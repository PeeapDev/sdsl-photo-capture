import 'dart:io';

import 'package:flutter/material.dart';

class NamingScreen extends StatefulWidget {
  final String imagePath; // processed temp image path
  final String sessionPath; // destination folder
  const NamingScreen({super.key, required this.imagePath, required this.sessionPath});

  @override
  State<NamingScreen> createState() => _NamingScreenState();
}

class _NamingScreenState extends State<NamingScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter first and last name.')),
      );
      return;
    }
    final safeFirst = first.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final safeLast = last.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final filename = '${safeFirst}_$safeLast.jpg';
    final destPath = '${widget.sessionPath}/$filename';

    final src = File(widget.imagePath);
    await src.copy(destPath);

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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lastCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save as FirstName_LastName.jpg'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
