import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/zones_models.dart';
import '../providers/auth_provider.dart';
import '../providers/zones_provider.dart';

class ZonePreviewPage extends ConsumerStatefulWidget {
  const ZonePreviewPage({super.key, this.initialZone});

  final String? initialZone;

  @override
  ConsumerState<ZonePreviewPage> createState() => _ZonePreviewPageState();
}

class _ZonePreviewPageState extends ConsumerState<ZonePreviewPage> {
  static const double _mapOriginalWidth = 1920;
  static const double _mapOriginalHeight = 1080;
  static const double _dragThreshold = 6;

  int? _draggingFloorIndex;
  Offset? _dragStartPointerPos;
  Offset? _dragStartFloorPos;
  bool _hasMovedSignificantly = false;
  bool _floorEditMode = false;

  void _setFloorEditMode(bool enabled) {
    setState(() {
      _floorEditMode = enabled;
      _draggingFloorIndex = null;
      _dragStartPointerPos = null;
      _dragStartFloorPos = null;
      _hasMovedSignificantly = false;
    });
  }

  void _startFloorDrag(int index, Offset initialPoint, Offset globalPosition) {
    ref.read(zonesProvider.notifier).beginCoordinateEdit();
    setState(() {
      _draggingFloorIndex = index;
      _dragStartPointerPos = globalPosition;
      _dragStartFloorPos = initialPoint;
      _hasMovedSignificantly = false;
    });
  }

  void _updateFloorDrag({
    required BoxConstraints constraints,
    required String zoneId,
    required String floor,
    required int index,
    required Offset globalPosition,
  }) {
    if (_draggingFloorIndex != index ||
        _dragStartPointerPos == null ||
        _dragStartFloorPos == null) {
      return;
    }
    final delta = globalPosition - _dragStartPointerPos!;
    if (!_hasMovedSignificantly && delta.distance > _dragThreshold) {
      _hasMovedSignificantly = true;
    }

    final mapDeltaX = (delta.dx / constraints.maxWidth) * _mapOriginalWidth;
    final mapDeltaY = (delta.dy / constraints.maxHeight) * _mapOriginalHeight;
    final nextPoint = Offset(
      (_dragStartFloorPos!.dx + mapDeltaX).clamp(0.0, _mapOriginalWidth),
      (_dragStartFloorPos!.dy + mapDeltaY).clamp(0.0, _mapOriginalHeight),
    );

    ref
        .read(zonesProvider.notifier)
        .updateFloorButtonPosition(
          zoneId,
          floor,
          ZonePoint(x: nextPoint.dx, y: nextPoint.dy),
          persist: false,
        );
  }

  void _endFloorDrag({
    required String zoneId,
    required String floor,
    required int index,
  }) {
    var committed = false;
    if (_draggingFloorIndex == index && _hasMovedSignificantly) {
      final zonesData = ref.read(zonesProvider).zonesData;
      final persisted = zonesData.floorButtonPositions[zoneId]?[floor];
      if (persisted != null) {
        ref
            .read(zonesProvider.notifier)
            .updateFloorButtonPosition(zoneId, floor, persisted, persist: true);
        committed = true;
      }
    }
    if (!committed) {
      ref.read(zonesProvider.notifier).endCoordinateEdit();
    }
    setState(() {
      _draggingFloorIndex = null;
      _dragStartPointerPos = null;
      _dragStartFloorPos = null;
      _hasMovedSignificantly = false;
    });
  }

  ZonePoint _defaultFloorPosition({required int index, required int count}) {
    final verticalStep = _mapOriginalHeight / (count + 1);
    return ZonePoint(
      x: _mapOriginalWidth * 0.82,
      y: verticalStep * (index + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zonesData = ref.watch(zonesProvider).zonesData;
    final authState = ref.watch(authProvider);
    final isAdmin = authState.isAdmin;
    final activeZones = zonesData.homePageBlockButtons
        .where((zone) => zone.active)
        .toList();
    final fallbackZone = activeZones.isNotEmpty
        ? activeZones.first.buttonName
        : null;
    final selectedZone =
        activeZones.any((zone) => zone.buttonName == widget.initialZone)
        ? widget.initialZone
        : fallbackZone;
    final floorMap = selectedZone == null
        ? const <String, List<String>>{}
        : (zonesData.categoryNamesBlockFloorMap[selectedZone] ?? const {});
    final floors = floorMap.keys.toList();

    return Scaffold(
      appBar: AppBar(title: Text(selectedZone ?? 'Zone Preview')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Select Floor',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                if (isAdmin)
                  FilterChip(
                    label: const Text('Edit Floors'),
                    selected: _floorEditMode,
                    onSelected: _setFloorEditMode,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/zone_preview.png',
                          fit: BoxFit.cover,
                        ),
                        if (selectedZone != null && floors.isNotEmpty)
                          ...() {
                            final alignedFloorX =
                                floors
                                    .map(
                                      (floor) =>
                                          zonesData
                                              .floorButtonPositions[selectedZone]?[floor]
                                              ?.x,
                                    )
                                    .whereType<double>()
                                    .fold<double?>(null, (value, element) {
                                      return value ?? element;
                                    }) ??
                                _defaultFloorPosition(
                                  index: 0,
                                  count: floors.length,
                                ).x;
                            return floors.asMap().entries.map((entry) {
                            final index = entry.key;
                            final floor = entry.value;
                            final rawFloorPosition =
                                zonesData.floorButtonPositions[selectedZone]?[floor] ??
                                _defaultFloorPosition(
                                  index: index,
                                  count: floors.length,
                                );
                            final floorPosition = ZonePoint(
                              x: alignedFloorX,
                              y: rawFloorPosition.y,
                            );
                            final left =
                                (floorPosition.x / _mapOriginalWidth) *
                                constraints.maxWidth;
                            final top =
                                (floorPosition.y / _mapOriginalHeight) *
                                constraints.maxHeight;
                            final isDragging = _draggingFloorIndex == index;

                            return Positioned(
                              left: left,
                              top: top,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: GestureDetector(
                                  onTap: () {
                                    if (_floorEditMode) {
                                      return;
                                    }
                                    context.push(
                                      '/floor-plan?zone=${Uri.encodeComponent(selectedZone)}&floor=${Uri.encodeComponent(floor)}',
                                    );
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 108,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              isDragging
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.black.withOpacity(
                                                    0.68,
                                                  ),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isDragging
                                                ? Colors.white
                                                : Colors.white.withOpacity(0.24),
                                            width: isDragging ? 2.2 : 1.4,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                isDragging ? 0.42 : 0.34,
                                              ),
                                              blurRadius: isDragging ? 18 : 14,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          floor,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                            height: 1,
                                            shadows: [
                                              Shadow(
                                                color: Color(0x99000000),
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isAdmin && _floorEditMode)
                                        Positioned.fill(
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.move,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onPanStart: (d) => _startFloorDrag(
                                                index,
                                                Offset(
                                                  floorPosition.x,
                                                  floorPosition.y,
                                                ),
                                                d.globalPosition,
                                              ),
                                              onPanUpdate: (d) =>
                                                  _updateFloorDrag(
                                                    constraints: constraints,
                                                    zoneId: selectedZone,
                                                    floor: floor,
                                                    index: index,
                                                    globalPosition:
                                                        d.globalPosition,
                                                  ),
                                              onPanEnd: (_) => _endFloorDrag(
                                                zoneId: selectedZone,
                                                floor: floor,
                                                index: index,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            });
                          }(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
