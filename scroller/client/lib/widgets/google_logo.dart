import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Official-style multicolor Google "G" mark.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Blue: right side + bar into the G opening
    arcPaint.color = _blue;
    canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, arcPaint);
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(size.width - stroke * 0.35, center.dy),
      arcPaint,
    );

    // Red: top arc
    arcPaint.color = _red;
    canvas.drawArc(rect, -math.pi, math.pi / 2, false, arcPaint);

    // Yellow: bottom-left arc
    arcPaint.color = _yellow;
    canvas.drawArc(rect, math.pi / 2, math.pi / 2, false, arcPaint);

    // Green: bottom-right arc
    arcPaint.color = _green;
    canvas.drawArc(rect, 0, math.pi / 2, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
