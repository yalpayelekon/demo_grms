import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/room_models.dart';
import '../models/zones_models.dart';
import '../models/service_policy.dart';
import '../widgets/room_card.dart';
import '../providers/zones_provider.dart';
import '../providers/hotel_status_provider.dart';
import '../providers/room_service_provider.dart';
import '../providers/demo_room_snapshot_provider.dart';
import '../providers/room_alias_provider.dart';
import '../providers/room_runtime_provider.dart';
import '../models/service_models.dart';
import '../models/api_result.dart';
import 'hotel_status/widgets/combined_room_control_dialog.dart';
import 'hotel_status/widgets/lighting_dialog.dart';
import '../utils/timestamped_debug_log.dart';

class HotelStatusPage extends ConsumerStatefulWidget {
  final String? initialZone;
  final String? initialFloor;

  const HotelStatusPage({super.key, this.initialZone, this.initialFloor});

  @override
  ConsumerState<HotelStatusPage> createState() => _HotelStatusPageState();
}

class _HotelStatusPageState extends ConsumerState<HotelStatusPage> {
  static const Set<String> _hotelStatusZones = {'Block A', 'Block B'};
  bool _showLighting = true;
  bool _showHVAC = true;
  bool _showRoomService = true;

  String? _selectedZoneId;
  String? _selectedFloorId;
  String _roomQuery = '';

  final Set<RoomStatus> _activeFilters = {
    RoomStatus.rentedOccupied,
    RoomStatus.rentedHK,
    RoomStatus.rentedVacant,
    RoomStatus.unrentedHK,
    RoomStatus.unrentedVacant,
    RoomStatus.malfunction,
  };

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zonesState = ref.watch(zonesProvider);
    final zonesData = zonesState.zonesData;

    final zones = zonesData.homePageBlockButtons
        .where((z) => z.active && _hotelStatusZones.contains(z.buttonName))
        .toList();
    final availableZoneIds = zones.map((z) => z.buttonName).toSet();
    if (_selectedZoneId == null ||
        !availableZoneIds.contains(_selectedZoneId)) {
      _selectedZoneId =
          widget.initialZone != null &&
              availableZoneIds.contains(widget.initialZone)
          ? widget.initialZone
          : (zones.isNotEmpty ? zones[0].buttonName : null);
    }

    final floorMap =
        zonesData.categoryNamesBlockFloorMap[_selectedZoneId] ?? {};
    final floors = floorMap.keys.toList();
    if (_selectedFloorId == null || !floors.contains(_selectedFloorId)) {
      _selectedFloorId =
          widget.initialFloor != null && floors.contains(widget.initialFloor)
          ? widget.initialFloor
          : (floors.isNotEmpty ? floors[0] : null);
    }

    final roomNumbers = floorMap[_selectedFloorId] ?? [];
    final mirroredRoomNumber = roomNumbers.isNotEmpty
        ? roomNumbers.first
        : null;
    _syncMirroredDemoRoom(mirroredRoomNumber);
    final activeMirroredRoomNumber = ref.watch(mirroredDemoRoomNumberProvider);
    final mirrorReady =
        mirroredRoomNumber != null &&
        activeMirroredRoomNumber == mirroredRoomNumber;

    if (kDebugMode) {
      debugLog(
        'HotelStatusPage: zone=$_selectedZoneId floor=$_selectedFloorId floors=${floors.length} rooms=${roomNumbers.length} mirroredTarget=$mirroredRoomNumber activeMirror=$activeMirroredRoomNumber mirrorReady=$mirrorReady',
      );
    }

    final hotelStatusState = ref.watch(hotelStatusProvider);
    final mirroredSnapshotState = !mirrorReady
        ? null
        : ref.watch(roomSnapshotProvider(mirroredRoomNumber));
    final hotelSyncStatus = DemoRoomHotelSyncStatus(
      source: mirroredSnapshotState?.source ?? 'live',
      targetUnreachable: mirroredSnapshotState?.targetUnreachable ?? false,
      message: mirroredSnapshotState?.message,
      reconnectAttempt: mirroredSnapshotState?.reconnectAttempt ?? 0,
    );
    final mirroredRuntimeRoom = !mirrorReady
        ? null
        : ref.watch(roomRuntimeRoomViewProvider(mirroredRoomNumber));
    final roomServices = ref.watch(roomServiceProvider);
    final serviceOverlayMap = _buildServiceOverlayMap(
      roomServices,
      mirroredRoomNumber: mirroredRoomNumber,
    );

    // Initialize rooms if not already there
    if (roomNumbers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(hotelStatusProvider.notifier).initializeRooms(roomNumbers);
      });
    }

    // Filter rooms
    final visibleRooms = roomNumbers
        .map((roomNumber) {
          final base =
              roomNumber == mirroredRoomNumber && mirroredRuntimeRoom != null
              ? mirroredRuntimeRoom
              : (hotelStatusState.rooms[roomNumber] ??
                    generateSimulatedRoomState(roomNumber));
          final overlay = serviceOverlayMap[roomNumber];
          return overlay == null ? base : _applyServiceOverlay(base, overlay);
        })
        .where((room) {
          final matchesStatus =
              _activeFilters.contains(room.status) ||
              (room.hasAlarm &&
                  _activeFilters.contains(RoomStatus.malfunction));
          final matchesQuery =
              _roomQuery.isEmpty || room.number.contains(_roomQuery);
          return matchesStatus && matchesQuery;
        })
        .toList();

    if (kDebugMode) {
      final overlayHits = visibleRooms
          .where((room) => serviceOverlayMap.containsKey(room.number))
          .length;
      final sample = visibleRooms
          .take(5)
          .map(
            (room) =>
                '${room.number}[dnd=${room.dnd.label},mur=${room.mur.label},laundry=${room.laundry.label}]',
          )
          .join(', ');
      debugLog(
        'HotelStatusPage: visibleRooms=${visibleRooms.length}, serviceOverlayHits=$overlayHits',
      );
      if (sample.isNotEmpty) {
        debugLog('HotelStatusPage: serviceIconSample=$sample');
      }
    }

    return Scaffold(
      body: Column(
        children: [
          _buildControls(
            zones,
            floors,
            visibleRooms,
            hotelSyncStatus,
            hasLiveDemoMirror: mirroredRoomNumber != null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisSpacing = 8.0;
                  const mainAxisSpacing = 10.0;
                  final width = constraints.maxWidth;
                  final crossAxisCount = width >= 1500
                      ? 13
                      : width >= 1320
                      ? 11
                      : width >= 1120
                      ? 9
                      : width >= 860
                      ? 7
                      : width >= 620
                      ? 5
                      : 3;

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: mainAxisSpacing,
                      crossAxisSpacing: crossAxisSpacing,
                      childAspectRatio: 1.08,
                    ),
                    itemCount: visibleRooms.length,
                    itemBuilder: (context, index) {
                      return RoomCard(
                        room: visibleRooms[index],
                        showLighting: _showLighting,
                        showHVAC: _showHVAC,
                        showRoomService: _showRoomService,
                        onCardTap: () =>
                            _showCombinedRoomControlDialog(visibleRooms[index]),
                        onLightingTap: () =>
                            _showLightingDialog(visibleRooms[index]),
                        onHVACTap: () => _showHVACDialog(visibleRooms[index]),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          _buildLegend(visibleRooms.length, roomNumbers.length),
        ],
      ),
    );
  }

  Widget _buildControls(
    List<ZoneButton> zones,
    List<String> floors,
    List<RoomData> visibleRooms,
    DemoRoomHotelSyncStatus syncStatus, {
    required bool hasLiveDemoMirror,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          if (hasLiveDemoMirror)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (syncStatus.targetUnreachable &&
                      (syncStatus.message?.isNotEmpty ?? false)) ...[
                    const SizedBox(width: 12),
                    Text(
                      syncStatus.message!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              _buildCheckbox(
                'Lighting',
                _showLighting,
                (v) => setState(() => _showLighting = v!),
              ),
              const SizedBox(width: 16),
              _buildCheckbox(
                'HVAC',
                _showHVAC,
                (v) => setState(() => _showHVAC = v!),
              ),
              const SizedBox(width: 16),
              _buildCheckbox(
                'Room Service',
                _showRoomService,
                (v) => setState(() => _showRoomService = v!),
              ),
              const Spacer(),
              _buildDropdown(
                value: _selectedZoneId,
                items: zones
                    .map(
                      (z) => DropdownMenuItem(
                        value: z.buttonName,
                        child: Text(z.uiDisplayName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedZoneId = v;
                  _selectedFloorId = null;
                  if (kDebugMode) {
                    debugLog(
                      'HotelStatusPage: zone changed to $_selectedZoneId',
                    );
                  }
                }),
              ),
              const SizedBox(width: 16),
              _buildDropdown(
                value: _selectedFloorId,
                items: floors
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedFloorId = v;
                  if (kDebugMode) {
                    debugLog(
                      'HotelStatusPage: floor changed to $_selectedFloorId',
                    );
                  }
                }),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: (_selectedZoneId == null || _selectedFloorId == null)
                    ? null
                    : () {
                        context.go(
                          Uri(
                            path: '/floor-plan',
                            queryParameters: {
                              'zone': _selectedZoneId,
                              'floor': _selectedFloorId,
                            },
                          ).toString(),
                        );
                      },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Floor Plan'),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 150,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search Room',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _roomQuery = v),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  final notifier = ref.read(hotelStatusProvider.notifier);
                  for (var room in visibleRooms) {
                    if (room.number ==
                        ref.read(mirroredDemoRoomNumberProvider)) {
                      ref
                          .read(roomSnapshotProvider(room.number).notifier)
                          .refreshNow();
                      continue;
                    }
                    notifier.fetchRoomSnapshot(room.number);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Text(label),
      ],
    );
  }

  Widget _buildDropdown<T>({
    T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLegend(int visibleCount, int totalCount) {
    final statusItems = [
      {
        'id': RoomStatus.rentedOccupied,
        'label': 'Rented Occupied',
        'asset': 'greenadamvaliz.png',
      },
      {
        'id': RoomStatus.rentedHK,
        'label': 'Rented HK',
        'asset': 'greenhousekeeping.png',
      },
      {
        'id': RoomStatus.rentedVacant,
        'label': 'Rented Vacant',
        'asset': 'greenvaliz.png',
      },
      {
        'id': RoomStatus.unrentedHK,
        'label': 'Unrented HK',
        'asset': 'whitehousekeeping.png',
      },
      {
        'id': RoomStatus.unrentedVacant,
        'label': 'Unrented Vacant',
        'asset': 'white.png',
      },
      {
        'id': RoomStatus.malfunction,
        'label': 'Malfunction',
        'asset': 'redadamvaliz.png',
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: statusItems.map((item) {
          final id = item['id'] as RoomStatus;
          final isActive = _activeFilters.contains(id);
          return GestureDetector(
            onTap: () => setState(() {
              if (isActive) {
                _activeFilters.remove(id);
              } else {
                _activeFilters.add(id);
              }
            }),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.4,
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/room_status/${item['asset']}',
                    width: 32,
                    height: 32,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['label'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$visibleCount/$totalCount',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showLightingDialog(RoomData room) {
    showDialog(
      context: context,
      builder: (context) => LightingDialog(room: room),
    );
  }

  void _showHVACDialog(RoomData room) {
    showDialog(
      context: context,
      builder: (context) => _HvacDialog(room: room),
    );
  }

  void _showCombinedRoomControlDialog(RoomData room) {
    showDialog(
      context: context,
      builder: (context) => CombinedRoomControlDialog(room: room),
    );
  }

  RoomData _applyServiceOverlay(RoomData base, _ServiceOverlayState overlay) {
    return base.copyWith(
      dnd: overlay.dnd ?? base.dnd,
      mur: overlay.mur ?? base.mur,
      laundry: overlay.laundry ?? base.laundry,
      murDelayedMinutes: overlay.murDelayedMinutes ?? base.murDelayedMinutes,
    );
  }

  Map<String, _ServiceOverlayState> _buildServiceOverlayMap(
    List<RoomServiceEntry> services, {
    String? mirroredRoomNumber,
  }) {
    final map = <String, _ServiceOverlayState>{};

    for (final service in services) {
      final key =
          service.roomNumber == demoBackendRoomNumber &&
              mirroredRoomNumber != null
          ? mirroredRoomNumber
          : service.roomNumber;
      final current = map[key];
      final next = _applyServiceToOverlay(current, service);
      map[key] = next;
    }

    map.updateAll((_, value) => _normalizeServiceOverlay(value));
    return map;
  }

  void _syncMirroredDemoRoom(String? mirroredRoomNumber) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final notifier = ref.read(mirroredDemoRoomNumberProvider.notifier);
      if (notifier.state != mirroredRoomNumber) {
        if (kDebugMode) {
          debugLog(
            'HotelStatusPage: syncing mirrored demo room ${notifier.state} -> $mirroredRoomNumber',
          );
        }
        notifier.state = mirroredRoomNumber;
      }
    });
  }

  _ServiceOverlayState _normalizeServiceOverlay(_ServiceOverlayState state) {
    final normalized = normalizeOverlay(
      ServiceOverlay(
        dnd: state.dnd ?? DndStatus.off,
        mur: state.mur ?? MurStatus.finished,
        laundry: state.laundry ?? LaundryStatus.finished,
        murDelayedMinutes: state.murDelayedMinutes,
      ),
    );
    return state.copyWith(
      dnd: normalized.dnd,
      mur: normalized.mur,
      laundry: normalized.laundry,
      murDelayedMinutes: normalized.murDelayedMinutes,
    );
  }

  _ServiceOverlayState _applyServiceToOverlay(
    _ServiceOverlayState? current,
    RoomServiceEntry service,
  ) {
    final next = current ?? const _ServiceOverlayState();

    switch (service.serviceType) {
      case ServiceType.dnd:
        if (next.dndTimestamp != null &&
            service.eventTimestamp <= next.dndTimestamp!) {
          return next;
        }
        final dnd = service.serviceState.toLowerCase() == 'on'
            ? DndStatus.on
            : DndStatus.off;
        return next.copyWith(dnd: dnd, dndTimestamp: service.eventTimestamp);
      case ServiceType.mur:
        if (next.murTimestamp != null &&
            service.eventTimestamp <= next.murTimestamp!) {
          return next;
        }
        final mur = switch (service.serviceState.toLowerCase()) {
          'requested' => MurStatus.requested,
          'delayed' => MurStatus.delayed,
          'started' => MurStatus.started,
          'canceled' => MurStatus.canceled,
          _ => MurStatus.finished,
        };
        return next.copyWith(
          mur: mur,
          murTimestamp: service.eventTimestamp,
          murDelayedMinutes: service.delayedMinutes > 0
              ? service.delayedMinutes
              : null,
        );
      case ServiceType.laundry:
        if (next.laundryTimestamp != null &&
            service.eventTimestamp <= next.laundryTimestamp!) {
          return next;
        }
        final laundry = switch (service.serviceState.toLowerCase()) {
          'requested' || 'started' => LaundryStatus.requested,
          'delayed' => LaundryStatus.delayed,
          'canceled' => LaundryStatus.canceled,
          _ => LaundryStatus.finished,
        };
        return next.copyWith(
          laundry: laundry,
          laundryTimestamp: service.eventTimestamp,
        );
    }
  }
}

class _ServiceOverlayState {
  const _ServiceOverlayState({
    this.dnd,
    this.mur,
    this.laundry,
    this.murDelayedMinutes,
    this.dndTimestamp,
    this.murTimestamp,
    this.laundryTimestamp,
  });

  final DndStatus? dnd;
  final MurStatus? mur;
  final LaundryStatus? laundry;
  final int? murDelayedMinutes;
  final int? dndTimestamp;
  final int? murTimestamp;
  final int? laundryTimestamp;

  _ServiceOverlayState copyWith({
    DndStatus? dnd,
    MurStatus? mur,
    LaundryStatus? laundry,
    int? murDelayedMinutes,
    int? dndTimestamp,
    int? murTimestamp,
    int? laundryTimestamp,
  }) {
    return _ServiceOverlayState(
      dnd: dnd ?? this.dnd,
      mur: mur ?? this.mur,
      laundry: laundry ?? this.laundry,
      murDelayedMinutes: murDelayedMinutes ?? this.murDelayedMinutes,
      dndTimestamp: dndTimestamp ?? this.dndTimestamp,
      murTimestamp: murTimestamp ?? this.murTimestamp,
      laundryTimestamp: laundryTimestamp ?? this.laundryTimestamp,
    );
  }
}

class _HvacDialog extends ConsumerStatefulWidget {
  final RoomData room;
  const _HvacDialog({required this.room});

  @override
  ConsumerState<_HvacDialog> createState() => _HvacDialogState();
}

class _HvacDialogState extends ConsumerState<_HvacDialog> {
  late double _setPoint;
  late bool _isOn;
  late int _mode;
  late int _fanMode;

  late double _initialSetPoint;
  late bool _initialIsOn;
  late int _initialMode;
  late int _initialFanMode;

  bool _saving = false;
  bool _loadingLatest = false;
  RoomData? _latestRoom;
  ProviderSubscription<RoomData?>? _roomRuntimeSubscription;

  @override
  void initState() {
    super.initState();
    _hydrateFromRoom(widget.room);
    _roomRuntimeSubscription = ref.listenManual<RoomData?>(
      roomRuntimeRoomViewProvider(widget.room.number),
      _onRoomRuntimeChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(roomSnapshotProvider(widget.room.number)).snapshot == null) {
        ref
            .read(roomSnapshotProvider(widget.room.number).notifier)
            .refreshNow();
      }
    });
  }

  @override
  void dispose() {
    _roomRuntimeSubscription?.close();
    super.dispose();
  }

  void _onRoomRuntimeChanged(RoomData? previous, RoomData? next) {
    if (next == null || !mounted) {
      return;
    }
    final changed = previous != next;
    if (!changed) {
      return;
    }

    setState(() {
      _latestRoom = next;
      if (!_hasChanges) {
        _hydrateFromRoom(next);
      }
    });
  }

  void _hydrateFromRoom(RoomData room) {
    _latestRoom = room;
    final detail = room.hvacDetail;
    _setPoint = detail?.setPoint ?? 22.0;
    _isOn = (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    _mode = _normalizeMode(detail?.mode);
    _fanMode = _normalizeFanMode(detail?.fanMode);

    _initialSetPoint = _setPoint;
    _initialIsOn = _isOn;
    _initialMode = _mode;
    _initialFanMode = _fanMode;
  }

  int _normalizeMode(int? raw) {
    final value = raw ?? 0;
    if (value >= 0 && value <= 3) {
      return value;
    }
    if (kDebugMode) {
      debugPrint('HVAC dialog: normalized mode raw=$value -> 0 (Heat)');
    }
    return 0;
  }

  int _normalizeFanMode(int? raw) {
    final value = raw ?? 4;
    if (value >= 1 && value <= 4) {
      return value;
    }
    if (kDebugMode) {
      debugPrint('HVAC dialog: normalized fanMode raw=$value -> 4 (Auto)');
    }
    return 4;
  }

  Future<void> _refreshFromBackend() async {
    setState(() => _loadingLatest = true);
    await ref
        .read(roomSnapshotProvider(widget.room.number).notifier)
        .refreshNow();
    if (!mounted) {
      return;
    }

    final refreshed = ref.read(roomRuntimeRoomViewProvider(widget.room.number));
    if (refreshed != null) {
      setState(() {
        _hydrateFromRoom(refreshed);
      });
    }
    setState(() => _loadingLatest = false);
  }

  bool get _hasChanges {
    final setPointChanged = (_setPoint - _initialSetPoint).abs() >= 0.1;
    return _isOn != _initialIsOn ||
        setPointChanged ||
        _mode != _initialMode ||
        _fanMode != _initialFanMode;
  }

  String get _modeLabel {
    switch (_mode) {
      case 0:
        return 'Heat';
      case 1:
        return 'Cool';
      case 2:
        return 'Fan Only';
      case 3:
        return 'Auto';
      default:
        return 'Heat';
    }
  }

  String get _fanLabel {
    switch (_fanMode) {
      case 1:
        return 'Low';
      case 2:
        return 'Medium';
      case 3:
        return 'High';
      default:
        return 'Auto';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final notifier = ref.read(hotelStatusProvider.notifier);
    final result = await notifier.updateHvac(widget.room.number, {
      'onOff': _isOn ? 1 : 0,
      'setPoint': _setPoint.toStringAsFixed(1),
      'mode': _mode,
      'fanMode': _fanMode,
    });

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update HVAC: ${result.error.message}'),
        ),
      );
      return;
    }
    setState(() {
      _initialSetPoint = _setPoint;
      _initialIsOn = _isOn;
      _initialMode = _mode;
      _initialFanMode = _fanMode;
    });
    unawaited(_refreshFromBackend());
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBackendRoomNumber = ref.watch(
      effectiveBackendRoomNumberProvider(widget.room.number),
    );
    final syncState = ref.watch(roomSnapshotProvider(widget.room.number));
    final syncStatus = DemoRoomHotelSyncStatus(
      source: syncState.source,
      targetUnreachable: syncState.targetUnreachable,
      message: syncState.message,
      reconnectAttempt: syncState.reconnectAttempt,
    );
    final runtimeRoom = ref.watch(
      roomRuntimeRoomViewProvider(widget.room.number),
    );
    final room = runtimeRoom ?? _latestRoom ?? widget.room;
    final detail = room.hvacDetail;
    final runningFromBackend =
        (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    final safeMode = _normalizeMode(_mode);
    final safeFanMode = _normalizeFanMode(_fanMode);
    if (safeMode != _mode) {
      _mode = safeMode;
    }
    if (safeFanMode != _fanMode) {
      _fanMode = safeFanMode;
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 980,
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
        decoration: BoxDecoration(
          color: const Color(0xFF1F222B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'HVAC Control - Room ${widget.room.number}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_loadingLatest)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (effectiveBackendRoomNumber == demoBackendRoomNumber) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (syncStatus.targetUnreachable &&
                        (syncStatus.message?.isNotEmpty ?? false)) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          syncStatus.message!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orangeAccent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withOpacity(0.25),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/johnsonControl.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatChip(
                                  'Room Temp',
                                  detail?.roomTemperature != null
                                      ? '${detail!.roomTemperature!.toStringAsFixed(1)} C'
                                      : '-',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatChip(
                                  'Running',
                                  runningFromBackend ? 'On' : 'Off',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatChip('Mode', _modeLabel),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: _buildStatChip('Fan', _fanLabel)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Power',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Switch(
                                value: _isOn,
                                onChanged: (value) =>
                                    setState(() => _isOn = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Set Point: ${_setPoint.toStringAsFixed(1)} C',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Slider(
                            value: _setPoint.clamp(16.0, 30.0),
                            min: 16,
                            max: 30,
                            divisions: 28,
                            label: _setPoint.toStringAsFixed(1),
                            onChanged: (value) =>
                                setState(() => _setPoint = value),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            value: safeMode,
                            decoration: const InputDecoration(
                              labelText: 'Mode',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Heat')),
                              DropdownMenuItem(value: 1, child: Text('Cool')),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('Fan Only'),
                              ),
                              DropdownMenuItem(value: 3, child: Text('Auto')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _mode = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: safeFanMode,
                            decoration: const InputDecoration(
                              labelText: 'Fan',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('Low')),
                              DropdownMenuItem(value: 2, child: Text('Medium')),
                              DropdownMenuItem(value: 3, child: Text('High')),
                              DropdownMenuItem(value: 4, child: Text('Auto')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _fanMode = value);
                              }
                            },
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _saving || !_hasChanges
                                    ? null
                                    : _save,
                                child: Text(_saving ? 'Saving...' : 'Save'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
