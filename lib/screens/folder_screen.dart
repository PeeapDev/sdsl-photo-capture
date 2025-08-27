import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';

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

  Future<String> _createNewSession(String folderPath, String folderName) async {
    final today = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${today.year}-${two(today.month)}-${two(today.day)}';
    final device = _deviceLabel ?? 'Device1';
    String baseName = '${folderName}_${dateStr}_$device';
    String candidate = p.join(folderPath, baseName);
    int i = 1;
    while (await Directory(candidate).exists()) {
      candidate = p.join(folderPath, '${baseName}_$i');
      i++;
    }
    final dir = Directory(candidate);
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String?> _promptAndCreateNewSession(String folderPath, String folderName) async {
    final today = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${today.year}-${two(today.month)}-${two(today.day)}';
    final device = _deviceLabel ?? 'Device1';
    final defaultBase = '${folderName}_${dateStr}_$device';

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
    String baseName = input.trim().replaceAll(' ', '_');
    if (baseName.isEmpty) baseName = defaultBase;
    String candidate = p.join(folderPath, baseName);
    int i = 1;
    while (await Directory(candidate).exists()) {
      candidate = p.join(folderPath, '${baseName}_$i');
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

  Future<void> _createOrSelectFolder(String name) async {
    final base = await _appBaseDir();
    final normalized = name.trim().replaceAll(' ', '_');
    final folder = Directory(p.join(base.path, normalized));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    // Ensure at least one session folder exists
    await _getLatestOrCreateSession(folder.path, normalized);
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

  Future<String> _getLatestOrCreateSession(String folderPath, String folderName) async {
    final dir = Directory(folderPath);
    final subs = await dir.list(followLinks: false).toList();
    final sessionDirs = subs.whereType<Directory>().toList();
    if (sessionDirs.isEmpty) {
      final today = DateTime.now();
      final dateStr = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final device = _deviceLabel ?? 'Device1';
      final newSession = Directory(p.join(folderPath, '${folderName}_${dateStr}_$device'));
      await newSession.create(recursive: true);
      return newSession.path;
    }
    sessionDirs.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return sessionDirs.first.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Photo Capture'),
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
              : GridView.builder(
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
                          final session = await _getLatestOrCreateSession(f.path, f.name);
                          if (!mounted) return;
                          Navigator.pushNamed(
                            context,
                            '/folderDetail',
                            arguments: {
                              'name': f.name,
                              'path': session,
                            },
                          );
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
                                        if (newPath == null) return;
                                        if (!mounted) return;
                                        Navigator.pushNamed(
                                          context,
                                          '/folderDetail',
                                          arguments: {
                                            'name': f.name,
                                            'path': newPath,
                                          },
                                        );
                                      }
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(value: 'export', child: Text('Export ZIP & Share')),
                                      PopupMenuItem(value: 'new', child: Text('Add Folder (New Session)')),
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
                                'Created ${_fmtDate(f.modified)}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
    );
  }
}
