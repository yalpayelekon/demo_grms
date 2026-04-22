import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/alarm_models.dart';
import '../models/lighting_device.dart';
import '../models/room_models.dart';
import 'zones_provider.dart';

class AlarmsState {
  final List<AlarmData> allAlarms;
  final List<AlarmData> filteredAlarms;
  final String categoryFilter;
  final String ackFilter;
  final String statusFilter;

  AlarmsState({
    this.allAlarms = const [],
    this.filteredAlarms = const [],
    this.categoryFilter = 'All',
    this.ackFilter = 'All',
    this.statusFilter = 'All',
  });

  AlarmsState copyWith({
    List<AlarmData>? allAlarms,
    List<AlarmData>? filteredAlarms,
    String? categoryFilter,
    String? ackFilter,
    String? statusFilter,
  }) {
    return AlarmsState(
      allAlarms: allAlarms ?? this.allAlarms,
      filteredAlarms: filteredAlarms ?? this.filteredAlarms,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      ackFilter: ackFilter ?? this.ackFilter,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }
}

class AlarmsNotifier extends Notifier<AlarmsState> {
  static const Duration _alarmGenerationInterval = Duration(seconds: 90);
  static const Duration _alarmProgressionInterval = Duration(minutes: 3);
  static const int _maxAlarmEntries = 200;
  static const Duration _doorOpenAlarmThreshold = Duration(seconds: 5);
  static const List<String> _alarmCategories = <String>[
    'Long Inact.',
    'Open Door',
    'PMS',
    'RCU',
    'Lighting',
    'HVAC',
  ];

  final Random _random = Random();
  Timer? _alarmGeneratorTimer;
  Timer? _alarmProgressionTimer;
  int _sequence = 1000;
  final Map<String, DateTime> _doorOpenSinceByRoom = <String, DateTime>{};
  final Map<String, bool> _doorAlarmEventStateByRoom = <String, bool>{};

  @override
  AlarmsState build() {
    final initial = _loadSeedAlarms();
    _startSimulation();
    ref.onDispose(() {
      _alarmGeneratorTimer?.cancel();
      _alarmProgressionTimer?.cancel();
    });
    return initial;
  }

  void _startSimulation() {
    _alarmGeneratorTimer?.cancel();
    _alarmProgressionTimer?.cancel();

    _alarmGeneratorTimer = Timer.periodic(_alarmGenerationInterval, (_) {
      _generateAlarmNow();
    });

    _alarmProgressionTimer = Timer.periodic(_alarmProgressionInterval, (_) {
      _progressAlarms();
    });
  }

  AlarmsState _loadSeedAlarms() {
    final now = DateTime.now();
    final seeded = <AlarmData>[
      _seedAlarm(
        room: _pickRoomOrFallback(0, fallback: 'Room 5904'),
        category: 'Long Inact.',
        incidentAt: now.subtract(const Duration(minutes: 35)),
        acknowledgement: AlarmAcknowledgement.waitingAck,
        status: AlarmStatus.waitingAck,
        details: 'Device inactive for an extended period.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(1, fallback: 'Room 5204'),
        category: 'Open Door',
        incidentAt: now.subtract(const Duration(hours: 2, minutes: 18)),
        acknowledgement: AlarmAcknowledgement.acknowledged,
        acknowledgementAt: now.subtract(const Duration(hours: 2, minutes: 1)),
        status: AlarmStatus.waitingRepair,
        details: 'Door left open longer than threshold.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(2, fallback: 'Room 1403'),
        category: 'PMS',
        incidentAt: now.subtract(const Duration(hours: 5, minutes: 4)),
        acknowledgement: AlarmAcknowledgement.waitingAck,
        status: AlarmStatus.waitingAck,
        details: 'PMS communication mismatch detected.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(3, fallback: 'Room 1203'),
        category: 'RCU',
        incidentAt: now.subtract(const Duration(hours: 20, minutes: 10)),
        acknowledgement: AlarmAcknowledgement.acknowledged,
        acknowledgementAt: now.subtract(const Duration(hours: 19, minutes: 43)),
        status: AlarmStatus.waitingRepair,
        details: 'RCU heartbeat missing intermittently.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(4, fallback: 'Room 5008'),
        category: 'Lighting',
        incidentAt: now.subtract(const Duration(days: 1, hours: 3)),
        acknowledgement: AlarmAcknowledgement.waitingAck,
        status: AlarmStatus.waitingAck,
        details: 'Lighting controller status is inconsistent.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(5, fallback: 'Room 5106'),
        category: 'HVAC',
        incidentAt: now.subtract(
          const Duration(days: 2, hours: 1, minutes: 12),
        ),
        acknowledgement: AlarmAcknowledgement.acknowledged,
        acknowledgementAt: now.subtract(const Duration(days: 2, hours: 1)),
        status: AlarmStatus.fixed,
        details: 'HVAC deviation was fixed by onsite team.',
      ),
      _seedAlarm(
        room: _pickRoomOrFallback(6, fallback: 'Room 5915'),
        category: 'Open Door',
        incidentAt: now.subtract(const Duration(days: 3, hours: 4)),
        acknowledgement: AlarmAcknowledgement.acknowledged,
        acknowledgementAt: now.subtract(
          const Duration(days: 3, hours: 3, minutes: 45),
        ),
        status: AlarmStatus.waitingRepair,
        details: 'Door sensor repeatedly reports open state.',
      ),
    ];

    return _applyFiltersTo(seeded, 'All', 'All', 'All');
  }

  AlarmData _seedAlarm({
    required String room,
    required String category,
    required DateTime incidentAt,
    required AlarmAcknowledgement acknowledgement,
    required AlarmStatus status,
    required String details,
    DateTime? acknowledgementAt,
  }) {
    _sequence += 1;
    return AlarmData(
      id: _sequence.toString(),
      room: room,
      incidentTime: _formatIncidentTime(incidentAt),
      category: category,
      acknowledgement: acknowledgement,
      acknowledgementTime: acknowledgementAt == null
          ? ''
          : _formatIncidentTime(acknowledgementAt),
      status: status,
      details: details,
    );
  }

  List<String> _roomPool() {
    final zonesState = ref.read(zonesProvider);
    final rooms =
        zonesState.zonesData.categoryNamesBlockFloorMap.values
            .expand((floors) => floors.values.expand((roomList) => roomList))
            .toSet()
            .toList()
          ..sort();
    return rooms;
  }

  String _pickRoomOrFallback(int seed, {required String fallback}) {
    final pool = _roomPool();
    if (pool.isEmpty) {
      return fallback;
    }
    return 'Room ${pool[seed % pool.length]}';
  }

  String _formatIncidentTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd\nh:mm a').format(dateTime);
  }

  String _weightedCategory() {
    final roll = _random.nextInt(100);
    if (roll < 26) return 'Open Door';
    if (roll < 45) return 'Long Inact.';
    if (roll < 60) return 'PMS';
    if (roll < 75) return 'RCU';
    if (roll < 89) return 'Lighting';
    return 'HVAC';
  }

  void _generateAlarmNow() {
    final roomPool = _roomPool();
    final roomNumber = roomPool.isEmpty
        ? 'Room 5901'
        : 'Room ${roomPool[_random.nextInt(roomPool.length)]}';
    final category = _weightedCategory();
    final incident = DateTime.now().subtract(
      Duration(minutes: _random.nextInt(25)),
    );

    _sequence += 1;
    final newAlarm = AlarmData(
      id: _sequence.toString(),
      room: roomNumber,
      incidentTime: _formatIncidentTime(incident),
      category: category,
      acknowledgement: AlarmAcknowledgement.waitingAck,
      acknowledgementTime: '',
      status: AlarmStatus.waitingAck,
      details: 'Auto-generated mock alarm for simulation cadence.',
    );

    final merged = <AlarmData>[newAlarm, ...state.allAlarms];
    final trimmed = _trimAlarms(merged);
    state = _applyFiltersTo(
      trimmed,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );

    if (kDebugMode) {
      debugPrint(
        'AlarmsNotifier: generated alarm id=${newAlarm.id} room=${newAlarm.room} category=$category total=${trimmed.length}',
      );
    }
  }

  List<AlarmData> _trimAlarms(List<AlarmData> alarms) {
    if (alarms.length <= _maxAlarmEntries) {
      return alarms;
    }
    final mutable = List<AlarmData>.from(alarms);
    while (mutable.length > _maxAlarmEntries) {
      final fixedIndex = mutable.lastIndexWhere(
        (alarm) => alarm.status == AlarmStatus.fixed,
      );
      if (fixedIndex >= 0) {
        mutable.removeAt(fixedIndex);
      } else {
        mutable.removeLast();
      }
    }
    return mutable;
  }

  void _progressAlarms() {
    var changed = false;
    final progressed = state.allAlarms.map((alarm) {
      if (alarm.status == AlarmStatus.fixed) {
        return alarm;
      }
      if (alarm.acknowledgement == AlarmAcknowledgement.waitingAck &&
          _random.nextDouble() < 0.26) {
        changed = true;
        return alarm.copyWith(
          acknowledgement: AlarmAcknowledgement.acknowledged,
          acknowledgementTime: _formatIncidentTime(DateTime.now()),
          status: AlarmStatus.waitingRepair,
        );
      }
      if (alarm.acknowledgement == AlarmAcknowledgement.acknowledged &&
          alarm.status == AlarmStatus.waitingRepair &&
          _random.nextDouble() < 0.13) {
        changed = true;
        return alarm.copyWith(status: AlarmStatus.fixed);
      }
      return alarm;
    }).toList();

    if (!changed) {
      return;
    }
    state = _applyFiltersTo(
      progressed,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );
    if (kDebugMode) {
      final fixedCount = progressed
          .where((a) => a.status == AlarmStatus.fixed)
          .length;
      debugPrint(
        'AlarmsNotifier: progression tick applied total=${progressed.length} fixed=$fixedCount',
      );
    }
  }

  void setFilters({String? category, String? ack, String? status}) {
    state = _applyFiltersTo(
      state.allAlarms,
      category ?? state.categoryFilter,
      ack ?? state.ackFilter,
      status ?? state.statusFilter,
    );
  }

  AlarmsState _applyFiltersTo(
    List<AlarmData> all,
    String cat,
    String ack,
    String stat,
  ) {
    final filtered = all.where((alarm) {
      final matchesCategory = cat == 'All' || alarm.category == cat;
      final matchesAck = ack == 'All' || alarm.acknowledgement.label == ack;
      final matchesStatus = stat == 'All' || alarm.status.label == stat;
      return matchesCategory && matchesAck && matchesStatus;
    }).toList();

    return AlarmsState(
      allAlarms: all,
      filteredAlarms: filtered,
      categoryFilter: cat,
      ackFilter: ack,
      statusFilter: stat,
    );
  }

  void toggleAcknowledgement(String alarmId) {
    final index = state.allAlarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = state.allAlarms[index];
      final isNowAck = alarm.acknowledgement == AlarmAcknowledgement.waitingAck;

      final nowStr = isNowAck ? _formatIncidentTime(DateTime.now()) : '';

      final updatedAlarm = alarm.copyWith(
        acknowledgement: isNowAck
            ? AlarmAcknowledgement.acknowledged
            : AlarmAcknowledgement.waitingAck,
        acknowledgementTime: nowStr,
        status: isNowAck ? AlarmStatus.waitingRepair : alarm.status,
      );

      final updatedAll = List<AlarmData>.from(state.allAlarms)
        ..[index] = updatedAlarm;
      state = _applyFiltersTo(
        updatedAll,
        state.categoryFilter,
        state.ackFilter,
        state.statusFilter,
      );
    }
  }

  void toggleStatus(String alarmId) {
    final index = state.allAlarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = state.allAlarms[index];
      if (alarm.acknowledgement == AlarmAcknowledgement.acknowledged) {
        final newStatus = alarm.status == AlarmStatus.waitingRepair
            ? AlarmStatus.fixed
            : AlarmStatus.waitingRepair;
        final updatedAlarm = alarm.copyWith(status: newStatus);
        final updatedAll = List<AlarmData>.from(state.allAlarms)
          ..[index] = updatedAlarm;
        state = _applyFiltersTo(
          updatedAll,
          state.categoryFilter,
          state.ackFilter,
          state.statusFilter,
        );
      }
    }
  }

  void syncLightingDeviceAlarmsForRoom(
    String roomNumber,
    List<LightingDeviceSummary> devices, {
    bool hasDaliLineShortCircuit = false,
  }) {
    final normalizedRoom = roomNumber.trim();
    if (normalizedRoom.isEmpty) {
      return;
    }
    final roomLabel = normalizedRoom.toLowerCase().startsWith('room ')
        ? normalizedRoom
        : 'Room $normalizedRoom';
    final roomPrefix = _lightingRoomPrefix(normalizedRoom);
    final lineAlarmId = _lightingLineAlarmId(normalizedRoom);
    final now = DateTime.now();

    final activeDevices = devices.where((d) => d.alarm).toList(growable: false);
    final activeIds = <String>{};
    final updated = List<AlarmData>.from(state.allAlarms);
    const category = 'Lighting';

    if (hasDaliLineShortCircuit) {
      activeIds.add(lineAlarmId);
      final detail = 'RCU alarm: DALI line short circuit detected.';
      final index = updated.indexWhere((alarm) => alarm.id == lineAlarmId);
      if (index < 0) {
        updated.insert(
          0,
          AlarmData(
            id: lineAlarmId,
            room: roomLabel,
            incidentTime: _formatIncidentTime(now),
            category: category,
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          ),
        );
      } else {
        final existing = updated[index];
        if (existing.status == AlarmStatus.fixed) {
          updated[index] = existing.copyWith(
            incidentTime: _formatIncidentTime(now),
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          );
        } else {
          updated[index] = existing.copyWith(details: detail);
        }
      }
    }

    for (final device in activeDevices) {
      final alarmId = _lightingAlarmId(normalizedRoom, device);
      activeIds.add(alarmId);
      final detail = _lightingDeviceAlarmDetail(device);
      final index = updated.indexWhere((alarm) => alarm.id == alarmId);

      if (index < 0) {
        updated.insert(
          0,
          AlarmData(
            id: alarmId,
            room: roomLabel,
            incidentTime: _formatIncidentTime(now),
            category: category,
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          ),
        );
        continue;
      }

      final existing = updated[index];
      if (existing.status == AlarmStatus.fixed) {
        updated[index] = existing.copyWith(
          incidentTime: _formatIncidentTime(now),
          acknowledgement: AlarmAcknowledgement.waitingAck,
          acknowledgementTime: '',
          status: AlarmStatus.waitingAck,
          details: detail,
        );
      } else {
        updated[index] = existing.copyWith(details: detail);
      }
    }

    for (var i = 0; i < updated.length; i++) {
      final alarm = updated[i];
      final isLightingDeviceAlarm =
          alarm.category == category && alarm.id.startsWith(roomPrefix);
      final isLineAlarm = alarm.category == category && alarm.id == lineAlarmId;
      if (!isLightingDeviceAlarm && !isLineAlarm) {
        continue;
      }
      final stillActive = activeIds.contains(alarm.id);
      if (stillActive || alarm.status == AlarmStatus.fixed) {
        continue;
      }
      final resolvedSuffix = isLineAlarm
          ? ' Resolved (DALI line short circuit cleared).'
          : ' Resolved (Device alarm off).';
      final resolvedAt = _formatIncidentTime(now);
      updated[i] = alarm.copyWith(
        acknowledgement: AlarmAcknowledgement.acknowledged,
        acknowledgementTime:
            alarm.acknowledgement == AlarmAcknowledgement.waitingAck
            ? resolvedAt
            : alarm.acknowledgementTime,
        status: AlarmStatus.fixed,
        details: '${alarm.details}$resolvedSuffix',
      );
    }

    final trimmed = _trimAlarms(updated);
    state = _applyFiltersTo(
      trimmed,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );
  }

  void syncHvacAlarmForRoom(String roomNumber, HvacDetail? hvacDetail) {
    final normalizedRoom = roomNumber.trim();
    if (normalizedRoom.isEmpty) {
      return;
    }

    final roomLabel = normalizedRoom.toLowerCase().startsWith('room ')
        ? normalizedRoom
        : 'Room $normalizedRoom';
    final alarmId = _hvacAlarmId(normalizedRoom);
    final now = DateTime.now();
    final activeErrorCode = _activeHvacErrorCode(hvacDetail);
    final updated = List<AlarmData>.from(state.allAlarms);
    final index = updated.indexWhere((alarm) => alarm.id == alarmId);

    if (activeErrorCode != null) {
      final detail = _hvacAlarmDetail(activeErrorCode);
      if (index < 0) {
        updated.insert(
          0,
          AlarmData(
            id: alarmId,
            room: roomLabel,
            incidentTime: _formatIncidentTime(now),
            category: 'HVAC',
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          ),
        );
      } else {
        final existing = updated[index];
        if (existing.status == AlarmStatus.fixed) {
          updated[index] = existing.copyWith(
            incidentTime: _formatIncidentTime(now),
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          );
        } else {
          updated[index] = existing.copyWith(details: detail);
        }
      }
    } else if (index >= 0) {
      final existing = updated[index];
      if (existing.status != AlarmStatus.fixed) {
        final resolvedAt = _formatIncidentTime(now);
        updated[index] = existing.copyWith(
          acknowledgement: AlarmAcknowledgement.acknowledged,
          acknowledgementTime:
              existing.acknowledgement == AlarmAcknowledgement.waitingAck
              ? resolvedAt
              : existing.acknowledgementTime,
          status: AlarmStatus.fixed,
          details: '${existing.details} Resolved (HVAC error cleared).',
        );
      }
    }

    final trimmed = _trimAlarms(updated);
    state = _applyFiltersTo(
      trimmed,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );
  }

  void syncDoorAlarmForRoom(
    String roomNumber, {
    required bool hasDoorAlarm,
    required bool isDoorOpen,
    List<Map<String, dynamic>> serviceEvents = const <Map<String, dynamic>>[],
  }) {
    final normalizedRoom = roomNumber.trim();
    if (normalizedRoom.isEmpty) {
      return;
    }

    final roomLabel = normalizedRoom.toLowerCase().startsWith('room ')
        ? normalizedRoom
        : 'Room $normalizedRoom';
    final alarmId = _doorAlarmId(normalizedRoom);
    final now = DateTime.now();
    final updated = List<AlarmData>.from(state.allAlarms);
    final index = updated.indexWhere((alarm) => alarm.id == alarmId);
    final eventDoorAlarmState = _latestDoorAlarmEventState(serviceEvents);
    if (eventDoorAlarmState != null) {
      _doorAlarmEventStateByRoom[normalizedRoom] = eventDoorAlarmState;
    }

    if (isDoorOpen) {
      _doorOpenSinceByRoom.putIfAbsent(normalizedRoom, () => now);
    } else {
      _doorOpenSinceByRoom.remove(normalizedRoom);
    }

    final openedAt = _doorOpenSinceByRoom[normalizedRoom];
    final durationDoorAlarm =
        isDoorOpen &&
        openedAt != null &&
        now.difference(openedAt) >= _doorOpenAlarmThreshold;
    final eventDoorAlarm = _doorAlarmEventStateByRoom[normalizedRoom] ?? false;
    final effectiveDoorAlarm =
        hasDoorAlarm || eventDoorAlarm || durationDoorAlarm;

    if (effectiveDoorAlarm) {
      final detail = eventDoorAlarm
          ? 'Door open alarm active (RCU occupancy event).'
          : (durationDoorAlarm
                ? 'Door remained open for at least 10 seconds.'
                : 'Door open alarm active.');
      if (index < 0) {
        updated.insert(
          0,
          AlarmData(
            id: alarmId,
            room: roomLabel,
            incidentTime: _formatIncidentTime(now),
            category: 'Open Door',
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          ),
        );
      } else {
        final existing = updated[index];
        if (existing.status == AlarmStatus.fixed) {
          updated[index] = existing.copyWith(
            incidentTime: _formatIncidentTime(now),
            acknowledgement: AlarmAcknowledgement.waitingAck,
            acknowledgementTime: '',
            status: AlarmStatus.waitingAck,
            details: detail,
          );
        } else {
          updated[index] = existing.copyWith(details: detail);
        }
      }
    } else if (index >= 0) {
      final existing = updated[index];
      if (existing.status != AlarmStatus.fixed) {
        final resolvedAt = _formatIncidentTime(now);
        updated[index] = existing.copyWith(
          acknowledgement: AlarmAcknowledgement.acknowledged,
          acknowledgementTime:
              existing.acknowledgement == AlarmAcknowledgement.waitingAck
              ? resolvedAt
              : existing.acknowledgementTime,
          status: AlarmStatus.fixed,
          details: '${existing.details} Resolved (Door alarm cleared).',
        );
      }
    }

    final trimmed = _trimAlarms(updated);
    state = _applyFiltersTo(
      trimmed,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );
  }

  void syncRuntimeAlarmsForRoom(
    String roomNumber,
    List<LightingDeviceSummary> devices, {
    bool hasDaliLineShortCircuit = false,
    bool hasDoorAlarm = false,
    bool isDoorOpen = false,
    List<Map<String, dynamic>> serviceEvents = const <Map<String, dynamic>>[],
    HvacDetail? hvacDetail,
  }) {
    syncLightingDeviceAlarmsForRoom(
      roomNumber,
      devices,
      hasDaliLineShortCircuit: hasDaliLineShortCircuit,
    );
    syncHvacAlarmForRoom(roomNumber, hvacDetail);
    syncDoorAlarmForRoom(
      roomNumber,
      hasDoorAlarm: hasDoorAlarm,
      isDoorOpen: isDoorOpen,
      serviceEvents: serviceEvents,
    );
  }

  String _lightingRoomPrefix(String roomNumber) {
    final normalized = roomNumber.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    return 'lighting-device-$normalized-';
  }

  String _lightingLineAlarmId(String roomNumber) {
    final normalized = roomNumber.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    return 'lighting-line-$normalized';
  }

  String _lightingAlarmId(String roomNumber, LightingDeviceSummary device) {
    return '${_lightingRoomPrefix(roomNumber)}${device.type.name}-${device.address}';
  }

  String _lightingDeviceAlarmDetail(LightingDeviceSummary device) {
    final deviceName = device.name.trim().isEmpty
        ? 'Unnamed'
        : device.name.trim();
    final deviceLabel =
        '${device.type.name.toUpperCase()} #${device.address} ($deviceName)';
    if (device.daliSituation == 3) {
      return 'RCU alarm: Device-level lighting gear alarm. '
          'This device is unreachable'
          'Device: $deviceLabel.';
    }
    final situationSuffix = device.daliSituation != null
        ? ' (daliSituation=${device.daliSituation})'
        : '';
    return 'RCU alarm source: Device-level lighting gear alarm. '
        'Difference: this is not a line short circuit; device-level fault state '
        'is active$situationSuffix. Device: $deviceLabel.';
  }

  String _hvacAlarmId(String roomNumber) {
    final normalized = roomNumber.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    return 'hvac-error-$normalized';
  }

  String _doorAlarmId(String roomNumber) {
    final normalized = roomNumber.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    return 'door-open-$normalized';
  }

  int? _activeHvacErrorCode(HvacDetail? hvacDetail) {
    final code = hvacDetail?.comError;
    if (code == null || code == 0) {
      return null;
    }
    return code;
  }

  String _hvacAlarmDetail(int code) {
    if (code == 1) {
      return 'HVAC communication lost.';
    }
    return 'HVAC Modbus/register error detected (code: $code).';
  }

  bool? _latestDoorAlarmEventState(List<Map<String, dynamic>> events) {
    var bestTimestamp = -1;
    bool? bestState;

    for (final event in events) {
      final eventTypeRaw =
          (event['eventType'] ?? event['event_type']) as String?;
      if (eventTypeRaw == null) {
        continue;
      }
      final state = _doorAlarmStateFromEventType(eventTypeRaw);
      if (state == null) {
        continue;
      }
      final timestamp = _toInt(event['timestamp']);
      if (timestamp > bestTimestamp) {
        bestTimestamp = timestamp;
        bestState = state;
        continue;
      }
      if (bestState == null && timestamp <= 0) {
        bestState = state;
      }
    }

    return bestState;
  }

  bool? _doorAlarmStateFromEventType(String eventType) {
    final normalized = eventType.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('open_door_alarm_deleted') ||
        normalized.contains('door_open_alarm_deleted')) {
      return false;
    }
    if (normalized.contains('open_door_alarm') ||
        normalized.contains('door_open_alarm')) {
      return true;
    }
    return null;
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? -1;
    }
    return -1;
  }

  @visibleForTesting
  void setAlarmsForTesting(List<AlarmData> alarms) {
    state = _applyFiltersTo(
      alarms,
      state.categoryFilter,
      state.ackFilter,
      state.statusFilter,
    );
  }

  @visibleForTesting
  void generateAlarmNowForTesting() {
    _generateAlarmNow();
  }

  @visibleForTesting
  void progressAlarmsForTesting() {
    _progressAlarms();
  }

  @visibleForTesting
  static List<String> supportedCategoriesForTesting() =>
      List<String>.from(_alarmCategories);
}

final alarmsProvider = NotifierProvider<AlarmsNotifier, AlarmsState>(
  AlarmsNotifier.new,
);
