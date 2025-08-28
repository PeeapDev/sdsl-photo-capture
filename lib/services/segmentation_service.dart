import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

/// Lightweight person segmentation using a TFLite model (e.g., MediaPipe Selfie Segmentation).
/// - Expects an asset at assets/models/selfie_segmentation.tflite
/// - Input: RGBA bytes
/// - Output: grayscale mask (0..255), same size as input
class SegmentationService {
  static tfl.Interpreter? _interpreter;
  static int _inputW = 256;
  static int _inputH = 256;
  static bool _loadingTried = false;

  static Future<bool> _ensureLoaded() async {
    if (_interpreter != null) return true;
    if (_loadingTried) return false;
    _loadingTried = true;
    try {
      final options = tfl.InterpreterOptions()..threads = 2;
      final interpreter = await tfl.Interpreter.fromAsset(
        'assets/models/selfie_segmentation.tflite',
        options: options,
      );
      _interpreter = interpreter;
      // Try to infer input size from input tensor
      final inputTensor = interpreter.getInputTensors().first;
      final shape = inputTensor.shape;
      if (shape.length >= 4) {
        // [1, height, width, channels]
        _inputH = shape[1];
        _inputW = shape[2];
      }
      return true;
    } catch (_) {
      _interpreter = null;
      return false;
    }
  }

  /// Returns a mask image (Image from `package:image`) in original size, grayscale 0..255.
  /// Returns null if model not available.
  /// Run segmentation from a package:image Image directly
  static Future<img.Image?> segmentFromImage(img.Image source) async {
    if (!await _ensureLoaded()) return null;
    final interpreter = _interpreter!;

    final origW = source.width;
    final origH = source.height;
    final resized = img.copyResize(source, width: _inputW, height: _inputH, interpolation: img.Interpolation.average);

    // Build normalized input [1,H,W,3]
    final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
    final input = List.generate(1, (_) => List.generate(_inputH, (_) => List.filled(_inputW * 3, 0.0)));
    int k = 0;
    for (int y = 0; y < _inputH; y++) {
      for (int x = 0; x < _inputW; x++) {
        final r = rgb[k++] / 255.0;
        final g = rgb[k++] / 255.0;
        final b = rgb[k++] / 255.0;
        input[0][y][x * 3 + 0] = r;
        input[0][y][x * 3 + 1] = g;
        input[0][y][x * 3 + 2] = b;
      }
    }

    var output = List.generate(1, (_) => List.generate(_inputH, (_) => List.filled(_inputW, 0.0)));
    try {
      interpreter.run(input, output);
    } catch (_) {
      return null;
    }

    // Build RGB grayscale mask and upscale to original size
    final maskSmall = img.Image(width: _inputW, height: _inputH);
    for (int y = 0; y < _inputH; y++) {
      for (int x = 0; x < _inputW; x++) {
        final v = (output[0][y][x] * 255.0).clamp(0.0, 255.0).toInt();
        maskSmall.setPixelRgb(x, y, v, v, v);
      }
    }
    final mask = img.copyResize(maskSmall, width: origW, height: origH, interpolation: img.Interpolation.average);
    return img.gaussianBlur(mask, radius: 1);
  }
}
