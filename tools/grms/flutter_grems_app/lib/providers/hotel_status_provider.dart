import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room_models.dart';
import '../models/api_result.dart';
import 'api_providers.dart';
import '../utils/timestamped_debug_log.dart';

class DemoRoomHotelSyncStatus {
  const DemoRoomHotelSyncStatus({
    this.source = 'live',
    this.targetUnreachable = false,
    this.message,
    this.reconnectAttempt = 0,
  });

  final String source;
  final bool targetUnreachable;
  final String? message;
  final int reconnectAttempt;

  DemoRoomHotelSyncStatus copyWith({
    String? source,
    bool? targetUnreachable,
    String? message,
    int? reconnectAttempt,
  }) {
    return DemoRoomHotelSyncStatus(
      source: source ?? this.source,
      targetUnreachable: targetUnreachable ?? this.targetUnreachable,
      message: message,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

final demoRoomHotelSyncStatusProvider = StateProvider<DemoRoomHotelSyncStatus>(
  (ref) => const DemoRoomHotelSyncStatus(),
);

class HotelStatusState {
  final Map<String, RoomData> rooms;
  final bool isLoading;

  HotelStatusState({this.rooms = const {}, this.isLoading = false});

  HotelStatusState copyWith({Map<String, RoomData>? rooms, bool? isLoading}) {
    return HotelStatusState(
      rooms: rooms ?? this.rooms,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HotelStatusNotifier extends Notifier<HotelStatusState> {
  @override
  HotelStatusState build() {
    return HotelStatusState();
  }

  Future<void> fetchRoomSnapshot(String roomNumber) async {
    state = state.copyWith(isLoading: true);

    final result = await ref
        .read(roomControlApiProvider)
        .getRoomSnapshot(roomNumber);
    if (result is Success<RoomData>) {
      final updatedRooms = Map<String, RoomData>.from(state.rooms);
      updatedRooms[roomNumber] = result.value;
      if (kDebugMode) {
        debugLog(
          'HotelStatusNotifier: backend override applied for room=$roomNumber',
        );
      }
      _publishDemoRoomStatus(
        source: result.value.dataSource,
        targetUnreachable: false,
        message: null,
      );
      state = state.copyWith(rooms: updatedRooms, isLoading: false);
    } else {
      if (kDebugMode) {
        debugLog(
          'HotelStatusNotifier: backend snapshot failed for room=$roomNumber; preserving local simulator state',
        );
      }
      _publishDemoRoomStatus(
        targetUnreachable: true,
        message: 'Target unreachable',
      );
      state = state.copyWith(isLoading: false);
    }
  }

  void applyBackendRoomSnapshot(String roomNumber, Map<String, dynamic> json) {
    try {
      final parsed = RoomData.fromJson({
        ...json,
        if ((json['number'] as String?)?.isEmpty ?? true) 'number': roomNumber,
      });
      final updatedRooms = Map<String, RoomData>.from(state.rooms);
      updatedRooms[roomNumber] = parsed;
      state = state.copyWith(rooms: updatedRooms);
      if (kDebugMode) {
        debugLog(
          'HotelStatusNotifier: live snapshot applied room=$roomNumber '
          'status=${parsed.status.label} dnd=${parsed.dnd.label} mur=${parsed.mur.label}',
        );
      }
      _publishDemoRoomStatus(
        source: parsed.dataSource,
        targetUnreachable: false,
        message: null,
      );
    } catch (error) {
      if (kDebugMode) {
        debugLog(
          'HotelStatusNotifier: failed to parse live snapshot for room=$roomNumber: $error',
        );
      }
    }
  }

  void setConnectionWarning({
    required String message,
    required int reconnectAttempt,
  }) {
    _publishDemoRoomStatus(
      targetUnreachable: true,
      message: message,
      reconnectAttempt: reconnectAttempt,
    );
  }

  void _publishDemoRoomStatus({
    String? source,
    bool? targetUnreachable,
    String? message,
    int? reconnectAttempt,
  }) {
    final notifier = ref.read(demoRoomHotelSyncStatusProvider.notifier);
    final current = notifier.state;
    notifier.state = current.copyWith(
      source: source,
      targetUnreachable: targetUnreachable,
      message: message,
      reconnectAttempt: reconnectAttempt,
    );
  }

  Future<ApiResult<void>> toggleLighting(
    String roomNumber,
    bool currentStatus,
  ) async {
    const int mainLightAddress = 1;
    final int targetLevel = currentStatus ? 0 : 100;

    final result = await ref
        .read(roomControlApiProvider)
        .setLightingLevel(roomNumber, mainLightAddress, targetLevel);
    if (result is Success<void>) {
      if (state.rooms.containsKey(roomNumber)) {
        final updatedRooms = Map<String, RoomData>.from(state.rooms);
        updatedRooms[roomNumber] = updatedRooms[roomNumber]!.copyWith(
          lightingOn: !currentStatus,
        );
        state = state.copyWith(rooms: updatedRooms);
      }
    }
    return result;
  }

  Future<ApiResult<void>> updateHvac(
    String roomNumber,
    Map<String, dynamic> updates,
  ) async {
    final result = await ref
        .read(roomControlApiProvider)
        .updateHvac(roomNumber, updates);
    if (result is Success<HvacDetail>) {
      if (state.rooms.containsKey(roomNumber)) {
        final updatedRooms = Map<String, RoomData>.from(state.rooms);
        final currentRoom = updatedRooms[roomNumber]!;
        updatedRooms[roomNumber] = currentRoom.copyWith(
          hvac: updates.containsKey('onOff')
              ? (updates['onOff'] == 1 ? HvacStatus.active : HvacStatus.off)
              : currentRoom.hvac,
          hvacDetail: result.value,
        );
        state = state.copyWith(rooms: updatedRooms);
      }
    }

    if (result is Success<HvacDetail>) {
      return ApiResult.success(null);
    }
    return ApiResult.failure((result as Failure<HvacDetail>).error);
  }

  void initializeRooms(List<String> roomNumbers) {
    final updatedRooms = Map<String, RoomData>.from(state.rooms);
    bool added = false;
    var addedCount = 0;
    for (var num in roomNumbers) {
      if (!updatedRooms.containsKey(num)) {
        updatedRooms[num] = generateSimulatedRoomState(num);
        added = true;
        addedCount += 1;
      }
    }
    if (added) {
      if (kDebugMode) {
        debugLog(
          'HotelStatusNotifier: initialized $addedCount simulated rooms '
          '(total now ${updatedRooms.length})',
        );
      }
      state = state.copyWith(rooms: updatedRooms);
    }
  }
}

final hotelStatusProvider =
    NotifierProvider<HotelStatusNotifier, HotelStatusState>(
      HotelStatusNotifier.new,
    );

RoomData generateSimulatedRoomState(String roomNumber) {
  if (_isDemoRoomNumber(roomNumber)) {
    return RoomData(
      number: roomNumber,
      status: RoomStatus.rentedVacant,
      hasAlarm: false,
      lightingOn: true,
      hvac: HvacStatus.active,
      hvacDetail: const HvacDetail(
        state: HvacStatus.active,
        onOff: 1,
        roomTemperature: 22.5,
        setPoint: 23.0,
        mode: 3,
        fanMode: 4,
        comfortTemperature: 23.0,
        lowerSetpoint: 20.0,
        upperSetpoint: 26.0,
        keylockFunction: 0,
        occupancyInput: 0,
        runningStatus: 3,
        comError: 0,
        fidelio: 0,
      ),
      dnd: DndStatus.off,
      mur: MurStatus.finished,
      laundry: LaundryStatus.finished,
      occupancy: const RoomOccupancy(
        occupied: false,
        rented: true,
        doorOpen: false,
        hasDoorAlarm: false,
      ),
    );
  }

  final seed = _seedFromRoomNumber(roomNumber);

  final statusRoll = _roll(seed, 11);
  final status = statusRoll < 40
      ? RoomStatus.rentedOccupied
      : statusRoll < 58
      ? RoomStatus.rentedHK
      : statusRoll < 76
      ? RoomStatus.rentedVacant
      : statusRoll < 89
      ? RoomStatus.unrentedHK
      : RoomStatus.unrentedVacant;

  final hasAlarm = _roll(seed, 23) < 20;
  final lightingOn = _roll(seed, 31) < 65;

  final hvacRoll = _roll(seed, 41);
  final hvac = hvacRoll < 35
      ? HvacStatus.cold
      : hvacRoll < 50
      ? HvacStatus.hot
      : hvacRoll < 75
      ? HvacStatus.active
      : HvacStatus.off;

  final dnd = _roll(seed, 53) < 15 ? DndStatus.on : DndStatus.off;

  final murRoll = _roll(seed, 67);
  final mur = murRoll < 7
      ? MurStatus.delayed
      : murRoll < 18
      ? MurStatus.started
      : murRoll < 30
      ? MurStatus.requested
      : MurStatus.finished;

  final laundry = _roll(seed, 79) < 18
      ? LaundryStatus.requested
      : LaundryStatus.finished;

  return RoomData(
    number: roomNumber,
    status: status,
    hasAlarm: hasAlarm,
    lightingOn: lightingOn,
    hvac: hvac,
    dnd: dnd,
    mur: mur,
    laundry: laundry,
    murDelayedMinutes: mur == MurStatus.delayed
        ? 5 + (_roll(seed, 97) % 40)
        : null,
  );
}

bool _isDemoRoomNumber(String roomNumber) {
  return roomNumber.trim().toLowerCase() == 'demo 101';
}

int _seedFromRoomNumber(String roomNumber) {
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
