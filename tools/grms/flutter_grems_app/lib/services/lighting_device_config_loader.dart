import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/lighting_device.dart';
import '../providers/lighting_devices_provider.dart';

class LightingDeviceConfigLoader {
  const LightingDeviceConfigLoader({List<String>? assetPaths})
    : _assetPaths = assetPaths ?? _defaultAssetPaths;

  static const List<String> _defaultAssetPaths = <String>[
    'assets/json/lighting-devices.json',
    'json/lighting-devices.json',
  ];
  final List<String> _assetPaths;

  Future<List<LightingDeviceConfig>> loadFromAsset() async {
    Object? lastError;
    for (final path in _assetPaths) {
      try {
        final raw = await rootBundle.loadString(path, cache: false);
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          return const <LightingDeviceConfig>[];
        }

        final configs = <LightingDeviceConfig>[];
        for (final item in decoded) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final address = _toInt(item['address']);
          final x = _toDouble(item['x']);
          final y = _toDouble(item['y']);
          final name = item['name']?.toString() ?? '';
          final rawType = (item['type']?.toString() ?? '').trim().toLowerCase();
          if (address == null || x == null || y == null || name.isEmpty) {
            continue;
          }
          configs.add(
            LightingDeviceConfig(
              address: address,
              name: name,
              x: x,
              y: y,
              type: rawType == 'dali'
                  ? LightingDeviceType.dali
                  : LightingDeviceType.onboard,
            ),
          );
        }
        return configs;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      if (lastError is FlutterError) {
        throw lastError;
      }
      throw FlutterError(lastError.toString());
    }
    return const <LightingDeviceConfig>[];
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is double) {
      return value.toInt();
    }
    return null;
  }

  double? _toDouble(dynamic value) {
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
