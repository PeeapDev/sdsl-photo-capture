import 'package:flutter/material.dart';

class FaceOverlay extends StatelessWidget {
  final double cr80Ratio; // width/height
  const FaceOverlay({super.key, required this.cr80Ratio});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Compute guide rectangle that fits screen with CR80 ratio
        double guideW = w * 0.9; // margin
        double guideH = guideW / cr80Ratio;
        if (guideH > h * 0.8) {
          guideH = h * 0.8;
          guideW = guideH * cr80Ratio;
        }

        return Stack(
          children: [
            // Darken outside area
            CustomPaint(
              size: Size(w, h),
              painter: _MaskPainter(Size(guideW, guideH)),
            ),
            // Corner lines for the guide
            Center(
              child: SizedBox(
                width: guideW,
                height: guideH,
                child: CustomPaint(
                  painter: _GuidePainter(),
                ),
              ),
            ),
            // Simple face hint
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.account_circle, color: Colors.white70, size: 64),
                  SizedBox(height: 4),
                  Text(
                    'Center face inside the frame',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MaskPainter extends CustomPainter {
  final Size guideSize;
  _MaskPainter(this.guideSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectXY(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: guideSize.width,
        height: guideSize.height,
      ),
      16,
      16,
    );

    // Draw full screen dark
    canvas.drawRect(rect, paint);
    // Cutout center guide
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, paint);
    canvas.drawRRect(rrect, clearPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const corner = 28.0;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Corners
    // Top-left
    canvas.drawLine(const Offset(0, 0), Offset(corner, 0), stroke);
    canvas.drawLine(const Offset(0, 0), Offset(0, corner), stroke);
    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - corner, 0), stroke);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, corner), stroke);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - corner), stroke);
    canvas.drawLine(Offset(0, size.height), Offset(corner, size.height), stroke);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - corner, size.height), stroke);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - corner), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
