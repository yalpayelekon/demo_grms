import 'package:json_annotation/json_annotation.dart';

part 'output_device_data.g.dart';

@JsonSerializable()
class OutputDeviceData {
  OutputDeviceData({
    required this.address,
    required this.name,
    required this.variety,
    required this.type,
    required this.actualLevel,
    required this.targetLevel,
    required this.status,
    required this.onboard,
  });

  factory OutputDeviceData.fromJson(Map<String, dynamic> json) =>
      _$OutputDeviceDataFromJson(json);

  @JsonKey(defaultValue: 0)
  final int address;
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: '')
  final String variety;
  @JsonKey(defaultValue: '')
  final String type;
  @JsonKey(defaultValue: 0)
  final int actualLevel;
  @JsonKey(defaultValue: 0)
  final int targetLevel;
  @JsonKey(defaultValue: '')
  final String status;
  @JsonKey(defaultValue: false)
  final bool onboard;

  Map<String, dynamic> toJson() => _$OutputDeviceDataToJson(this);
}
