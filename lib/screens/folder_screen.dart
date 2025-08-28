import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import '../services/pin_service.dart';

import '../screens/camera_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderItem {
  final String name;
  final String path;
  final DateTime modified;
  _FolderItem(this.name, this.path, this.modified);
}

class _FolderScreenState extends State<FolderScreen> {
  final TextEditingController _schoolCtrl = TextEditingController();
  String? _deviceLabel; // e.g., Device1
  List<_FolderItem> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _resolveDeviceLabel();
  }

  Future<int> _countImagesIn(String path) async {
    final exts = {'.jpg', '.jpeg', '.png', '.heic', '.heif'};
    int count = 0;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return 0;
      final all = await dir.list(recursive: true, followLinks: false).toList();
      for (final e in all) {
        if (e is File) {
          if (exts.contains(p.extension(e.path).toLowerCase())) count++;
        }
      }
    } catch (_) {}
    return count;
  }

  Future<String> _createNewSession(String folderPath, String folderName) async {
    // Not used any more for auto session naming; kept for potential future use
    const baseName = 'New folder';
    String candidate = p.join(folderPath, baseName);
    int i = 1;
    while (await Directory(candidate).exists()) {
      candidate = p.join(folderPath, '$baseName ($i)');
      i++;
    }
    final dir = Directory(candidate);
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String?> _promptAndCreateNewSession(String folderPath, String folderName) async {
    const defaultBase = 'New folder';

    final ctrl = TextEditingController(text: defaultBase);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New session name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter session name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (input == null) return null;
    String baseName = input.trim();
    if (baseName.isEmpty) baseName = defaultBase;
    String candidate = p.join(folderPath, baseName);
    int i = 1;
    while (await Directory(candidate).exists()) {
      candidate = p.join(folderPath, '$baseName ($i)');
      i++;
    }
    final dir = Directory(candidate);
    await dir.create(recursive: true);
    return dir.path;
  }

  String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  Future<void> _resolveDeviceLabel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _deviceLabel = a.model.replaceAll(' ', '');
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _deviceLabel = i.name.replaceAll(' ', '');
      } else {
        _deviceLabel = 'Device1';
      }
    } catch (_) {
      _deviceLabel = 'Device1';
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadFolders() async {
    final base = await _appBaseDir();
    final list = await base.list(followLinks: false).toList();
    final dirs = <_FolderItem>[];
    for (final e in list) {
      if (e is Directory) {
        try {
          final stat = await e.stat();
          dirs.add(_FolderItem(p.basename(e.path), e.path, stat.modified));
        } catch (_) {}
      }
    }
    dirs.sort((a, b) => b.modified.compareTo(a.modified));
    setState(() => _folders = dirs);
  }

  Future<Directory> _appBaseDir() async {
    // Use app documents directory for sandboxed storage (no extra permissions)
    final dir = await getApplicationDocumentsDirectory();
    final base = Directory('${dir.path}/SchoolPhotoCapture');
    if (!await base.exists()) await base.create(recursive: true);
    return base;
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

  Future<void> _deleteFolder(String folderPath) async {
    final allow = await _ensureAndVerifyPin();
    if (!allow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrect or cancelled.')));
      return;
    }
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      await _loadFolders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _createOrSelectFolder(String name) async {
    final base = await _appBaseDir();
    final normalized = name.trim();
    final folder = Directory(p.join(base.path, normalized));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    await _loadFolders();
  }

  Future<void> _promptNewFolder() async {
    _schoolCtrl.clear();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create New Folder',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schoolCtrl,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'e.g. Academy_School',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.folder_outlined),
                ),
                onSubmitted: (_) async {
                  if (_schoolCtrl.text.trim().isEmpty) return;
                  await _createOrSelectFolder(_schoolCtrl.text);
                  if (mounted) Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  if (_schoolCtrl.text.trim().isEmpty) return;
                  await _createOrSelectFolder(_schoolCtrl.text);
                  if (mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Create & Use'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportFolderAsZip(String folderName, String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;
    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, '${folderName}_${DateTime.now().millisecondsSinceEpoch}.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    encoder.addDirectory(dir);
    encoder.close();
    await SharePlus.instance.share(ShareParams(files: [XFile(zipPath)], text: 'Export for $folderName'));
  }

  // Removed auto session creation logic; folders can directly contain images and subfolders.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SDSL Photo Capture'),
        centerTitle: true,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptNewFolder,
        icon: const Icon(Icons.add),
        label: const Text('New Folder'),
      ),
      bottomNavigationBar: null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _folders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.folder_open, size: 72, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No folders yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      SizedBox(height: 6),
                      Text('Tap + to create a new one'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFolders,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 160,
                    ),
                    itemCount: _folders.length,
                    itemBuilder: (ctx, i) {
                      final f = _folders[i];
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            if (!mounted) return;
                            await Navigator.pushNamed(
                              context,
                              '/folderDetail',
                              arguments: {
                                'name': f.name,
                                'path': f.path, // open the main folder directly
                              },
                            );
                            if (!mounted) return;
                            await _loadFolders();
                          },
                          onLongPress: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete folder?'),
                                content: Text(f.name),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _deleteFolder(f.path);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const CircleAvatar(child: Icon(Icons.folder)),
                                    const Spacer(),
                                    PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'export') {
                                          await _exportFolderAsZip(f.name, f.path);
                                        } else if (v == 'new') {
                                          final newPath = await _promptAndCreateNewSession(f.path, f.name);
                                          if (newPath != null) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Created: ${p.basename(newPath)}')),
                                            );
                                            await Navigator.pushNamed(
                                              context,
                                              '/folderDetail',
                                              arguments: {
                                                'name': p.basename(newPath),
                                                'path': newPath,
                                              },
                                            );
                                            if (!mounted) return;
                                            await _loadFolders();
                                          }
                                        }
                                      },
                                      itemBuilder: (ctx) => const [
                                        PopupMenuItem(value: 'export', child: Text('Export ZIP & Share')),
                                        PopupMenuItem(value: 'new', child: Text('New subfolder')),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  f.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _fmtDate(f.modified),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                FutureBuilder<int>(
                                  future: _countImagesIn(f.path),
                                  builder: (ctx, snap) {
                                    final n = snap.data;
                                    final label = n == null ? 'Counting…' : (n == 1 ? '1 file' : '$n files');
                                    return Text(
                                      label,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
