import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'camera_screen.dart';
import '../services/pin_service.dart';

class FolderDetailScreen extends StatefulWidget {
  final String folderName;
  final String sessionPath;

  const FolderDetailScreen({
    super.key,
    required this.folderName,
    required this.sessionPath,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<File> _images = [];
  List<Directory> _subfolders = [];
  bool _loading = true;
  late String _currentPath;
  late String _currentName;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.sessionPath;
    _currentName = p.basename(_currentPath);
    _loadContent();
  }

  Future<bool> _ensureAndVerifyPin() async {
    final has = await PinService.hasPin();
    if (!has) {
      final setOk = await _promptSetPin();
      if (setOk != true) return false;
    }
    final ok = await _promptEnterPin();
    return ok == true;
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

  Future<void> _deleteImage(File f) async {
    final allow = await _ensureAndVerifyPin();
    if (!allow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrect or cancelled.')));
      return;
    }
    try {
      if (await f.exists()) await f.delete();
      await _loadContent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _loadContent() async {
    final dir = Directory(_currentPath);
    final exts = {'.jpg', '.jpeg', '.png', '.heic', '.heif'};
    final all = await dir.list(recursive: false, followLinks: false).toList();
    final folders = all.whereType<Directory>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    final imgs = all.whereType<File>().where((f) => exts.contains(p.extension(f.path).toLowerCase())).toList()
      ..sort((a, b) => File(b.path).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()));
    if (!mounted) return;
    setState(() {
      _subfolders = folders;
      _images = imgs;
      _loading = false;
    });
  }

  Future<void> _exportAsZip() async {
    try {
      final tmp = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = p.join(tmp.path, '${_currentName}_$stamp.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(Directory(_currentPath));
      encoder.close();

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          text: 'Export from ${_currentName}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _createNewSubfolder() async {
    try {
      final parent = _currentPath;
      const defaultBase = 'New folder';

      // Ask user for a custom name (prefilled with default)
      final nameCtrl = TextEditingController(text: defaultBase);
      final input = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('New subfolder name'),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter subfolder name'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(ctx).pop(nameCtrl.text),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(nameCtrl.text), child: const Text('Create')),
            ],
          );
        },
      );
      if (input == null) return; // cancelled
      String baseName = input.trim();
      if (baseName.isEmpty) baseName = defaultBase;
      String candidate = p.join(parent, baseName);
      int i = 1;
      while (await Directory(candidate).exists()) {
        candidate = p.join(parent, '$baseName ($i)');
        i++;
      }
      final dir = Directory(candidate);
      await dir.create(recursive: true);
      if (!mounted) return;
      setState(() {
        _loading = true;
      });
      await _loadContent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New subfolder created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create subfolder: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentName),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') await _exportAsZip();
              if (v == 'new') await _createNewSubfolder();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'export', child: Text('Export ZIP & Share')),
              PopupMenuItem(value: 'new', child: Text('New subfolder')),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, CameraScreen.routeName, arguments: _currentPath);
          // Reload images after returning from camera
          if (mounted) _loadContent();
        },
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Open Camera'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_subfolders.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Folders', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _subfolders.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          final d = _subfolders[i];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                '/folderDetail',
                                arguments: {
                                  'name': p.basename(d.path),
                                  'path': d.path,
                                },
                              );
                            },
                            child: Container(
                              width: 140,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(Icons.folder, size: 32),
                                  Text(
                                    p.basename(d.path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Images', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: _images.isEmpty
                        ? const Center(child: Text('No images yet'))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemCount: _images.length,
                            itemBuilder: (ctx, i) {
                              final f = _images[i];
                              final name = p.basename(f.path);
                              return Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () async {
                                    await Navigator.pushNamed(
                                      context,
                                      '/imageViewer',
                                      arguments: {
                                        'path': f.path,
                                        'folder': _currentPath,
                                      },
                                    );
                                    if (mounted) _loadContent();
                                  },
                                  onLongPress: () async {
                                    // Prompt delete with PIN
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete image?'),
                                        content: Text(name),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _deleteImage(f);
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.file(
                                            f,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const ColoredBox(
                                              color: Color(0x11000000),
                                              child: Center(child: Icon(Icons.broken_image)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
