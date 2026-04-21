import 'lighting_device.dart';
import 'room_models.dart';

class RoomRuntimeSnapshot {
  const RoomRuntimeSnapshot({
    required this.roomData,
    required this.lighting,
    required this.serviceEvents,
    required this.source,
    required this.stale,
    required this.receivedAt,
    this.rawHasAlarm = false,
    this.hasDoorAlarm = false,
    this.hasDaliLineShortCircuit = false,
  });

  final RoomData roomData;
  final LightingDevicesResponse lighting;
  final List<Map<String, dynamic>> serviceEvents;
  final String source;
  final bool stale;
  final DateTime receivedAt;
  final bool rawHasAlarm;
  final bool hasDoorAlarm;
  final bool hasDaliLineShortCircuit;

  factory RoomRuntimeSnapshot.fromSnapshot(
    Map<String, dynamic> snapshot, {
    required DateTime receivedAt,
  }) {
    final meta = snapshot['_meta'];
    final source = meta is Map && meta['source'] is String
        ? (meta['source'] as String).trim()
        : 'live';
    final stale = meta is Map && meta['stale'] is bool
        ? meta['stale'] as bool
        : false;

    return RoomRuntimeSnapshot(
      roomData: RoomData.fromJson(snapshot),
      lighting: _lightingResponseFromSnapshot(snapshot),
      serviceEvents: _serviceEventsFromSnapshot(snapshot),
      source: source.isEmpty ? 'live' : source,
      stale: stale,
      receivedAt: receivedAt,
      rawHasAlarm: snapshot['hasAlarm'] as bool? ?? false,
      hasDoorAlarm: snapshot['hasDoorAlarm'] as bool? ?? false,
      hasDaliLineShortCircuit:
          snapshot['hasDaliLineShortCircuit'] as bool? ?? false,
    );
  }

  static LightingDevicesResponse _lightingResponseFromSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final rawDevices = snapshot['lightingDevices'];
    if (rawDevices is! List) {
      return LightingDevicesResponse(
        onboardOutputs: const [],
        daliOutputs: const [],
      );
    }

    final onboard = <LightingDeviceSummary>[];
    final dali = <LightingDeviceSummary>[];

    for (final item in rawDevices) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final address = _toInt(map['address']);
      if (address == null) {
        continue;
      }

      final typeRaw = (map['type'] as String?)?.toLowerCase();
      final onboardRaw = map['onboard'] == true;
      final type = typeRaw == 'dali'
          ? LightingDeviceType.dali
          : (onboardRaw ? LightingDeviceType.onboard : LightingDeviceType.dali);

      final summary = LightingDeviceSummary(
        address: address,
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : 'Device $address',
        actualLevel: _toDouble(map['actualLevel']) ?? 0,
        targetLevel: _toDouble(map['targetLevel']),
        powerW: _toDouble(map['powerW']),
        feature: map['feature'] as String?,
        alarm: map['alarm'] as bool? ?? false,
        daliSituation: _toInt(map['daliSituation']),
        type: type,
        x: _toDouble(map['x']),
        y: _toDouble(map['y']),
      );

      if (type == LightingDeviceType.onboard) {
        onboard.add(summary);
      } else {
        dali.add(summary);
      }
    }

    return LightingDevicesResponse(onboardOutputs: onboard, daliOutputs: dali);
  }

  static List<Map<String, dynamic>> _serviceEventsFromSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final rawEvents = snapshot['serviceEvents'];
    if (rawEvents is! List) {
      return const [];
    }

    return rawEvents
        .whereType<Map>()
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
