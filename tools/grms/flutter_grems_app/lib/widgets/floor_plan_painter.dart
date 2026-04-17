import 'package:flutter/material.dart';

import '../utils/constants.dart';

class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({required this.polygons});

  final List<List<Offset>> polygons;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final polygon in polygons) {
      if (polygon.length < 3) continue;
      final path = Path();
      final first = polygon.first;
      path.moveTo(first.dx / mapOriginalWidth * size.width, first.dy / mapOriginalHeight * size.height);
      for (var i = 1; i < polygon.length; i++) {
        final p = polygon[i];
        path.lineTo(p.dx / mapOriginalWidth * size.width, p.dy / mapOriginalHeight * size.height);
      }
      path.close();
      paint.color = const Color(0x5540A4FF);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) => oldDelegate.polygons != polygons;
}
