import 'package:flutter/foundation.dart';

enum AlarmStatus {
  waitingAck('Waiting Ack'),
  acknowledged('Acknowledged'),
  waitingRepair('Waiting Repair/Cancel'),
  fixed('Fixed');

  final String label;
  const AlarmStatus(this.label);

  static AlarmStatus fromString(String value) {
    return AlarmStatus.values.firstWhere(
      (e) => e.label == value,
      orElse: () => AlarmStatus.waitingAck,
    );
  }
}

enum AlarmAcknowledgement {
  waitingAck('Waiting Ack'),
  acknowledged('Acknowledged');

  final String label;
  const AlarmAcknowledgement(this.label);

  static AlarmAcknowledgement fromString(String value) {
    return AlarmAcknowledgement.values.firstWhere(
      (e) => e.label == value,
      orElse: () => AlarmAcknowledgement.waitingAck,
    );
  }
}

@immutable
class AlarmData {
  final String id;
  final String room;
  final String incidentTime;
  final String category;
  final AlarmAcknowledgement acknowledgement;
  final String acknowledgementTime;
  final AlarmStatus status;
  final String details;
  final String? ipAddress;

  const AlarmData({
    required this.id,
    required this.room,
    required this.incidentTime,
    required this.category,
    required this.acknowledgement,
    required this.acknowledgementTime,
    required this.status,
    required this.details,
    this.ipAddress,
  });

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      id: json['id'] as String,
      room: json['room'] as String,
      incidentTime: json['incidentTime'] as String,
      category: json['category'] as String,
      acknowledgement: AlarmAcknowledgement.fromString(json['acknowledgement'] as String),
      acknowledgementTime: json['acknowledgementTime'] as String? ?? '',
      status: AlarmStatus.fromString(json['status'] as String),
      details: json['details'] as String? ?? '',
      ipAddress: json['ipAddress'] as String?,
    );
  }

  AlarmData copyWith({
    String? incidentTime,
    AlarmAcknowledgement? acknowledgement,
    String? acknowledgementTime,
    AlarmStatus? status,
    String? details,
    String? ipAddress,
  }) {
    return AlarmData(
      id: id,
      room: room,
      incidentTime: incidentTime ?? this.incidentTime,
      category: category,
      acknowledgement: acknowledgement ?? this.acknowledgement,
      acknowledgementTime: acknowledgementTime ?? this.acknowledgementTime,
      status: status ?? this.status,
      details: details ?? this.details,
      ipAddress: ipAddress ?? this.ipAddress,
    );
  }
}
