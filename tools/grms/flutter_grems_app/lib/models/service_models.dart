import 'package:flutter/foundation.dart';

enum ServiceType { dnd, mur, laundry }

extension ServiceTypeExtension on ServiceType {
  String get label {
    switch (this) {
      case ServiceType.dnd: return 'DND';
      case ServiceType.mur: return 'MUR';
      case ServiceType.laundry: return 'Laundry';
    }
  }

  static ServiceType fromString(String val) {
    if (val.toUpperCase() == 'DND') return ServiceType.dnd;
    if (val.toUpperCase() == 'MUR') return ServiceType.mur;
    return ServiceType.laundry;
  }
}

enum ServiceAcknowledgement { acknowledged, waitingAck, none }

extension ServiceAcknowledgementExtension on ServiceAcknowledgement {
  String get label {
    switch (this) {
      case ServiceAcknowledgement.acknowledged: return 'Acknowledged';
      case ServiceAcknowledgement.waitingAck: return 'Waiting Ack';
      case ServiceAcknowledgement.none: return 'None';
    }
  }
}

@immutable
class RoomServiceEntry {
  final String id;
  final String roomNumber;
  final int floor;
  final ServiceType serviceType;
  final String serviceState;
  final String activationTime;
  final int eventTimestamp;
  final String? startTime;
  final String? endTime;
  final int delayedMinutes;
  final int? finishedMinutes;
  final ServiceAcknowledgement acknowledgement;
  final String? acknowledgementTime;
  final String? note;

  const RoomServiceEntry({
    required this.id,
    required this.roomNumber,
    required this.floor,
    required this.serviceType,
    required this.serviceState,
    required this.activationTime,
    required this.eventTimestamp,
    this.startTime,
    this.endTime,
    required this.delayedMinutes,
    this.finishedMinutes,
    required this.acknowledgement,
    this.acknowledgementTime,
    this.note,
  });

  RoomServiceEntry copyWith({
    String? serviceState,
    String? startTime,
    String? endTime,
    int? delayedMinutes,
    int? finishedMinutes,
    ServiceAcknowledgement? acknowledgement,
    String? acknowledgementTime,
    String? note,
  }) {
    return RoomServiceEntry(
      id: id,
      roomNumber: roomNumber,
      floor: floor,
      serviceType: serviceType,
      serviceState: serviceState ?? this.serviceState,
      activationTime: activationTime,
      eventTimestamp: eventTimestamp,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      delayedMinutes: delayedMinutes ?? this.delayedMinutes,
      finishedMinutes: finishedMinutes ?? this.finishedMinutes,
      acknowledgement: acknowledgement ?? this.acknowledgement,
      acknowledgementTime: acknowledgementTime ?? this.acknowledgementTime,
      note: note ?? this.note,
    );
  }
}
