import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lighting_device.dart';
import '../models/room_models.dart';
import '../models/room_runtime_snapshot.dart';
import '../utils/lighting_dim_level_curves.dart';
import 'alarms_provider.dart';
import 'demo_room_snapshot_provider.dart';
import 'lighting_devices_provider.dart';

enum PendingLightingStatus { idle, inflight, acked, failed }

class PendingLightingWrite {
  const PendingLightingWrite({
    required this.requestId,
    required this.targetLevel,
    required this.startedAt,
    required this.status,
    this.ackAt,
  });

  final String requestId;
  final int targetLevel;
  final DateTime startedAt;
  final DateTime? ackAt;
  final PendingLightingStatus status;

  PendingLightingWrite copyWith({
    String? requestId,
    int? targetLevel,
    DateTime? startedAt,
    DateTime? ackAt,
    PendingLightingStatus? status,
  }) {
    return PendingLightingWrite(
      requestId: requestId ?? this.requestId,
      targetLevel: targetLevel ?? this.targetLevel,
      startedAt: startedAt ?? this.startedAt,
      ackAt: ackAt ?? this.ackAt,
      status: status ?? this.status,
    );
  }
}

class RoomLightingRuntimeState {
  const RoomLightingRuntimeState({
    this.lighting,
    this.selectedScene,
    this.pendingScene,
    this.pendingSceneRequestId,
    this.pendingSceneStartedAt,
    this.pendingSceneAckAt,
    this.pendingSceneStatus = PendingLightingStatus.idle,
    this.pendingDeviceWrites = const {},
  });

  final LightingDevicesResponse? lighting;
  final int? selectedScene;
  final int? pendingScene;
  final String? pendingSceneRequestId;
  final DateTime? pendingSceneStartedAt;
  final DateTime? pendingSceneAckAt;
  final PendingLightingStatus pendingSceneStatus;
  final Map<String, PendingLightingWrite> pendingDeviceWrites;

  RoomLightingRuntimeState copyWith({
    LightingDevicesResponse? lighting,
    bool clearLighting = false,
    int? selectedScene,
    bool clearSelectedScene = false,
    int? pendingScene,
    bool clearPendingScene = false,
    String? pendingSceneRequestId,
    bool clearPendingSceneRequestId = false,
    DateTime? pendingSceneStartedAt,
    bool clearPendingSceneStartedAt = false,
    DateTime? pendingSceneAckAt,
    bool clearPendingSceneAckAt = false,
    PendingLightingStatus? pendingSceneStatus,
    Map<String, PendingLightingWrite>? pendingDeviceWrites,
  }) {
    return RoomLightingRuntimeState(
      lighting: clearLighting ? null : (lighting ?? this.lighting),
      selectedScene: clearSelectedScene
          ? null
          : (selectedScene ?? this.selectedScene),
      pendingScene: clearPendingScene
          ? null
          : (pendingScene ?? this.pendingScene),
      pendingSceneRequestId: clearPendingSceneRequestId
          ? null
          : (pendingSceneRequestId ?? this.pendingSceneRequestId),
      pendingSceneStartedAt: clearPendingSceneStartedAt
          ? null
          : (pendingSceneStartedAt ?? this.pendingSceneStartedAt),
      pendingSceneAckAt: clearPendingSceneAckAt
          ? null
          : (pendingSceneAckAt ?? this.pendingSceneAckAt),
      pendingSceneStatus: pendingSceneStatus ?? this.pendingSceneStatus,
      pendingDeviceWrites: pendingDeviceWrites ?? this.pendingDeviceWrites,
    );
  }
}

class RoomLightingRuntimeNotifier
    extends FamilyNotifier<RoomLightingRuntimeState, String> {
  static const Map<int, Map<int, int>> _sceneAddressLevels = {
    1: {8: 254, 9: 254, 10: 254, 12: 254, 15: 254, 16: 254, 17: 254, 18: 254},
    2: {8: 228, 9: 228, 10: 228, 12: 228, 15: 228, 16: 228, 17: 228, 18: 228},
    3: {8: 0, 9: 0, 10: 0, 12: 169, 15: 0, 16: 0, 17: 0, 18: 169},
    4: {8: 0, 9: 0, 10: 0, 12: 0, 15: 0, 16: 0, 17: 169, 18: 0},
    5: {8: 0, 9: 209, 10: 209, 12: 0, 15: 0, 16: 209, 17: 0, 18: 0},
  };
  static const Duration _ackWaitTimeout = Duration(seconds: 3);
  static const Duration _holdAfterAck = Duration(seconds: 6);

  late final String _roomNumber;
  Timer? _syncTimer;

  @override
  RoomLightingRuntimeState build(String roomNumber) {
    _roomNumber = roomNumber;
    ref.onDispose(() {
      _syncTimer?.cancel();
    });
    ref.listen<RoomRuntimeSnapshot?>(roomRuntimeSnapshotProvider(roomNumber), (
      previous,
      next,
    ) {
      _applySnapshot(next);
      _scheduleAlarmSync(next);
    });
    final snapshot = ref.read(roomRuntimeSnapshotProvider(roomNumber));
    _scheduleAlarmSync(snapshot);
    return RoomLightingRuntimeState(lighting: snapshot?.lighting);
  }

  void _syncAlarms(RoomRuntimeSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }
    final devices = <LightingDeviceSummary>[
      ...snapshot.lighting.onboardOutputs,
      ...snapshot.lighting.daliOutputs,
    ];
    ref
        .read(alarmsProvider.notifier)
        .syncRuntimeAlarmsForRoom(
          _roomNumber,
          devices,
          hasDaliLineShortCircuit: snapshot.hasDaliLineShortCircuit,
          hasDoorAlarm: snapshot.hasDoorAlarm,
          isDoorOpen: snapshot.roomData.occupancy?.doorOpen ?? false,
          serviceEvents: snapshot.serviceEvents,
          hvacDetail: snapshot.roomData.hvacDetail,
        );
  }

  void _scheduleAlarmSync(RoomRuntimeSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }
    Future<void>.microtask(() {
      _syncAlarms(snapshot);
    });
  }

  void startScene(int scene, String requestId, DateTime startedAt) {
    state = state.copyWith(
      selectedScene: scene,
      pendingScene: scene,
      pendingSceneRequestId: requestId,
      pendingSceneStartedAt: startedAt,
      clearPendingSceneAckAt: true,
      pendingSceneStatus: PendingLightingStatus.inflight,
    );
    _applyOptimisticScene(scene);
    _scheduleSync();
  }

  void ackScene(String requestId) {
    if (state.pendingSceneRequestId != requestId) {
      return;
    }
    state = state.copyWith(
      pendingSceneAckAt: DateTime.now(),
      pendingSceneStatus: PendingLightingStatus.acked,
    );
    _scheduleSync();
  }

  void failScene(String requestId) {
    if (state.pendingSceneRequestId != requestId) {
      return;
    }
    _releasePendingScene(clearSelectedScene: true);
    _resyncWithSnapshot();
  }

  void startMasterPowerToggle(
    bool enabled,
    String requestId,
    DateTime startedAt,
  ) {
    state = state.copyWith(
      selectedScene: 6,
      pendingScene: 6,
      pendingSceneRequestId: requestId,
      pendingSceneStartedAt: startedAt,
      clearPendingSceneAckAt: true,
      pendingSceneStatus: PendingLightingStatus.inflight,
    );
    _applyOptimisticMasterPower(enabled);
    _scheduleSync();
  }

  void ackMasterPowerToggle(String requestId) {
    ackScene(requestId);
  }

  void failMasterPowerToggle(String requestId) {
    failScene(requestId);
  }

  void startDeviceWrite(
    LightingDeviceSummary displayedDevice,
    int targetLevel,
    String requestId,
  ) {
    final key = _deviceKey(displayedDevice.address, displayedDevice.type);
    final nextWrites = Map<String, PendingLightingWrite>.from(
      state.pendingDeviceWrites,
    );
    nextWrites[key] = PendingLightingWrite(
      requestId: requestId,
      targetLevel: targetLevel,
      startedAt: DateTime.now(),
      status: PendingLightingStatus.inflight,
    );
    state = state.copyWith(pendingDeviceWrites: nextWrites);
    _applyOptimisticDeviceLevel(displayedDevice, targetLevel.toDouble());
    _scheduleSync();
  }

  void ackDeviceWrite(LightingDeviceSummary displayedDevice, String requestId) {
    final key = _deviceKey(displayedDevice.address, displayedDevice.type);
    final pending = state.pendingDeviceWrites[key];
    if (pending == null || pending.requestId != requestId) {
      return;
    }
    final nextWrites = Map<String, PendingLightingWrite>.from(
      state.pendingDeviceWrites,
    );
    nextWrites[key] = pending.copyWith(
      ackAt: DateTime.now(),
      status: PendingLightingStatus.acked,
    );
    state = state.copyWith(pendingDeviceWrites: nextWrites);
    _scheduleSync();
  }

  void failDeviceWrite(
    LightingDeviceSummary displayedDevice,
    String requestId,
  ) {
    final key = _deviceKey(displayedDevice.address, displayedDevice.type);
    final pending = state.pendingDeviceWrites[key];
    if (pending == null || pending.requestId != requestId) {
      return;
    }
    _releasePendingDeviceWrite(key);
    _resyncWithSnapshot();
  }

  void selectScene(int? scene) {
    state = state.copyWith(
      selectedScene: scene,
      clearSelectedScene: scene == null,
    );
  }

  void _applySnapshot(RoomRuntimeSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }
    final retryAfter = _retryAfter();
    if (retryAfter != null) {
      _scheduleSync(retryAfter);
      return;
    }
    state = state.copyWith(lighting: snapshot.lighting);
  }

  void _applyOptimisticScene(int scene) {
    final current = state.lighting;
    final sceneLevels = _sceneAddressLevels[scene];
    if (current == null || sceneLevels == null || sceneLevels.isEmpty) {
      return;
    }
    LightingDeviceSummary apply(LightingDeviceSummary device) {
      final rawLevel = sceneLevels[device.address];
      if (rawLevel == null) {
        return device;
      }
      final percent = _rawLevelToUiPercent(rawLevel, device.type).toDouble();
      return LightingDeviceSummary(
        address: device.address,
        name: device.name,
        actualLevel: percent,
        targetLevel: percent,
        powerW: device.powerW,
        feature: device.feature,
        alarm: device.alarm,
        daliSituation: device.daliSituation,
        type: device.type,
        x: device.x,
        y: device.y,
      );
    }

    state = state.copyWith(
      lighting: LightingDevicesResponse(
        onboardOutputs: current.onboardOutputs.map(apply).toList(),
        daliOutputs: current.daliOutputs.map(apply).toList(),
      ),
    );
  }

  void _applyOptimisticDeviceLevel(
    LightingDeviceSummary displayedDevice,
    double level,
  ) {
    final current = state.lighting;
    if (current == null) {
      return;
    }

    final exactKey = _deviceKey(displayedDevice.address, displayedDevice.type);
    var fallbackApplied = false;

    LightingDeviceSummary apply(LightingDeviceSummary item) {
      final itemKey = _deviceKey(item.address, item.type);
      if (itemKey == exactKey) {
        fallbackApplied = true;
        return _copyLevel(item, level);
      }
      if (!fallbackApplied && item.address == displayedDevice.address) {
        fallbackApplied = true;
        return _copyLevel(item, level);
      }
      return item;
    }

    state = state.copyWith(
      lighting: LightingDevicesResponse(
        onboardOutputs: current.onboardOutputs.map(apply).toList(),
        daliOutputs: current.daliOutputs.map(apply).toList(),
      ),
    );
  }

  void _applyOptimisticMasterPower(bool enabled) {
    final current = state.lighting;
    if (current == null) {
      return;
    }
    final level = enabled ? 100.0 : 0.0;

    LightingDeviceSummary apply(LightingDeviceSummary device) {
      return _copyLevel(device, level);
    }

    state = state.copyWith(
      lighting: LightingDevicesResponse(
        onboardOutputs: current.onboardOutputs.map(apply).toList(),
        daliOutputs: current.daliOutputs.map(apply).toList(),
      ),
    );
  }

  LightingDeviceSummary _copyLevel(LightingDeviceSummary device, double level) {
    return LightingDeviceSummary(
      address: device.address,
      name: device.name,
      actualLevel: level,
      targetLevel: level,
      powerW: device.powerW,
      feature: device.feature,
      alarm: device.alarm,
      daliSituation: device.daliSituation,
      type: device.type,
      x: device.x,
      y: device.y,
    );
  }

  Duration? _retryAfter() {
    final now = DateTime.now();
    Duration? retryAfter;

    final sceneRetry = _pendingSceneRetryAfter(now);
    if (sceneRetry != null) {
      retryAfter = sceneRetry;
    }

    final keysToRelease = <String>[];
    for (final entry in state.pendingDeviceWrites.entries) {
      final delay = _pendingWriteRetryAfter(entry.value, now);
      if (delay == null) {
        keysToRelease.add(entry.key);
        continue;
      }
      if (retryAfter == null || delay < retryAfter) {
        retryAfter = delay;
      }
    }
    if (keysToRelease.isNotEmpty) {
      final nextWrites = Map<String, PendingLightingWrite>.from(
        state.pendingDeviceWrites,
      );
      for (final key in keysToRelease) {
        nextWrites.remove(key);
      }
      state = state.copyWith(pendingDeviceWrites: nextWrites);
    }

    return retryAfter;
  }

  Duration? _pendingSceneRetryAfter(DateTime now) {
    if (state.pendingScene == null ||
        state.pendingSceneRequestId == null ||
        state.pendingSceneStatus == PendingLightingStatus.idle) {
      return null;
    }

    if (state.pendingSceneStatus == PendingLightingStatus.inflight) {
      final startedAt = state.pendingSceneStartedAt;
      if (startedAt == null) {
        _releasePendingScene();
        return null;
      }
      final deadline = startedAt.add(_ackWaitTimeout);
      if (!now.isBefore(deadline)) {
        _releasePendingScene();
        return null;
      }
      return deadline.difference(now);
    }

    if (state.pendingSceneStatus == PendingLightingStatus.acked) {
      final ackAt = state.pendingSceneAckAt;
      if (ackAt == null) {
        _releasePendingScene();
        return null;
      }
      final deadline = ackAt.add(_holdAfterAck);
      if (!now.isBefore(deadline)) {
        _releasePendingScene();
        return null;
      }
      return deadline.difference(now);
    }

    _releasePendingScene();
    return null;
  }

  Duration? _pendingWriteRetryAfter(
    PendingLightingWrite pending,
    DateTime now,
  ) {
    if (pending.status == PendingLightingStatus.inflight) {
      final deadline = pending.startedAt.add(_ackWaitTimeout);
      if (!now.isBefore(deadline)) {
        return null;
      }
      return deadline.difference(now);
    }

    if (pending.status == PendingLightingStatus.acked) {
      final ackAt = pending.ackAt;
      if (ackAt == null) {
        return null;
      }
      final deadline = ackAt.add(_holdAfterAck);
      if (!now.isBefore(deadline)) {
        return null;
      }
      return deadline.difference(now);
    }

    return null;
  }

  void _scheduleSync([Duration? retryAfter]) {
    final delay =
        retryAfter ?? _retryAfter() ?? const Duration(milliseconds: 50);
    _syncTimer?.cancel();
    final timerDelay = delay <= Duration.zero
        ? const Duration(milliseconds: 50)
        : delay + const Duration(milliseconds: 50);
    _syncTimer = Timer(timerDelay, _resyncWithSnapshot);
  }

  void _resyncWithSnapshot() {
    _applySnapshot(ref.read(roomRuntimeSnapshotProvider(_roomNumber)));
  }

  void _releasePendingScene({bool clearSelectedScene = false}) {
    state = state.copyWith(
      clearPendingScene: true,
      clearPendingSceneRequestId: true,
      clearPendingSceneStartedAt: true,
      clearPendingSceneAckAt: true,
      clearSelectedScene: clearSelectedScene,
      pendingSceneStatus: PendingLightingStatus.idle,
    );
  }

  void _releasePendingDeviceWrite(String key) {
    final nextWrites = Map<String, PendingLightingWrite>.from(
      state.pendingDeviceWrites,
    );
    nextWrites.remove(key);
    state = state.copyWith(pendingDeviceWrites: nextWrites);
  }

  String _deviceKey(int address, LightingDeviceType type) {
    return '${type.name}-$address';
  }

  int _rawLevelToUiPercent(int rawLevel, LightingDeviceType type) {
    final curve = type == LightingDeviceType.onboard
        ? rcuDimmLevelCurve
        : daliDimmLevelCurve;
    if (rawLevel <= 0) {
      return 0;
    }
    if (rawLevel >= 255) {
      return 100;
    }
    for (var pct = 100; pct >= 1; pct--) {
      if (rawLevel >= curve[pct]) {
        return pct;
      }
    }
    return 0;
  }
}

final roomLightingRuntimeProvider =
    NotifierProviderFamily<
      RoomLightingRuntimeNotifier,
      RoomLightingRuntimeState,
      String
    >(RoomLightingRuntimeNotifier.new);

final roomRuntimeRoomDataProvider =
    Provider.family<RoomRuntimeSnapshot?, String>(
      (ref, roomNumber) => ref.watch(roomRuntimeSnapshotProvider(roomNumber)),
    );

final roomRuntimeRoomViewProvider = Provider.family<RoomData?, String>((
  ref,
  roomNumber,
) {
  final snapshot = ref.watch(roomRuntimeSnapshotProvider(roomNumber));
  if (snapshot == null) {
    return null;
  }

  ref.watch(lightingDevicesProvider);
  final configs = ref.read(lightingDevicesProvider.notifier).configs;
  final normalizedRoom = _normalizeRoomRuntimeData(snapshot.roomData);
  final effectiveHasAlarm = _computeEffectiveRoomAlarm(snapshot, configs);
  if (normalizedRoom.hasAlarm == effectiveHasAlarm) {
    return normalizedRoom;
  }
  return normalizedRoom.copyWith(hasAlarm: effectiveHasAlarm);
});

RoomData _normalizeRoomRuntimeData(RoomData room) {
  final occupancy = room.occupancy;
  if (occupancy == null) {
    return room;
  }

  final expectedStatus = switch ((
    occupancy.rented,
    occupancy.occupied,
    room.mur,
  )) {
    (true, _, MurStatus.started) => RoomStatus.rentedHK,
    (false, _, MurStatus.started) => RoomStatus.unrentedHK,
    (_, true, _) => RoomStatus.rentedOccupied,
    (true, false, _) => RoomStatus.rentedVacant,
    (false, false, _) => RoomStatus.unrentedVacant,
  };

  if (expectedStatus == room.status) {
    return room;
  }
  return room.copyWith(status: expectedStatus);
}

bool _computeEffectiveRoomAlarm(
  RoomRuntimeSnapshot snapshot,
  List<LightingDeviceConfig> configs,
) {
  if (snapshot.hasDoorAlarm) {
    return true;
  }
  if (_hasHvacAlarm(snapshot.roomData.hvacDetail)) {
    return true;
  }
  if (snapshot.hasDaliLineShortCircuit) {
    return true;
  }
  if (_hasVisibleConfiguredLightingAlarm(snapshot, configs)) {
    return true;
  }
  return false;
}

bool _hasHvacAlarm(HvacDetail? hvacDetail) {
  final code = hvacDetail?.comError;
  return code != null && code != 0;
}

bool _hasVisibleConfiguredLightingAlarm(
  RoomRuntimeSnapshot snapshot,
  List<LightingDeviceConfig> configs,
) {
  if (configs.isEmpty) {
    return false;
  }

  final visibleKeys = <String>{
    for (final config in configs)
      _lightingDeviceKey(config.address, config.type),
  };
  final visibleAddresses = <int>{for (final config in configs) config.address};
  final liveDevices = <LightingDeviceSummary>[
    ...snapshot.lighting.onboardOutputs,
    ...snapshot.lighting.daliOutputs,
  ];

  for (final device in liveDevices) {
    if (!device.alarm) {
      continue;
    }
    final key = _lightingDeviceKey(device.address, device.type);
    if (visibleKeys.contains(key) ||
        visibleAddresses.contains(device.address)) {
      return true;
    }
  }

  return false;
}

String _lightingDeviceKey(int address, LightingDeviceType type) {
  return '${type.name}-$address';
}
