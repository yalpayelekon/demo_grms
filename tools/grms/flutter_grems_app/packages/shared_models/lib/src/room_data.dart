import 'package:json_annotation/json_annotation.dart';

import 'hvac_data.dart';
import 'output_device_data.dart';
import 'service_event.dart';

part 'room_data.g.dart';

@JsonSerializable(explicitToJson: true)
class RoomData {
  RoomData({
    this.hvac,
    required this.lighting,
    required this.dnd,
    required this.mur,
    required this.laundry,
    required this.status,
    required this.hasAlarm,
    required this.lightingDevices,
    required this.serviceEvents,
  });

  factory RoomData.fromJson(Map<String, dynamic> json) => _$RoomDataFromJson(json);

  @JsonKey(fromJson: HvacData.fromDynamic, toJson: HvacData.toJsonDynamic)
  final HvacData? hvac;
  @JsonKey(defaultValue: '')
  final String lighting;
  @JsonKey(defaultValue: '')
  final String dnd;
  @JsonKey(defaultValue: '')
  final String mur;
  @JsonKey(defaultValue: '')
  final String laundry;
  @JsonKey(defaultValue: '')
  final String status;
  @JsonKey(defaultValue: false)
  final bool hasAlarm;
  @JsonKey(defaultValue: [])
  final List<OutputDeviceData> lightingDevices;
  @JsonKey(defaultValue: [])
  final List<ServiceEvent> serviceEvents;

  Map<String, dynamic> toJson() => _$RoomDataToJson(this);
}
