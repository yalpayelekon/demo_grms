import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/service_models.dart';
import '../models/service_policy.dart';
import 'demo_room_snapshot_provider.dart';
import 'room_service_settings_provider.dart';
import 'zones_provider.dart';
import '../utils/timestamped_debug_log.dart';

class DemoRoomServiceSyncStatus {
  const DemoRoomServiceSyncStatus({
    this.source = 'live',
    this.connected = false,
    this.targetUnreachable = false,
    this.message,
    this.reconnectAttempt = 0,
  });

  final String source;
  final bool connected;
  final bool targetUnreachable;
  final String? message;
  final int reconnectAttempt;
}

final demoRoomServiceSyncStatusProvider =
    StateProvider<DemoRoomServiceSyncStatus>(
      (ref) => const DemoRoomServiceSyncStatus(),
    );

class RoomServiceNotifier extends Notifier<List<RoomServiceEntry>> {
  static const String _demoRoomNumber = 'Demo 101';

  final Random _random = Random();
  Timer? _mockTimer;
  Timer? _transitionTimer;
  final Map<String, String> _lastSnapshotStateByTypeKey = {};
  int _lastDemoSnapshotVersion = 0;

  @override
  List<RoomServiceEntry> build() {
    state = _initializeMockData(_roomPool());
    _startMockGenerator();
    _startStatusTransitions();
    _startDemoRoomLiveSync();

    ref.onDispose(() {
      _mockTimer?.cancel();
      _transitionTimer?.cancel();
    });

    return state;
  }

  List<String> _roomPool() {
    final zonesState = ref.read(zonesProvider);
    final allRooms =
        zonesState.zonesData.categoryNamesBlockFloorMap.values
            .expand((floors) => floors.values.expand((rooms) => rooms))
            .where(
              (room) =>
                  room.trim().toLowerCase() != _demoRoomNumber.toLowerCase(),
            )
            .toSet()
            .toList()
          ..sort();
    return allRooms;
  }

  int _floorFromRoom(String roomNumber) {
    final digits = roomNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 2) {
      return int.tryParse(digits.substring(0, 2)) ?? 0;
    }
    if (digits.isNotEmpty) {
      return int.tryParse(digits[0]) ?? 0;
    }
    return 0;
  }

  List<RoomServiceEntry> _initializeMockData(List<String> roomPool) {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    if (roomPool.isEmpty) {
      return [];
    }
    final seeded = <RoomServiceEntry>[];
    var dndCount = 0;
    var murCount = 0;
    var laundryCount = 0;

    for (final room in roomPool) {
      final seed = _seedFromRoom(room);

      if (_roll(seed, 1302) < 18) {
        laundryCount += 1;
        seeded.add(
          RoomServiceEntry(
            id: 'rs-$room-Laundry-seed',
            roomNumber: room,
            floor: _floorFromRoom(room),
            serviceType: ServiceType.laundry,
            serviceState: 'Requested',
            activationTime: fmt.format(
              now.subtract(Duration(minutes: 10 + (_roll(seed, 22) % 60))),
            ),
            eventTimestamp: now
                .subtract(Duration(minutes: 10 + (_roll(seed, 22) % 60)))
                .millisecondsSinceEpoch,
            delayedMinutes: 0,
            acknowledgement: ServiceAcknowledgement.waitingAck,
          ),
        );
      }

      final murRoll = _roll(seed, 1104);
      if (murRoll < 25) {
        murCount += 1;
        final murState = murRoll < 9
            ? 'Delayed'
            : murRoll < 17
            ? 'Started'
            : 'Requested';
        seeded.add(
          RoomServiceEntry(
            id: 'rs-$room-MUR-seed',
            roomNumber: room,
            floor: _floorFromRoom(room),
            serviceType: ServiceType.mur,
            serviceState: murState,
            activationTime: fmt.format(
              now.subtract(Duration(minutes: 5 + (_roll(seed, 31) % 75))),
            ),
            eventTimestamp: now
                .subtract(Duration(minutes: 5 + (_roll(seed, 31) % 75)))
                .millisecondsSinceEpoch,
            delayedMinutes: murState == 'Delayed'
                ? 5 + (_roll(seed, 33) % 40)
                : 0,
            acknowledgement: ServiceAcknowledgement.waitingAck,
          ),
        );
      }

      if (_roll(seed, 1203) < 16) {
        dndCount += 1;
        seeded.add(
          RoomServiceEntry(
            id: 'rs-$room-DND-seed',
            roomNumber: room,
            floor: _floorFromRoom(room),
            serviceType: ServiceType.dnd,
            serviceState: 'On',
            activationTime: fmt.format(
              now.subtract(Duration(minutes: 30 + (_roll(seed, 41) % 180))),
            ),
            eventTimestamp: now
                .subtract(Duration(minutes: 30 + (_roll(seed, 41) % 180)))
                .millisecondsSinceEpoch,
            delayedMinutes: 0,
            acknowledgement: ServiceAcknowledgement.none,
          ),
        );
      }
    }

    if (kDebugMode) {
      debugLog(
        'RoomServiceNotifier: seeding mock services with roomPool=${roomPool.length} '
        '(dnd=$dndCount,mur=$murCount,laundry=$laundryCount)',
      );
    }

    seeded.sort((a, b) => b.eventTimestamp.compareTo(a.eventTimestamp));
    if (seeded.length > 100) {
      return seeded.sublist(0, 100);
    }
    return seeded;
  }

  void _startMockGenerator() {
    _mockTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final roomPool = _roomPool();
      if (roomPool.isEmpty) {
        return;
      }
      final roomNum = roomPool[_random.nextInt(roomPool.length)];
      final type =
          ServiceType.values[_random.nextInt(ServiceType.values.length)];
      final now = DateTime.now();
      final fmt = DateFormat('yyyy-MM-dd HH:mm');

      final newEntry = RoomServiceEntry(
        id: 'rs-$roomNum-${type.label}-${now.millisecondsSinceEpoch}',
        roomNumber: roomNum,
        floor: _floorFromRoom(roomNum),
        serviceType: type,
        serviceState: type == ServiceType.dnd ? 'On' : 'Requested',
        activationTime: fmt.format(now),
        eventTimestamp: now.millisecondsSinceEpoch,
        delayedMinutes: 0,
        acknowledgement: type == ServiceType.dnd
            ? ServiceAcknowledgement.none
            : ServiceAcknowledgement.waitingAck,
      );

      final nextState = applyCrossCancelOnNewEntry(state, newEntry);
      _logPolicyNotes(nextState);
      state = nextState;
      if (state.length > 100) {
        state = state.sublist(0, 100);
      }
      if (kDebugMode) {
        debugLog(
          'RoomServiceNotifier: generated ${type.label} event for room=$roomNum',
        );
      }
    });
  }

  void _startStatusTransitions() {
    _transitionTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _applyThresholdTransitions(DateTime.now());
    });
  }

  void _logPolicyNotes(List<RoomServiceEntry> entries) {
    if (!kDebugMode) {
      return;
    }
    for (final e in entries.take(10)) {
      if (e.note == null || !e.note!.startsWith('policy.cancel')) {
        continue;
      }
      debugLog('RoomServiceNotifier: ${e.note}');
    }
  }

  void toggleAcknowledgement(String id) {
    final index = state.indexWhere((s) => s.id == id);
    if (index != -1) {
      final item = state[index];
      if (item.serviceType == ServiceType.dnd) return;

      final newAck = item.acknowledgement == ServiceAcknowledgement.waitingAck
          ? ServiceAcknowledgement.acknowledged
          : ServiceAcknowledgement.waitingAck;

      final updatedList = List<RoomServiceEntry>.from(state);
      updatedList[index] = item.copyWith(
        acknowledgement: newAck,
        acknowledgementTime: newAck == ServiceAcknowledgement.acknowledged
            ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())
            : null,
      );
      state = updatedList;
    }
  }

  @visibleForTesting
  void setEntriesForTesting(List<RoomServiceEntry> entries) {
    state = entries;
  }

  void _startDemoRoomLiveSync() {
    ref.listen(demoRoomSnapshotProvider, (previous, next) {
      _publishDemoSyncStatus(
        source: next.source,
        connected: next.connected,
        targetUnreachable: next.targetUnreachable,
        message: next.message,
        reconnectAttempt: next.reconnectAttempt,
      );
      if (previous?.snapshotVersion == next.snapshotVersion ||
          next.snapshot == null) {
        return;
      }
      _lastDemoSnapshotVersion = next.snapshotVersion;
      _applyBackendServiceSnapshot(next.snapshot!);
    });

    scheduleMicrotask(() {
      final current = ref.read(demoRoomSnapshotProvider);
      _publishDemoSyncStatus(
        source: current.source,
        connected: current.connected,
        targetUnreachable: current.targetUnreachable,
        message: current.message,
        reconnectAttempt: current.reconnectAttempt,
      );
      if (current.snapshot != null &&
          current.snapshotVersion != 0 &&
          current.snapshotVersion != _lastDemoSnapshotVersion) {
        _lastDemoSnapshotVersion = current.snapshotVersion;
        _applyBackendServiceSnapshot(current.snapshot!);
      }
    });
  }

  void _publishDemoSyncStatus({
    bool? connected,
    String? source,
    String? message,
    bool? targetUnreachable,
    int? reconnectAttempt,
  }) {
    final snapshot = ref.read(demoRoomSnapshotProvider);
    final status = DemoRoomServiceSyncStatus(
      source: source ?? snapshot.source,
      connected: connected ?? snapshot.connected,
      targetUnreachable: targetUnreachable ?? snapshot.targetUnreachable,
      message: message ?? snapshot.message,
      reconnectAttempt: reconnectAttempt ?? snapshot.reconnectAttempt,
    );
    ref.read(demoRoomServiceSyncStatusProvider.notifier).state = status;
  }

  void _applyBackendServiceSnapshot(Map<String, dynamic> snapshotJson) {
    final meta = snapshotJson['_meta'];
    if (meta is Map) {
      final source = (meta['source'] as String?)?.trim();
      if (source != null && source.isNotEmpty) {
        _publishDemoSyncStatus(source: source);
      }
    }

    final parsed = <RoomServiceEntry>[];
    final rawEvents = snapshotJson['serviceEvents'];
    if (rawEvents is List) {
      for (var i = 0; i < rawEvents.length; i++) {
        final raw = rawEvents[i];
        if (raw is! Map) {
          continue;
        }
        final event = _parseBackendServiceEvent(
          Map<String, dynamic>.from(raw),
          i,
        );
        if (event != null) {
          parsed.add(event);
        }
      }
    }

    if (parsed.isEmpty) {
      parsed.addAll(_buildServiceEntriesFromSnapshotStates(snapshotJson));
    }

    if (parsed.isEmpty) {
      return;
    }

    final merged = _mergeHistory(parsed, state);
    state = merged.length > 100 ? merged.sublist(0, 100) : merged;

    if (kDebugMode) {
      final demoEntries = state
          .where(
            (e) =>
                e.roomNumber.trim().toLowerCase() ==
                _demoRoomNumber.toLowerCase(),
          )
          .toList();
      debugLog(
        'RoomServiceNotifier: snapshot apply parsed=${parsed.length} '
        'serviceEvents=${rawEvents is List ? rawEvents.length : 0} '
        'stateCount=${state.length} demoCount=${demoEntries.length}',
      );
    }
  }

  List<RoomServiceEntry> _buildServiceEntriesFromSnapshotStates(
    Map<String, dynamic> snapshotJson,
  ) {
    final room = (snapshotJson['number'] as String?)?.trim().isNotEmpty == true
        ? (snapshotJson['number'] as String).trim()
        : _demoRoomNumber;
    final now = DateTime.now();
    final nowTs = now.millisecondsSinceEpoch;
    final activationTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    final dndState = _mapSnapshotState(
      ServiceType.dnd,
      (snapshotJson['dnd'] as String?)?.trim() ?? '',
    );
    final murState = _mapSnapshotState(
      ServiceType.mur,
      (snapshotJson['mur'] as String?)?.trim() ?? '',
    );
    final laundryState = _mapSnapshotState(
      ServiceType.laundry,
      (snapshotJson['laundry'] as String?)?.trim() ?? '',
    );

    final states = <ServiceType, String>{
      ServiceType.dnd: dndState,
      ServiceType.mur: murState,
      ServiceType.laundry: laundryState,
    };

    final parsed = <RoomServiceEntry>[];
    states.forEach((serviceType, serviceState) {
      if (serviceState.trim().isEmpty) {
        return;
      }
      final typeKey = '$room|${serviceType.name}';
      final previousState = _lastSnapshotStateByTypeKey[typeKey];
      if (previousState == serviceState) {
        return;
      }
      _lastSnapshotStateByTypeKey[typeKey] = serviceState;

      parsed.add(
        RoomServiceEntry(
          id: 'snapshot-$room-${serviceType.label}-$nowTs',
          roomNumber: room,
          floor: _floorFromRoom(room),
          serviceType: serviceType,
          serviceState: serviceState,
          activationTime: activationTime,
          eventTimestamp: nowTs,
          delayedMinutes: 0,
          acknowledgement: _defaultAckForState(serviceType, serviceState),
          acknowledgementTime: null,
        ),
      );
    });

    return parsed;
  }

  String _mapSnapshotState(ServiceType serviceType, String rawState) {
    final normalized = rawState.trim().toLowerCase();
    if (serviceType == ServiceType.dnd) {
      return switch (normalized) {
        'yellow' || 'on' || 'requested' || 'active' => 'On',
        _ => 'Off',
      };
    }

    if (serviceType == ServiceType.mur) {
      return switch (normalized) {
        'yellow' || 'progress' || 'requested' => 'Requested',
        'started' => 'Started',
        'delayed' => 'Delayed',
        'cancelled' || 'canceled' => 'Canceled',
        _ => 'Finished',
      };
    }

    return switch (normalized) {
      'yellow' || 'progress' || 'requested' || 'on' || 'active' => 'Requested',
      'delayed' => 'Delayed',
      'cancelled' || 'canceled' || 'passive' || 'off' => 'Finished',
      _ => 'Finished',
    };
  }

  RoomServiceEntry? _parseBackendServiceEvent(
    Map<String, dynamic> eventJson,
    int index,
  ) {
    final serviceTypeRaw =
        ((eventJson['serviceType'] ?? eventJson['service_type']) as String?)
            ?.trim() ??
        '';
    final eventTypeRaw =
        ((eventJson['eventType'] ?? eventJson['event_type']) as String?)
            ?.trim() ??
        '';
    final roomRaw =
        ((eventJson['roomNumber'] ?? eventJson['room_number']) as String?)
            ?.trim();
    final room = roomRaw?.isNotEmpty == true ? roomRaw! : _demoRoomNumber;

    final timestampSeconds = _toInt(eventJson['timestamp']);
    final timestampMillis =
        (timestampSeconds > 0
                ? timestampSeconds * 1000
                : DateTime.now().millisecondsSinceEpoch)
            .toInt();

    final serviceType = ServiceTypeExtension.fromString(serviceTypeRaw);
    final serviceState = _mapBackendEventToServiceState(
      serviceType,
      eventTypeRaw,
    );
    final ack = _defaultAckForState(serviceType, serviceState);
    final activationTime =
        (eventJson['formattedTimestamp'] as String?)?.trim().isNotEmpty == true
        ? (eventJson['formattedTimestamp'] as String).trim()
        : DateFormat(
            'yyyy-MM-dd HH:mm:ss',
          ).format(DateTime.fromMillisecondsSinceEpoch(timestampMillis));

    return RoomServiceEntry(
      id: 'backend-$room-${serviceType.label}-${eventTypeRaw.toLowerCase()}-$timestampMillis-$index',
      roomNumber: room,
      floor: _floorFromRoom(room),
      serviceType: serviceType,
      serviceState: serviceState,
      activationTime: activationTime,
      eventTimestamp: timestampMillis,
      delayedMinutes: 0,
      acknowledgement: ack,
      acknowledgementTime: null,
    );
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _mapBackendEventToServiceState(
    ServiceType serviceType,
    String eventType,
  ) {
    final normalized = eventType.trim().toLowerCase();
    final isCanceled =
        normalized.contains('request_canceled') ||
        normalized.contains('request canceled') ||
        normalized.contains('cancelled') ||
        normalized.contains('canceled') ||
        normalized.contains('passive') ||
        normalized == 'deactivated';
    final isRequested =
        normalized.contains('requested') ||
        normalized.contains('activated') ||
        normalized.contains('active') ||
        normalized == 'requested';
    final isStarted = normalized.contains('started') || normalized == 'started';
    final isFinished =
        normalized.contains('finished') || normalized == 'finished';

    if (serviceType == ServiceType.dnd) {
      if (isCanceled) return 'Off';
      if (isRequested) return 'On';
      return 'Off';
    }

    if (isCanceled) return 'Canceled';
    if (isFinished) return 'Finished';
    if (isStarted) return 'Started';
    if (isRequested) return 'Requested';
    return serviceType == ServiceType.mur ? 'Requested' : 'Requested';
  }

  ServiceAcknowledgement _defaultAckForState(
    ServiceType serviceType,
    String serviceState,
  ) {
    if (serviceType == ServiceType.dnd) {
      return ServiceAcknowledgement.none;
    }
    switch (serviceState) {
      case 'Requested':
      case 'Started':
      case 'Delayed':
        return ServiceAcknowledgement.waitingAck;
      default:
        return ServiceAcknowledgement.none;
    }
  }

  void _applyThresholdTransitions(DateTime now) {
    final settings = ref.read(roomServiceSettingsProvider).settings;
    _applyThresholdTransitionsWithThresholds(
      now,
      murThreshold: settings.murDelayThresholdSeconds,
      laundryThreshold: settings.laundryDelayThresholdSeconds,
    );
  }

  void _applyThresholdTransitionsWithThresholds(
    DateTime now, {
    required int murThreshold,
    required int laundryThreshold,
  }) {
    final safeMurThreshold = murThreshold < 1 ? 1 : murThreshold;
    final safeLaundryThreshold = laundryThreshold < 1 ? 1 : laundryThreshold;

    var transitionCount = 0;
    final updated = <RoomServiceEntry>[];

    for (final entry in state) {
      final elapsedSeconds = _elapsedSeconds(entry, now);
      if (elapsedSeconds <= 0) {
        updated.add(entry);
        continue;
      }

      if (entry.serviceType == ServiceType.mur &&
          (entry.serviceState == 'Requested' ||
              entry.serviceState == 'Started') &&
          elapsedSeconds > safeMurThreshold) {
        transitionCount += 1;
        updated.add(
          entry.copyWith(
            serviceState: 'Delayed',
            delayedMinutes: _secondsToMinutes(elapsedSeconds),
            note: 'threshold_transition mur>${safeMurThreshold}s',
          ),
        );
        continue;
      }

      if (entry.serviceType == ServiceType.laundry &&
          (entry.serviceState == 'Requested' ||
              entry.serviceState == 'Started') &&
          elapsedSeconds > safeLaundryThreshold) {
        transitionCount += 1;
        final nowText = DateFormat('yyyy-MM-dd HH:mm').format(now);
        updated.add(
          entry.copyWith(
            serviceState: 'Finished',
            endTime: nowText,
            finishedMinutes: _secondsToMinutes(elapsedSeconds),
            acknowledgement: ServiceAcknowledgement.none,
            note: 'threshold_transition laundry>${safeLaundryThreshold}s',
          ),
        );
        continue;
      }

      if (entry.serviceType == ServiceType.mur &&
          entry.serviceState == 'Delayed') {
        updated.add(
          entry.copyWith(delayedMinutes: _secondsToMinutes(elapsedSeconds)),
        );
        continue;
      }

      updated.add(entry);
    }

    if (transitionCount > 0) {
      state = updated;
    }

    if (kDebugMode) {
      final demoByState = <String, int>{};
      for (final e in state.where((e) => e.roomNumber == _demoRoomNumber)) {
        demoByState[e.serviceState] = (demoByState[e.serviceState] ?? 0) + 1;
      }
      debugLog(
        'RoomServiceNotifier: threshold tick '
        'mur=${safeMurThreshold}s laundry=${safeLaundryThreshold}s '
        'transitions=$transitionCount demoStates=$demoByState',
      );
    }
  }

  int _elapsedSeconds(RoomServiceEntry entry, DateTime now) {
    if (entry.eventTimestamp > 0) {
      return now
          .difference(DateTime.fromMillisecondsSinceEpoch(entry.eventTimestamp))
          .inSeconds;
    }
    final parsed = _tryParseDateTime(entry.activationTime);
    if (parsed == null) return 0;
    return now.difference(parsed).inSeconds;
  }

  DateTime? _tryParseDateTime(String value) {
    final candidates = [
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd HH:mm'),
    ];
    for (final format in candidates) {
      try {
        return format.parse(value);
      } catch (_) {
        // Try next format.
      }
    }
    return null;
  }

  int _secondsToMinutes(int seconds) {
    if (seconds <= 0) return 0;
    final minutes = (seconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  List<RoomServiceEntry> _mergeHistory(
    List<RoomServiceEntry> incoming,
    List<RoomServiceEntry> current,
  ) {
    final all = [...incoming, ...current];
    final deduped = <String, RoomServiceEntry>{};
    for (final entry in all) {
      final key =
          '${entry.roomNumber}|${entry.serviceType.name}|${entry.serviceState}|${entry.eventTimestamp}';
      deduped.putIfAbsent(key, () => entry);
    }
    final merged = deduped.values.toList()
      ..sort((a, b) => b.eventTimestamp.compareTo(a.eventTimestamp));
    return merged;
  }

  @visibleForTesting
  void applyThresholdTransitionsForTesting(
    DateTime now, {
    int? murThresholdSeconds,
    int? laundryThresholdSeconds,
  }) {
    final needSettings =
        murThresholdSeconds == null || laundryThresholdSeconds == null;
    final settings = needSettings
        ? ref.read(roomServiceSettingsProvider).settings
        : null;
    _applyThresholdTransitionsWithThresholds(
      now,
      murThreshold: murThresholdSeconds ?? settings!.murDelayThresholdSeconds,
      laundryThreshold:
          laundryThresholdSeconds ?? settings!.laundryDelayThresholdSeconds,
    );
  }

  @visibleForTesting
  void applyBackendSnapshotForTesting(Map<String, dynamic> snapshotJson) {
    _applyBackendServiceSnapshot(snapshotJson);
  }

  @visibleForTesting
  String mapBackendEventForTesting(ServiceType type, String eventType) {
    return _mapBackendEventToServiceState(type, eventType);
  }
}

int _seedFromRoom(String roomNumber) {
  final digitsOnly = roomNumber.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.isNotEmpty) {
    return int.tryParse(digitsOnly) ?? roomNumber.hashCode.abs();
  }
  return roomNumber.hashCode.abs();
}

int _roll(int seed, int salt) {
  var x = seed ^ (salt * 0x9E3779B9);
  x = (x ^ (x >> 16)) * 0x45D9F3B;
  x = (x ^ (x >> 16)) * 0x45D9F3B;
  x = x ^ (x >> 16);
  return x.abs() % 100;
}

final roomServiceProvider =
    NotifierProvider<RoomServiceNotifier, List<RoomServiceEntry>>(
      RoomServiceNotifier.new,
    );
