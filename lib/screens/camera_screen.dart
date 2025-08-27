import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/image_processor.dart';
import '../widgets/face_overlay.dart';
import 'naming_screen.dart';

class CameraScreen extends StatefulWidget {
  static const routeName = '/camera';
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  bool _isBusy = false;
  late final String sessionPath;

  // CR80 ratio = 3.375 x 2.125 => width:height ~ 1.588235294
  static const double _cr80Ratio = 3.375 / 2.125;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sessionPath = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    _init();
  }

  Future<void> _init() async {
    if (sessionPath.isEmpty) return;
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required.')),
        );
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
    if (mounted) setState(() => _initializing = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final file = await _controller!.takePicture();
      final processed = await ImageProcessor.processToWhiteBackground(
        File(file.path),
        targetAspectRatio: _cr80Ratio,
      );
      if (!mounted) return;
      final savedPath = processed.path;
      // Navigate to naming screen
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => NamingScreen(
            imagePath: savedPath,
            sessionPath: sessionPath,
          ),
        ),
      );
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $result')),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: Text('Camera not available')),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                // Show preview fitted into screen, overlay will show CR80 crop
                aspectRatio: max(1, _controller!.value.aspectRatio),
                child: CameraPreview(_controller!),
              ),
            ),
            // CR80 and face overlay
            const FaceOverlay(cr80Ratio: _cr80Ratio),
            Positioned(
              bottom: 24,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _capture,
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text('Capture', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
