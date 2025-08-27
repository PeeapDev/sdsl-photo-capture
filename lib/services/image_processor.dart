import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageProcessor {
  /// Processes the captured image to fit CR80 aspect ratio with a white background.
  /// If segmentation becomes available later, integrate here. For now: crop/resize + white padding.
  static Future<File> processToWhiteBackground(
    File input, {
    required double targetAspectRatio, // width / height (CR80 ~ 1.5882353)
    int targetLongSide = 1500, // reasonable resolution for ID photos
  }) async {
    final bytes = await input.readAsBytes();
    img.Image? original = img.decodeImage(bytes);
    if (original == null) return input;

    // Ensure correct orientation if EXIF present
    original = img.bakeOrientation(original);

    final int srcW = original.width;
    final int srcH = original.height;
    final double srcAR = srcW / srcH;

    late img.Image cropped;
    if (srcAR > targetAspectRatio) {
      // Source too wide -> crop width
      final newW = (srcH * targetAspectRatio).round();
      final x = ((srcW - newW) / 2).round();
      cropped = img.copyCrop(original, x: x, y: 0, width: newW, height: srcH);
    } else if (srcAR < targetAspectRatio) {
      // Source too tall -> crop height
      final newH = (srcW / targetAspectRatio).round();
      final y = ((srcH - newH) / 2).round();
      cropped = img.copyCrop(original, x: 0, y: y, width: srcW, height: newH);
    } else {
      cropped = original;
    }

    // Resize so the longer side is targetLongSide
    final int cw = cropped.width;
    final int ch = cropped.height;
    final bool widthIsLong = cw >= ch;
    final scale = targetLongSide / (widthIsLong ? cw : ch);
    final resized = img.copyResize(
      cropped,
      width: (cw * scale).round(),
      height: (ch * scale).round(),
      interpolation: img.Interpolation.average,
    );

    // Create exact canvas with white background in target ratio
    // Compute canvas dimensions preserving targetAspectRatio
    int canvasW, canvasH;
    if (resized.width / resized.height > targetAspectRatio) {
      canvasW = resized.width;
      canvasH = (canvasW / targetAspectRatio).round();
    } else {
      canvasH = resized.height;
      canvasW = (canvasH * targetAspectRatio).round();
    }

    final canvas = img.Image(width: canvasW, height: canvasH);
    // Fill white
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    // Paste centered
    final offX = ((canvasW - resized.width) / 2).round();
    final offY = ((canvasH - resized.height) / 2).round();
    img.compositeImage(canvas, resized, dstX: offX, dstY: offY);

    // Encode JPEG
    final outBytes = img.encodeJpg(canvas, quality: 92);

    // Save to temp and return file
    final tmp = await getTemporaryDirectory();
    final outPath = '${tmp.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(outBytes);
    return outFile;
  }
}
