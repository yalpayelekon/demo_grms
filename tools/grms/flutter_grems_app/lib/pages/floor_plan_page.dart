import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/hotel_status/widgets/lighting_dialog.dart';
import '../providers/auth_provider.dart';
import '../providers/hotel_status_provider.dart';
import '../providers/room_runtime_provider.dart';
import '../providers/zones_provider.dart';

class FloorPlanPage extends ConsumerStatefulWidget {
  const FloorPlanPage({super.key, this.initialZone, this.initialFloor});

  final String? initialZone;
  final String? initialFloor;

  @override
  ConsumerState<FloorPlanPage> createState() => _FloorPlanPageState();
}

class _FloorPlanPageState extends ConsumerState<FloorPlanPage> {
  String? _selectedZone;
  String? _selectedFloor;

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    final zonesData = ref.watch(zonesProvider).zonesData;
    final activeZones = zonesData.homePageBlockButtons
        .where((zone) => zone.active)
        .toList();
    final availableZoneIds = activeZones.map((zone) => zone.buttonName).toSet();

    _selectedZone ??=
        (widget.initialZone != null &&
            availableZoneIds.contains(widget.initialZone))
        ? widget.initialZone
        : (activeZones.isNotEmpty ? activeZones.first.buttonName : null);

    final floorMap = _selectedZone == null
        ? const <String, List<String>>{}
        : (zonesData.categoryNamesBlockFloorMap[_selectedZone] ?? const {});
    final floors = floorMap.keys.toList();
    if (_selectedFloor == null || !floors.contains(_selectedFloor)) {
      _selectedFloor =
          (widget.initialFloor != null && floors.contains(widget.initialFloor))
          ? widget.initialFloor
          : (floors.isNotEmpty ? floors.first : null);
    }

    final rooms = floorMap[_selectedFloor] ?? const <String>[];
    if (rooms.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(hotelStatusProvider.notifier).initializeRooms(rooms);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_selectedZone ?? 'Zone'} - ${_selectedFloor ?? 'Floor'}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: (_selectedZone == null || _selectedFloor == null)
                  ? null
                  : () {
                      context.go(
                        Uri(
                          path: '/hotel-status',
                          queryParameters: {
                            'zone': _selectedZone,
                            'floor': _selectedFloor,
                          },
                        ).toString(),
                      );
                    },
              icon: const Icon(Icons.hotel),
              label: const Text('Hotel Status'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Room',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Semantics(
                  button: true,
                  label: 'Open room controls',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openRoomDialog(_demoRoomNumber(rooms)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: const Color(0xFF10151F),
                          child: Image.asset(
                            'assets/images/floor_with_rooms.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 20,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.58),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRoomDialog(String roomNumber) {
    final runtimeRoom = ref.read(roomRuntimeRoomViewProvider(roomNumber));
    final fallback = generateSimulatedRoomState(roomNumber);
    final room = runtimeRoom ?? fallback;

    showDialog<void>(
      context: context,
      builder: (context) => LightingDialog(room: room),
    );
  }

  String _demoRoomNumber(List<String> rooms) {
    if (rooms.isNotEmpty) {
      return rooms.first;
    }
    return '1001';
  }
}
