import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import '../services/image_processor.dart';

class NamingScreen extends StatefulWidget {
  final String imagePath; // processed temp image path
  final String sessionPath; // destination folder
  final double targetAspectRatio; // width/height from camera preset
  const NamingScreen({
    super.key,
    required this.imagePath,
    required this.sessionPath,
    required this.targetAspectRatio,
  });

  @override
  State<NamingScreen> createState() => _NamingScreenState();
}

class _NamingScreenState extends State<NamingScreen> {
  final _nameCtrl = TextEditingController();
  

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name.')),
      );
      return;
    }
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final filename = '$safeName.jpg';
    final destPath = '${widget.sessionPath}/$filename';

    final src = File(widget.imagePath);
    await src.copy(destPath);

    // Background post-save processing: enforce white background and strict guide crop
    // Run without blocking UI; replace file in place when done
    unawaited(() async {
      try {
        final processed = await ImageProcessor.processToWhiteBackground(
          File(destPath),
          targetAspectRatio: widget.targetAspectRatio,
          focusRectPx: null, // strict guide crop, ignore face bbox here
        );
        final outBytes = await processed.readAsBytes();
        await File(destPath).writeAsBytes(outBytes, flush: true);
      } catch (_) {}
    }());

    if (!mounted) return;
    Navigator.pop(context, filename);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Name Photo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                hintText: 'e.g., John Doe',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
