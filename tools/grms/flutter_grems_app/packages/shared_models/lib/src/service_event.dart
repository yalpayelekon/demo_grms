import 'package:json_annotation/json_annotation.dart';

part 'service_event.g.dart';

@JsonEnum(alwaysCreate: true)
enum ServiceType {
  @JsonValue('DND')
  dnd,
  @JsonValue('MUR')
  mur,
  @JsonValue('Laundry')
  laundry,
}

@JsonEnum(alwaysCreate: true)
enum EventType {
  @JsonValue('REQUESTED')
  requested,
  @JsonValue('CANCELED')
  canceled,
  @JsonValue('STARTED')
  started,
  @JsonValue('FINISHED')
  finished,
  @JsonValue('ACTIVATED')
  activated,
  @JsonValue('DEACTIVATED')
  deactivated,
}

@JsonSerializable()
class ServiceEvent {
  ServiceEvent({
    required this.serviceType,
    required this.eventType,
    required this.timestamp,
    required this.roomNumber,
    this.formattedTimestamp,
  });

  factory ServiceEvent.fromJson(Map<String, dynamic> json) =>
      _$ServiceEventFromJson(json);

  final ServiceType serviceType;
  final EventType eventType;
  final int timestamp;
  final String roomNumber;
  final String? formattedTimestamp;

  Map<String, dynamic> toJson() => _$ServiceEventToJson(this);
}
