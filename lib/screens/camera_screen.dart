import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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
  int _cameraIndex = 0; // track current camera
  bool _initializing = true;
  bool _isBusy = false;
  String _sessionPath = '';
  int _shots = 0; // per-session shot counter

  // Portrait presets (width/height). Defaults to 35x45mm passport style.
  static const Map<String, double> _presets = {
    '35×45 mm': 35 / 45, // ~0.7778
    '30×40 mm': 30 / 40, // 0.75
    '2×2 in': 1.0,       // square
  };
  String _selectedPreset = '35×45 mm';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Force portrait while on the camera screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessionPath = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    _init();
  }

  Future<void> _init() async {
    if (_sessionPath.isEmpty) {
      if (mounted) setState(() => _initializing = false);
      return;
    }
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      if (mounted) {
        setState(() => _initializing = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Camera permission needed'),
            content: const Text('Please allow camera access to take photos.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      // set default to back camera
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cameraIndex == -1) _cameraIndex = 0;
      _controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();
      // Lock capture orientation to portrait
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    try {
      setState(() => _initializing = true);
      await _controller?.dispose();
      _controller = CameraController(
        _cameras[next],
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();
      // Lock capture orientation to portrait after switching
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() {
        _cameraIndex = next;
        _initializing = false;
      });
    } catch (e) {
      debugPrint('Switch camera error: $e');
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<Map<String, int>?> _detectFaceRect(String imagePath) async {
    try {
      final options = FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
      );
      final detector = FaceDetector(options: options);
      final input = InputImage.fromFilePath(imagePath);
      final faces = await detector.processImage(input);
      await detector.close();
      if (faces.isEmpty) return null;
      // pick the largest face
      Rect best = faces.first.boundingBox;
      double bestArea = best.width * best.height;
      for (final f in faces.skip(1)) {
        final r = f.boundingBox;
        final a = r.width * r.height;
        if (a > bestArea) {
          best = r;
          bestArea = a;
        }
      }
      return {
        'x': best.left.round(),
        'y': best.top.round(),
        'width': best.width.round(),
        'height': best.height.round(),
      };
    } catch (e) {
      debugPrint('Face detect error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // Restore orientations to allow all (system default)
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
      // Enforce strict guide crop: ignore face rect so we always crop to preset aspect ratio
      // If you want face-guided framing, restore: final faceRect = await _detectFaceRect(file.path);
      final Map<String, int>? faceRect = null;
      final processed = await ImageProcessor.processToWhiteBackground(
        File(file.path),
        targetAspectRatio: _presets[_selectedPreset]!,
        focusRectPx: faceRect,
      );
      if (!mounted) return;
      final savedPath = processed.path;
      // Navigate to naming screen
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => NamingScreen(
            imagePath: savedPath,
            sessionPath: _sessionPath,
            targetAspectRatio: _presets[_selectedPreset]!,
          ),
        ),
      );
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $result')),
        );
        setState(() => _shots++);
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
            // Render preview in true portrait AR using previewSize
            Builder(builder: (_) {
              final size = _controller!.value.previewSize;
              // On many devices, previewSize is in landscape (width > height). For portrait UI, flip it.
              final portraitAR = size != null
                  ? (size.height / size.width)
                  : (1 / _controller!.value.aspectRatio);
              return Center(
                child: AspectRatio(
                  aspectRatio: portraitAR,
                  child: CameraPreview(_controller!),
                ),
              );
            }),
            // Portrait overlay with faint head/shoulders guide
            FaceOverlay(cr80Ratio: _presets[_selectedPreset]!),
            // Preset selector at top center
            Positioned(
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _presets.keys.map((k) {
                    final sel = k == _selectedPreset;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(k),
                        selected: sel,
                        onSelected: (v) {
                          if (v) setState(() => _selectedPreset = k);
                        },
                        selectedColor: Colors.indigo,
                        labelStyle: TextStyle(color: sel ? Colors.white : Colors.white70, fontSize: 12),
                        backgroundColor: Colors.transparent,
                        shape: StadiumBorder(side: BorderSide(color: Colors.white24)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // Shots counter at top-right
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Shots: $_shots',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _capture,
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text('Capture', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _initializing ? null : _switchCamera,
                    icon: const Icon(Icons.cameraswitch),
                    label: const Text('Switch'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  ),
                ],
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
