import 'dart:io';
import 'package:image/image.dart' as img;
import 'segmentation_service.dart';
import 'package:path_provider/path_provider.dart';

class ImageProcessor {
  /// Processes the captured image to fit CR80 aspect ratio with a white background.
  /// If segmentation becomes available later, integrate here. For now: crop/resize + white padding.
  static Future<File> processToWhiteBackground(
    File input, {
    required double targetAspectRatio, // width / height
    int targetLongSide = 1200,
    Map<String, int>? focusRectPx, // optional: {x,y,width,height} in original pixel coords
  }) async {
    final bytes = await input.readAsBytes();
    img.Image? original = img.decodeImage(bytes);
    if (original == null) return input;

    // Ensure correct orientation if EXIF present
    original = img.bakeOrientation(original);

    final int srcW = original.width;
    final int srcH = original.height;
    final double srcAR = srcW / srcH;

    // Compute a crop rect. If focusRectPx provided (e.g., face bbox), center crop around it
    // with extra headroom so the face sits in upper third.
    int cropX = 0, cropY = 0, cropW = srcW, cropH = srcH;
    if (focusRectPx != null) {
      final fx = focusRectPx['x'] ?? 0;
      final fy = focusRectPx['y'] ?? 0;
      final fw = focusRectPx['width'] ?? srcW;
      final fh = focusRectPx['height'] ?? srcH;

      // Desired box around face: slightly less tight to reduce "too big" result
      final desiredH = (fh * 2.3).clamp((targetAspectRatio < 1 ? fh * 1.9 : fh * 2.1), srcH.toDouble()).toDouble();
      final desiredW = (desiredH * targetAspectRatio).clamp(fw * 1.5, srcW.toDouble());

      // Position so that face center sits around upper 0.42 of the crop (slightly lower headroom)
      final faceCx = fx + fw / 2.0;
      final faceCy = fy + fh / 2.0;
      final cropCx = faceCx;
      final cropCy = faceCy + desiredH * (0.42 - 0.5); // shift up a bit

      cropW = desiredW.round();
      cropH = desiredH.round();
      cropX = (cropCx - cropW / 2).round();
      cropY = (cropCy - cropH / 2).round();

      // Clamp to image bounds
      cropX = cropX.clamp(0, srcW - cropW);
      cropY = cropY.clamp(0, srcH - cropH);
    } else {
      // Fallback: center crop to target aspect
      if (srcAR > targetAspectRatio) {
        cropH = srcH;
        cropW = (cropH * targetAspectRatio).round();
        cropX = ((srcW - cropW) / 2).round();
        cropY = 0;
      } else if (srcAR < targetAspectRatio) {
        cropW = srcW;
        cropH = (cropW / targetAspectRatio).round();
        cropX = 0;
        cropY = ((srcH - cropH) / 2).round();
      }
    }

    final cropped = img.copyCrop(original, x: cropX, y: cropY, width: cropW, height: cropH);

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

    // Add a small white margin (padding) so subject appears slightly smaller in final frame
    final pad = (canvasW * 0.06).round(); // ~6% padding
    final canvas = img.Image(width: canvasW + pad * 2, height: canvasH + pad * 2);
    // Fill white
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    // If segmentation model is available, cut out subject (alpha) and composite with white
    img.Image subjectOnWhite = resized;
    try {
      final mask = await SegmentationService.segmentFromImage(resized);
      if (mask != null && mask.width == resized.width && mask.height == resized.height) {
        final w = resized.width;
        final h = resized.height;
        final cut = img.Image(width: w, height: h);
        final srcBytes = resized.getBytes(order: img.ChannelOrder.rgb);
        final maskBytes = mask.getBytes(order: img.ChannelOrder.rgb);
        int si = 0; // source index in srcBytes
        int mi = 0; // mask index in maskBytes
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final mr = maskBytes[mi]; // grayscale mask replicated in r,g,b
            // alpha from mask (0..1)
            final a = mr / 255.0;
            final fr = srcBytes[si].toDouble();
            final fg = srcBytes[si + 1].toDouble();
            final fb = srcBytes[si + 2].toDouble();
            final r = (fr * a + 255.0 * (1 - a)).round().clamp(0, 255);
            final g = (fg * a + 255.0 * (1 - a)).round().clamp(0, 255);
            final b = (fb * a + 255.0 * (1 - a)).round().clamp(0, 255);
            cut.setPixelRgb(x, y, r, g, b);
            si += 3;
            mi += 3;
          }
        }
        subjectOnWhite = cut;
      }
    } catch (_) {
      // fallback silently
    }

    // Paste centered
    final offX = ((canvas.width - subjectOnWhite.width) / 2).round();
    final offY = ((canvas.height - subjectOnWhite.height) / 2).round();
    img.compositeImage(canvas, subjectOnWhite, dstX: offX, dstY: offY);

    // Encode JPEG
    final outBytes = img.encodeJpg(canvas, quality: 92);

    // Save to temp and return file
    final tmp = await getTemporaryDirectory();
    final outPath = '${tmp.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(outBytes);
    return outFile;
  }

  // Note: advanced background removal (segmentation) can be integrated here later if needed.
}
