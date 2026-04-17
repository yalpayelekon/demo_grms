import 'package:flutter/material.dart';

import '../models/zone_button.dart';
import '../utils/constants.dart';

class ZoneButtonWidget extends StatelessWidget {
  const ZoneButtonWidget({
    super.key,
    required this.zone,
    required this.onTap,
    required this.onDrag,
    required this.isAdmin,
    required this.alarms,
    required this.delayed,
  });

  final ZoneButton zone;
  final VoidCallback onTap;
  final void Function(double x, double y)? onDrag;
  final bool isAdmin;
  final int alarms;
  final int delayed;

  @override
  Widget build(BuildContext context) {
    final left = zone.xCoordinate / mapOriginalWidth;
    final top = zone.yCoordinate / mapOriginalHeight;

    return FractionalTranslation(
      translation: Offset(left - 0.5, top - 0.5),
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: isAdmin
            ? (details) {
                final rb = context.findRenderObject() as RenderBox?;
                final parent = rb?.parent as RenderBox?;
                final size = parent?.size;
                if (size == null) return;
                final local = (rb?.localToGlobal(Offset.zero) ?? Offset.zero) + details.delta;
                final x = (local.dx / size.width).clamp(0, 1) * mapOriginalWidth;
                final y = (local.dy / size.height).clamp(0, 1) * mapOriginalHeight;
                onDrag?.call(x, y);
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: zone.active ? Colors.black87 : Colors.black45,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(zone.uiDisplayName),
              if (alarms > 0) Padding(padding: const EdgeInsets.only(left: 6), child: CircleAvatar(radius: 9, child: Text('$alarms', style: const TextStyle(fontSize: 10)))),
              if (delayed > 0) Padding(padding: const EdgeInsets.only(left: 6), child: CircleAvatar(backgroundColor: Colors.orange, radius: 9, child: Text('$delayed', style: const TextStyle(fontSize: 10)))),
            ],
          ),
        ),
      ),
    );
  }
}
