import 'lighting_device.dart';

class ServiceIconConfig {
  final String serviceType;
  final double x;
  final double y;

  const ServiceIconConfig({
    required this.serviceType,
    required this.x,
    required this.y,
  });

  factory ServiceIconConfig.fromJson(Map<String, dynamic> json) {
    return ServiceIconConfig(
      serviceType: (json['serviceType'] as String? ?? '').trim().toLowerCase(),
      x: _toDouble(json['x']) ?? 0,
      y: _toDouble(json['y']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'serviceType': serviceType,
        'x': x,
        'y': y,
      };

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class CoordinatesPayload {
  final Map<String, dynamic> zones;
  final List<LightingDeviceSummary> lightingDevices;
  final List<ServiceIconConfig> serviceIcons;

  const CoordinatesPayload({
    required this.zones,
    required this.lightingDevices,
    required this.serviceIcons,
  });

  factory CoordinatesPayload.fromJson(Map<String, dynamic> json) {
    return CoordinatesPayload(
      zones: (json['zones'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      lightingDevices: (json['lightingDevices'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(LightingDeviceSummary.fromJson)
          .toList(),
      serviceIcons: (json['serviceIcons'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ServiceIconConfig.fromJson)
          .where((icon) => icon.serviceType.isNotEmpty)
          .toList(),
    );
  }
}
