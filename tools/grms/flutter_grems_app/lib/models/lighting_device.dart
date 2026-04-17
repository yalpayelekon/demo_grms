enum LightingDeviceType { onboard, dali }

class LightingDeviceSummary {
  final int address;
  final String name;
  final double actualLevel;
  final double? targetLevel;
  final double? powerW;
  final String? feature;
  final bool alarm;
  final int? daliSituation;
  final LightingDeviceType type;
  final double? x;
  final double? y;

  LightingDeviceSummary({
    required this.address,
    required this.name,
    required this.actualLevel,
    this.targetLevel,
    this.powerW,
    this.feature,
    this.alarm = false,
    this.daliSituation,
    required this.type,
    this.x,
    this.y,
  });

  factory LightingDeviceSummary.fromJson(Map<String, dynamic> json) {
    return LightingDeviceSummary(
      address: json['address'] as int,
      name: json['name'] as String? ?? '',
      actualLevel: _toDouble(json['actualLevel']) ?? 0.0,
      targetLevel: _toDouble(json['targetLevel']),
      powerW: _toDouble(json['powerW']),
      feature: json['feature'] as String?,
      alarm: json['alarm'] as bool? ?? false,
      daliSituation: json['daliSituation'] as int?,
      type: json['type'] == 'dali'
          ? LightingDeviceType.dali
          : LightingDeviceType.onboard,
      x: _toDouble(json['x']),
      y: _toDouble(json['y']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class LightingDevicesResponse {
  final List<LightingDeviceSummary> onboardOutputs;
  final List<LightingDeviceSummary> daliOutputs;

  LightingDevicesResponse({
    required this.onboardOutputs,
    required this.daliOutputs,
  });

  factory LightingDevicesResponse.fromJson(Map<String, dynamic> json) {
    return LightingDevicesResponse(
      onboardOutputs:
          (json['onboardOutputs'] as List<dynamic>?)
              ?.map(
                (e) =>
                    LightingDeviceSummary.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      daliOutputs:
          (json['daliOutputs'] as List<dynamic>?)
              ?.map(
                (e) =>
                    LightingDeviceSummary.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}
