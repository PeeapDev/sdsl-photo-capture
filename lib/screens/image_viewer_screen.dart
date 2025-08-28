import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../services/pin_service.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imagePath;
  final String folderPath;
  const ImageViewerScreen({super.key, required this.imagePath, required this.folderPath});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late File _file;
  late String _name;

  @override
  void initState() {
    super.initState();
    _file = File(widget.imagePath);
    _name = p.basename(widget.imagePath);
  }

  Future<void> _openEditor() async {
    try {
      if (!await _file.exists()) return;
      // Pre-resize very large images to avoid editor black screen on low-memory devices
      // and pass bytes directly to the editor (plugin is more stable with bytes than Image widget)
      Uint8List inputBytes = await _file.readAsBytes();
      try {
        final decoded = img.decodeImage(inputBytes);
        if (decoded != null) {
          final baked = img.bakeOrientation(decoded);
          final maxDim = baked.width > baked.height ? baked.width : baked.height;
          const limit = 1600; // tighter bound to reduce memory usage
          img.Image toUse = baked;
          if (maxDim > limit) {
            final scale = limit / maxDim;
            toUse = img.copyResize(
              baked,
              width: (baked.width * scale).round(),
              height: (baked.height * scale).round(),
              interpolation: img.Interpolation.average,
            );
          }
          inputBytes = Uint8List.fromList(img.encodeJpg(toUse, quality: 92));
        }
      } catch (_) {}

      final edited = await Navigator.push<List<int>?>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageEditor(image: inputBytes),
        ),
      );
      if (edited == null) return; // user cancelled
      // Flatten onto white and save as JPEG
      final src = img.decodeImage(Uint8List.fromList(edited));
      if (src != null) {
        final baked = img.bakeOrientation(src);
        final canvas = img.Image(width: baked.width, height: baked.height);
        img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(canvas, baked, dstX: 0, dstY: 0);
        final jpg = img.encodeJpg(canvas, quality: 92);
        await _file.writeAsBytes(jpg);
      } else {
        // Fallback: write bytes directly
        await _file.writeAsBytes(edited);
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit failed: $e')),
      );
    }
  }

  Future<bool> _ensureAndVerifyPin() async {
    final has = await PinService.hasPin();
    if (!has) {
      final ok = await _promptSetPin();
      if (ok != true) return false;
    }
    final ok2 = await _promptEnterPin();
    return ok2 == true;
  }

  Future<bool?> _promptSetPin() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set 4-digit PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c1,
              decoration: const InputDecoration(labelText: 'PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
            ),
            TextField(
              controller: c2,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (c1.text.length == 4 && c1.text == c2.text) {
                await PinService.setPin(c1.text);
                if (context.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _promptEnterPin() async {
    final c = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter PIN to Delete'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '4-digit PIN'),
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          onSubmitted: (_) async {
            final ok = await PinService.verifyPin(c.text);
            if (ctx.mounted) Navigator.pop(ctx, ok);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final ok = await PinService.verifyPin(c.text);
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteImage() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete image?'),
        content: Text(_name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    final allow = await _ensureAndVerifyPin();
    if (!allow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrect or cancelled.')));
      return;
    }
    try {
      if (await _file.exists()) await _file.delete();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit & Crop',
            onPressed: _openEditor,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _deleteImage,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.crop),
        label: const Text('Edit & Crop'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.file(
                  _file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Cannot load image'),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_name, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ),
        ],
      ),
    );
  }
}
