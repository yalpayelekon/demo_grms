import 'package:flutter/foundation.dart';

enum RoomStatus {
  rentedOccupied('Rented Occupied'),
  rentedHK('Rented HK'),
  rentedVacant('Rented Vacant'),
  unrentedHK('Unrented HK'),
  unrentedVacant('Unrented Vacant'),
  malfunction('Malfunction');

  final String label;
  const RoomStatus(this.label);

  static RoomStatus fromString(String value) {
    return RoomStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => RoomStatus.unrentedVacant,
    );
  }
}

enum DndStatus {
  off('Off'),
  on('On');

  final String label;
  const DndStatus(this.label);

  static DndStatus fromString(String value) {
    if (value == 'Yellow') return DndStatus.on;
    return DndStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => DndStatus.off,
    );
  }
}

enum MurStatus {
  requested('Requested'),
  delayed('Delayed'),
  started('Started'),
  finished('Finished'),
  canceled('Canceled');

  final String label;
  const MurStatus(this.label);

  static MurStatus fromString(String value) {
    if (value == 'Yellow') return MurStatus.started;
    if (value == 'Off') return MurStatus.finished;
    return MurStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => MurStatus.finished,
    );
  }
}

enum LaundryStatus {
  requested('Requested'),
  delayed('Delayed'),
  finished('Finished'),
  canceled('Canceled');

  final String label;
  const LaundryStatus(this.label);

  static LaundryStatus fromString(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'off' || normalized == 'passive') {
      return LaundryStatus.finished;
    }
    if (normalized == 'on' ||
        normalized == 'yellow' ||
        normalized == 'active' ||
        normalized == 'progress' ||
        normalized == 'requested') {
      return LaundryStatus.requested;
    }
    if (normalized == 'delayed') {
      return LaundryStatus.delayed;
    }
    return LaundryStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => LaundryStatus.finished,
    );
  }
}

enum HvacStatus {
  off('Off'),
  active('Active'),
  cold('Cold'),
  hot('Hot');

  final String label;
  const HvacStatus(this.label);

  static HvacStatus fromString(String value) {
    return HvacStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => HvacStatus.off,
    );
  }
}

@immutable
class RoomOccupancy {
  const RoomOccupancy({
    required this.occupied,
    required this.rented,
    this.doorOpen,
    this.hasDoorAlarm,
  });

  final bool occupied;
  final bool rented;
  final bool? doorOpen;
  final bool? hasDoorAlarm;

  factory RoomOccupancy.fromJson(Map<String, dynamic> json) {
    return RoomOccupancy(
      occupied: json['occupied'] as bool? ?? false,
      rented: json['rented'] as bool? ?? true,
      doorOpen: json['doorOpen'] as bool?,
      hasDoorAlarm: json['hasDoorAlarm'] as bool?,
    );
  }
}

@immutable
class HvacDetail {
  final HvacStatus state;
  final int? onOff;
  final double? roomTemperature;
  final double? setPoint;
  final int? mode;
  final int? fanMode;
  final double? comfortTemperature;
  final double? lowerSetpoint;
  final double? upperSetpoint;
  final int? keylockFunction;
  final int? occupancyInput;
  final int? runningStatus;
  final int? comError;
  final int? fidelio;

  const HvacDetail({
    required this.state,
    this.onOff,
    this.roomTemperature,
    this.setPoint,
    this.mode,
    this.fanMode,
    this.comfortTemperature,
    this.lowerSetpoint,
    this.upperSetpoint,
    this.keylockFunction,
    this.occupancyInput,
    this.runningStatus,
    this.comError,
    this.fidelio,
  });

  factory HvacDetail.fromJson(Map<String, dynamic> json) {
    return HvacDetail(
      state: HvacStatus.fromString(json['state'] as String? ?? 'Off'),
      onOff: json['onOff'] as int?,
      roomTemperature: (json['roomTemperature'] as num?)?.toDouble(),
      setPoint: (json['setPoint'] as num?)?.toDouble(),
      mode: json['mode'] as int?,
      fanMode: json['fanMode'] as int?,
      comfortTemperature: (json['comfortTemperature'] as num?)?.toDouble(),
      lowerSetpoint: (json['lowerSetpoint'] as num?)?.toDouble(),
      upperSetpoint: (json['upperSetpoint'] as num?)?.toDouble(),
      keylockFunction: json['keylockFunction'] as int?,
      occupancyInput: json['occupancyInput'] as int?,
      runningStatus: json['runningStatus'] as int?,
      comError: json['comError'] as int?,
      fidelio: json['fidelio'] as int?,
    );
  }
}

@immutable
class RoomData {
  final String number;
  final RoomStatus status;
  final bool hasAlarm;
  final bool lightingOn;
  final HvacStatus hvac;
  final HvacDetail? hvacDetail;
  final DndStatus dnd;
  final MurStatus mur;
  final LaundryStatus laundry;
  final int? murDelayedMinutes;
  final String dataSource;
  final bool stale;
  final RoomOccupancy? occupancy;

  const RoomData({
    required this.number,
    required this.status,
    required this.hasAlarm,
    required this.lightingOn,
    required this.hvac,
    this.hvacDetail,
    required this.dnd,
    required this.mur,
    required this.laundry,
    this.murDelayedMinutes,
    this.dataSource = 'live',
    this.stale = false,
    this.occupancy,
  });

  factory RoomData.fromJson(Map<String, dynamic> json) {
    final hvacRaw = json['hvac'];
    HvacDetail? hvacDetail;
    String hvacState = 'Off';
    if (hvacRaw is String) {
      hvacState = hvacRaw;
    } else if (hvacRaw is Map<String, dynamic>) {
      hvacDetail = HvacDetail.fromJson(hvacRaw);
      hvacState = hvacDetail.state.label;
    } else if (hvacRaw is Map) {
      final map = Map<String, dynamic>.from(hvacRaw);
      hvacDetail = HvacDetail.fromJson(map);
      hvacState = hvacDetail.state.label;
    }

    final explicitHvacDetail = json['hvacDetail'];
    if (explicitHvacDetail is Map<String, dynamic>) {
      hvacDetail = HvacDetail.fromJson(explicitHvacDetail);
      hvacState = hvacDetail.state.label;
    } else if (explicitHvacDetail is Map) {
      hvacDetail = HvacDetail.fromJson(
        Map<String, dynamic>.from(explicitHvacDetail),
      );
      hvacState = hvacDetail.state.label;
    }

    final lightingRaw = json['lightingOn'];
    final lightingOn = lightingRaw is bool
        ? lightingRaw
        : ((json['lighting'] as String?)?.toLowerCase() == 'on');
    final dnd = DndStatus.fromString(json['dnd'] as String? ?? 'Off');
    final mur = MurStatus.fromString(json['mur'] as String? ?? 'Finished');
    final laundry = LaundryStatus.fromString(
      json['laundry'] as String? ?? 'Finished',
    );
    final occupancy = _parseOccupancy(json['occupancy']);
    final status = occupancy == null
        ? RoomStatus.fromString(json['status'] as String? ?? 'Unrented Vacant')
        : _statusFromOccupancy(occupancy, mur);

    return RoomData(
      number: json['number'] as String? ?? '',
      status: status,
      hasAlarm: json['hasAlarm'] as bool? ?? false,
      lightingOn: lightingOn,
      hvac: HvacStatus.fromString(hvacState),
      hvacDetail: hvacDetail,
      dnd: dnd,
      mur: mur,
      laundry: laundry,
      murDelayedMinutes: json['murDelayedMinutes'] as int?,
      dataSource:
          ((json['_meta'] as Map?)?['source'] as String?)?.trim().isNotEmpty ==
              true
          ? ((json['_meta'] as Map)['source'] as String).trim()
          : 'live',
      stale: ((json['_meta'] as Map?)?['stale'] as bool?) ?? false,
      occupancy: occupancy,
    );
  }

  RoomData copyWith({
    RoomStatus? status,
    bool? hasAlarm,
    bool? lightingOn,
    HvacStatus? hvac,
    HvacDetail? hvacDetail,
    DndStatus? dnd,
    MurStatus? mur,
    LaundryStatus? laundry,
    int? murDelayedMinutes,
    String? dataSource,
    bool? stale,
    RoomOccupancy? occupancy,
  }) {
    return RoomData(
      number: number,
      status: status ?? this.status,
      hasAlarm: hasAlarm ?? this.hasAlarm,
      lightingOn: lightingOn ?? this.lightingOn,
      hvac: hvac ?? this.hvac,
      hvacDetail: hvacDetail ?? this.hvacDetail,
      dnd: dnd ?? this.dnd,
      mur: mur ?? this.mur,
      laundry: laundry ?? this.laundry,
      murDelayedMinutes: murDelayedMinutes ?? this.murDelayedMinutes,
      dataSource: dataSource ?? this.dataSource,
      stale: stale ?? this.stale,
      occupancy: occupancy ?? this.occupancy,
    );
  }
}

RoomOccupancy? _parseOccupancy(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return RoomOccupancy.fromJson(raw);
  }
  if (raw is Map) {
    return RoomOccupancy.fromJson(Map<String, dynamic>.from(raw));
  }
  return null;
}

RoomStatus _statusFromOccupancy(RoomOccupancy occupancy, MurStatus mur) {
  final housekeeping = mur == MurStatus.started;
  if (housekeeping) {
    return occupancy.rented ? RoomStatus.rentedHK : RoomStatus.unrentedHK;
  }
  if (occupancy.occupied) {
    return RoomStatus.rentedOccupied;
  }
  return occupancy.rented ? RoomStatus.rentedVacant : RoomStatus.unrentedVacant;
}
