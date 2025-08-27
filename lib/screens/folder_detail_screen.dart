import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'camera_screen.dart';

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
  List<FileSystemEntity> _images = [];
  bool _loading = true;
  late String _activeSessionPath;

  @override
  void initState() {
    super.initState();
    _activeSessionPath = widget.sessionPath;
    _loadImages();
  }

  Future<void> _loadImages() async {
    final dir = Directory(_activeSessionPath);
    final exts = {'.jpg', '.jpeg', '.png', '.heic', '.heif'};
    final all = await dir.list(recursive: false, followLinks: false).toList();
    final imgs = all.whereType<File>().where((f) => exts.contains(p.extension(f.path).toLowerCase())).toList();
    imgs.sort((a, b) => File(b.path).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()));
    if (!mounted) return;
    setState(() {
      _images = imgs;
      _loading = false;
    });
  }

  Future<void> _exportAsZip() async {
    try {
      final tmp = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = p.join(tmp.path, '${widget.folderName}_$stamp.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(Directory(_activeSessionPath));
      encoder.close();

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          text: 'Export from ${widget.folderName}',
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
      final parent = p.dirname(_activeSessionPath);
      final today = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final dateStr = '${today.year}-${two(today.month)}-${two(today.day)}';
      // Keep device label generic; detail screen doesn't resolve device info.
      const device = 'Device1';
      String defaultBase = '${widget.folderName}_${dateStr}_$device';

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
      String baseName = input.trim().replaceAll(' ', '_');
      if (baseName.isEmpty) baseName = defaultBase;
      String candidate = p.join(parent, baseName);
      int i = 1;
      while (await Directory(candidate).exists()) {
        candidate = p.join(parent, '${baseName}_$i');
        i++;
      }
      final dir = Directory(candidate);
      await dir.create(recursive: true);
      if (!mounted) return;
      setState(() {
        _activeSessionPath = dir.path;
        _loading = true;
      });
      await _loadImages();
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
        title: Text(widget.folderName),
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
          await Navigator.pushNamed(context, CameraScreen.routeName, arguments: _activeSessionPath);
          // Reload images after returning from camera
          if (mounted) _loadImages();
        },
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Open Camera'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const ListTile(
                leading: CircleAvatar(child: Icon(Icons.photo_library_outlined)),
                title: Text('Images'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _images.isEmpty
                      ? const Center(child: Text('No images yet'))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                          itemCount: _images.length,
                          itemBuilder: (ctx, i) {
                            final f = _images[i] as File;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                f,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: Color(0x11000000),
                                  child: Center(child: Icon(Icons.broken_image)),
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
