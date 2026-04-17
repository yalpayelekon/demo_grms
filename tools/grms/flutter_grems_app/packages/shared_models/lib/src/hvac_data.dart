import 'package:json_annotation/json_annotation.dart';

part 'hvac_data.g.dart';

@JsonSerializable()
class HvacData {
  HvacData({
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

  factory HvacData.fromJson(Map<String, dynamic> json) =>
      _$HvacDataFromJson(json);

  static HvacData? fromDynamic(Object? json) {
    if (json == null) {
      return null;
    }
    if (json is String) {
      return HvacData(state: json);
    }
    if (json is Map<String, dynamic>) {
      return HvacData.fromJson(json);
    }
    return null;
  }

  static Object? toJsonDynamic(HvacData? hvac) => hvac?.toJson();

  final String state;
  final int? onOff;
  @JsonKey(fromJson: _toDouble)
  final double? roomTemperature;
  @JsonKey(fromJson: _toDouble)
  final double? setPoint;
  final int? mode;
  final int? fanMode;
  @JsonKey(fromJson: _toDouble)
  final double? comfortTemperature;
  @JsonKey(fromJson: _toDouble)
  final double? lowerSetpoint;
  @JsonKey(fromJson: _toDouble)
  final double? upperSetpoint;
  final int? keylockFunction;
  final int? occupancyInput;
  final int? runningStatus;
  final int? comError;
  final int? fidelio;

  Map<String, dynamic> toJson() => _$HvacDataToJson(this);

  static double? _toDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
