import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/zones_provider.dart';
import '../providers/home_zone_counts_provider.dart';
import '../models/zones_models.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const Set<String> _clickableHomeZones = {'Block A', 'Block B'};
  final GlobalKey _mapKey = GlobalKey();
  final double _mapOriginalWidth = 1920;
  final double _mapOriginalHeight = 1080;

  int? _draggingIndex;
  Offset? _dragStartPointerPos;
  Offset? _dragStartZonePos;
  bool _hasMovedSignificantly = false;
  bool _zoneEditMode = false;
  final double _dragThreshold = 6.0;
  static const BoxFit _mapFit = BoxFit.contain;

  Rect _resolveMapRect(BoxConstraints constraints) {
    final sourceSize = const Size(1920, 1080);
    final destinationSize = Size(constraints.maxWidth, constraints.maxHeight);
    final fitted = applyBoxFit(_mapFit, sourceSize, destinationSize);
    final dx = (destinationSize.width - fitted.destination.width) / 2;
    final dy = (destinationSize.height - fitted.destination.height) / 2;
    return Rect.fromLTWH(
      dx,
      dy,
      fitted.destination.width,
      fitted.destination.height,
    );
  }

  void _setZoneEditMode(bool enabled) {
    setState(() {
      _zoneEditMode = enabled;
      _draggingIndex = null;
      _dragStartPointerPos = null;
      _dragStartZonePos = null;
    });
  }

  void _startZoneDrag(int index, ZoneButton btn, Offset globalPosition) {
    ref.read(zonesProvider.notifier).beginCoordinateEdit();
    setState(() {
      _draggingIndex = index;
      _dragStartPointerPos = globalPosition;
      _dragStartZonePos = Offset(btn.xCoordinate, btn.yCoordinate);
      _hasMovedSignificantly = false;
    });
  }

  void _updateZoneDrag(
    BoxConstraints constraints,
    int index,
    ZoneButton btn,
    Offset globalPosition,
  ) {
    if (_draggingIndex != index ||
        _dragStartPointerPos == null ||
        _dragStartZonePos == null) {
      return;
    }

    final mapRect = _resolveMapRect(constraints);
    final delta = globalPosition - _dragStartPointerPos!;
    if (!_hasMovedSignificantly && delta.distance > _dragThreshold) {
      _hasMovedSignificantly = true;
    }

    final mapDeltaX = (delta.dx / mapRect.width) * _mapOriginalWidth;
    final mapDeltaY = (delta.dy / mapRect.height) * _mapOriginalHeight;

    final newX = (_dragStartZonePos!.dx + mapDeltaX).clamp(
      0.0,
      _mapOriginalWidth,
    );
    final newY = (_dragStartZonePos!.dy + mapDeltaY).clamp(
      0.0,
      _mapOriginalHeight,
    );

    ref
        .read(zonesProvider.notifier)
        .updateZoneLayout(
          index,
          btn.copyWith(xCoordinate: newX, yCoordinate: newY),
          persist: false,
        );
  }

  void _endZoneDrag(int index) {
    var committed = false;
    if (_draggingIndex == index && _hasMovedSignificantly) {
      final zonesData = ref.read(zonesProvider).zonesData;
      ref
          .read(zonesProvider.notifier)
          .updateZoneLayout(
            index,
            zonesData.homePageBlockButtons[index],
            persist: true,
          );
      committed = true;
    }
    if (!committed) {
      ref.read(zonesProvider.notifier).endCoordinateEdit();
    }
    setState(() {
      _draggingIndex = null;
    });
  }

  void _handleMapTap(
    BuildContext context,
    ZonesData data,
    BoxConstraints constraints,
    TapUpDetails details,
  ) {
    if (_zoneEditMode) {
      return;
    }

    final mapRect = _resolveMapRect(constraints);
    final tap = details.localPosition;
    final tapInMap = Offset(
      (tap.dx - mapRect.left).clamp(0.0, mapRect.width),
      (tap.dy - mapRect.top).clamp(0.0, mapRect.height),
    );
    final mapX = (tapInMap.dx / mapRect.width) * _mapOriginalWidth;
    final mapY = (tapInMap.dy / mapRect.height) * _mapOriginalHeight;
    final resolvedZone = _resolveZoneFromMapPoint(data, mapX, mapY);
    if (resolvedZone == null) {
      return;
    }

    context.push('/zone-preview?zone=${Uri.encodeComponent(resolvedZone)}');
  }

  String? _resolveZoneFromMapPoint(ZonesData data, double mapX, double mapY) {
    ZoneButton? nearest;
    var minDistance = double.infinity;
    for (final zone in data.homePageBlockButtons.where(
      (z) => z.active && _clickableHomeZones.contains(z.buttonName),
    )) {
      final dx = zone.xCoordinate - mapX;
      final dy = zone.yCoordinate - mapY;
      final d = dx * dx + dy * dy;
      if (d < minDistance) {
        minDistance = d;
        nearest = zone;
      }
    }
    return nearest?.buttonName;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final zonesState = ref.watch(zonesProvider);
    final zoneCounts = ref.watch(homeZoneCountsProvider);
    final isAdmin = authState.user?.role == UserRole.admin;

    final data = zonesState.zonesData;

    return Scaffold(
      body: Column(
        children: [
          _buildHero(isAdmin: isAdmin),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _mapOriginalWidth / _mapOriginalHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mapRect = _resolveMapRect(constraints);

                    return ClipRect(
                      child: Stack(
                        key: _mapKey,
                        children: [
                          // 1. Background Image
                          Image.asset(
                            'assets/images/serenity_hotel_view.png',
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            fit: _mapFit,
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) => _handleMapTap(
                                context,
                                data,
                                constraints,
                                details,
                              ),
                            ),
                          ),
                          // 3. Labels Layer
                          ...data.homePageBlockButtons.asMap().entries.map((
                            entry,
                          ) {
                            final index = entry.key;
                            final btn = entry.value;
                            return _buildZoneLabel(
                              context,
                              index,
                              btn,
                              mapRect,
                              constraints,
                              isAdmin,
                              zoneCounts[btn.buttonName]?.alarms ?? 0,
                              zoneCounts[btn.buttonName]?.delayedServices ?? 0,
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero({required bool isAdmin}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Steinkjer Hotel',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            FilterChip(
              label: const Text('Edit Zones'),
              selected: _zoneEditMode,
              onSelected: (value) => _setZoneEditMode(value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneLabel(
    BuildContext context,
    int index,
    ZoneButton btn,
    Rect mapRect,
    BoxConstraints constraints,
    bool isAdmin,
    int alarmCount,
    int serviceCount,
  ) {
    final xPercent = btn.xCoordinate / _mapOriginalWidth;
    final yPercent = btn.yCoordinate / _mapOriginalHeight;

    final left = mapRect.left + (xPercent * mapRect.width);
    final top = mapRect.top + (yPercent * mapRect.height);

    final isDragging = _draggingIndex == index;
    final tooltipText =
        '${btn.uiDisplayName} - $alarmCount alarm${alarmCount == 1 ? '' : 's'}, '
        '$serviceCount delayed service${serviceCount == 1 ? '' : 's'}';

    return Positioned(
      left: left,
      top: top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () {
            if (_zoneEditMode) {
              return;
            }
            if (!_hasMovedSignificantly &&
                btn.active &&
                _clickableHomeZones.contains(btn.buttonName)) {
              final target = btn.buttonName;
              context.push('/zone-preview?zone=${Uri.encodeComponent(target)}');
            }
          },
          child: MouseRegion(
            cursor:
                ((btn.active && _clickableHomeZones.contains(btn.buttonName)) ||
                    isAdmin)
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Tooltip(
              message: tooltipText,
              child: Semantics(
                label: tooltipText,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isDragging
                                    ? Colors.blue
                                    : (btn.active
                                          ? Colors.black
                                          : Colors.grey[700]!))
                                .withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDragging
                              ? Colors.white
                              : (btn.active ? Colors.blue : Colors.transparent),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            btn.uiDisplayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (alarmCount > 0 || serviceCount > 0) ...[
                            const SizedBox(width: 8),
                            _buildBadgeGroup(alarmCount, serviceCount),
                          ],
                        ],
                      ),
                    ),
                    if (isAdmin && _zoneEditMode) ...[
                      _buildDragHandle(
                        alignment: Alignment.topLeft,
                        onPanStart: (d) =>
                            _startZoneDrag(index, btn, d.globalPosition),
                        onPanUpdate: (d) => _updateZoneDrag(
                          constraints,
                          index,
                          btn,
                          d.globalPosition,
                        ),
                        onPanEnd: (_) => _endZoneDrag(index),
                      ),
                      _buildDragHandle(
                        alignment: Alignment.topRight,
                        onPanStart: (d) =>
                            _startZoneDrag(index, btn, d.globalPosition),
                        onPanUpdate: (d) => _updateZoneDrag(
                          constraints,
                          index,
                          btn,
                          d.globalPosition,
                        ),
                        onPanEnd: (_) => _endZoneDrag(index),
                      ),
                      _buildDragHandle(
                        alignment: Alignment.bottomLeft,
                        onPanStart: (d) =>
                            _startZoneDrag(index, btn, d.globalPosition),
                        onPanUpdate: (d) => _updateZoneDrag(
                          constraints,
                          index,
                          btn,
                          d.globalPosition,
                        ),
                        onPanEnd: (_) => _endZoneDrag(index),
                      ),
                      _buildDragHandle(
                        alignment: Alignment.bottomRight,
                        onPanStart: (d) =>
                            _startZoneDrag(index, btn, d.globalPosition),
                        onPanUpdate: (d) => _updateZoneDrag(
                          constraints,
                          index,
                          btn,
                          d.globalPosition,
                        ),
                        onPanEnd: (_) => _endZoneDrag(index),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeGroup(int alarms, int services) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (alarms > 0) _buildBadge(alarms.toString(), Colors.redAccent),
        if (alarms > 0 && services > 0) const SizedBox(width: 4),
        if (services > 0) _buildBadge(services.toString(), Colors.orangeAccent),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDragHandle({
    required Alignment alignment,
    required GestureDragStartCallback onPanStart,
    required GestureDragUpdateCallback onPanUpdate,
    required GestureDragEndCallback onPanEnd,
  }) {
    final dx = alignment.x < 0 ? -6.0 : null;
    final right = alignment.x > 0 ? -6.0 : null;
    final dy = alignment.y < 0 ? -6.0 : null;
    final bottom = alignment.y > 0 ? -6.0 : null;

    return Positioned(
      left: dx,
      right: right,
      top: dy,
      bottom: bottom,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.lightBlueAccent.withOpacity(0.95),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
