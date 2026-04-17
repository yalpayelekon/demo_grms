import 'package:flutter/foundation.dart';

@immutable
class ZoneButton {
  final String uiDisplayName;
  final String buttonName;
  final double xCoordinate;
  final double yCoordinate;
  final bool active;

  const ZoneButton({
    required this.uiDisplayName,
    required this.buttonName,
    required this.xCoordinate,
    required this.yCoordinate,
    required this.active,
  });

  factory ZoneButton.fromJson(Map<String, dynamic> json) {
    return ZoneButton(
      uiDisplayName: json['ui_display_name'] as String,
      buttonName: json['button_name'] as String,
      xCoordinate: (json['x_coordinate'] as num).toDouble(),
      yCoordinate: (json['y_coordinate'] as num).toDouble(),
      active: json['active'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ui_display_name': uiDisplayName,
      'button_name': buttonName,
      'x_coordinate': xCoordinate,
      'y_coordinate': yCoordinate,
      'active': active,
    };
  }

  ZoneButton copyWith({
    String? uiDisplayName,
    String? buttonName,
    double? xCoordinate,
    double? yCoordinate,
    bool? active,
  }) {
    return ZoneButton(
      uiDisplayName: uiDisplayName ?? this.uiDisplayName,
      buttonName: buttonName ?? this.buttonName,
      xCoordinate: xCoordinate ?? this.xCoordinate,
      yCoordinate: yCoordinate ?? this.yCoordinate,
      active: active ?? this.active,
    );
  }
}

@immutable
class ZonePoint {
  final double x;
  final double y;

  const ZonePoint({required this.x, required this.y});

  factory ZonePoint.fromJson(Map<String, dynamic> json) {
    return ZonePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

@immutable
class PolygonData {
  final List<ZonePoint> points;
  final String fill;

  const PolygonData({required this.points, required this.fill});

  factory PolygonData.fromJson(Map<String, dynamic> json) {
    return PolygonData(
      points: (json['points'] as List<dynamic>)
          .map((p) => ZonePoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      fill: json['fill'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'points': points.map((p) => p.toJson()).toList(), 'fill': fill};
  }
}

@immutable
class ZonesData {
  final int schemaVersion;
  final List<ZoneButton> homePageBlockButtons;
  final List<PolygonData> polyPointsData;
  final Map<String, Map<String, List<String>>> categoryNamesBlockFloorMap;
  final Map<String, Map<String, ZonePoint>> floorButtonPositions;
  final Map<String, Map<String, Map<String, ZonePoint>>> roomButtonPositions;

  const ZonesData({
    this.schemaVersion = 2,
    required this.homePageBlockButtons,
    required this.polyPointsData,
    required this.categoryNamesBlockFloorMap,
    this.floorButtonPositions = const {},
    this.roomButtonPositions = const {},
  });

  factory ZonesData.fromJson(Map<String, dynamic> json) {
    final parsedFloorMap = _parseCategoryNamesBlockFloorMap(
      json['categoryNamesBlockFloorMap'],
    );

    return ZonesData(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 2,
      homePageBlockButtons:
          (json['homePageBlockButtons'] as List<dynamic>?)
              ?.map((b) => ZoneButton.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      polyPointsData:
          (json['polyPointsData'] as List<dynamic>?)
              ?.map((p) => PolygonData.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      categoryNamesBlockFloorMap: parsedFloorMap,
      floorButtonPositions: _parseFloorButtonPositions(
        json['floorButtonPositions'],
      ),
      roomButtonPositions: _parseRoomButtonPositions(
        json['roomButtonPositions'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'homePageBlockButtons': homePageBlockButtons
          .map((b) => b.toJson())
          .toList(),
      'polyPointsData': polyPointsData.map((p) => p.toJson()).toList(),
      'categoryNamesBlockFloorMap': categoryNamesBlockFloorMap,
      'floorButtonPositions': floorButtonPositions.map(
        (zone, floors) => MapEntry(
          zone,
          floors.map((floor, point) => MapEntry(floor, point.toJson())),
        ),
      ),
      'roomButtonPositions': roomButtonPositions.map(
        (zone, floors) => MapEntry(
          zone,
          floors.map(
            (floor, rooms) => MapEntry(
              floor,
              rooms.map((room, point) => MapEntry(room, point.toJson())),
            ),
          ),
        ),
      ),
    };
  }

  ZonesData copyWith({
    int? schemaVersion,
    List<ZoneButton>? homePageBlockButtons,
    List<PolygonData>? polyPointsData,
    Map<String, Map<String, List<String>>>? categoryNamesBlockFloorMap,
    Map<String, Map<String, ZonePoint>>? floorButtonPositions,
    Map<String, Map<String, Map<String, ZonePoint>>>? roomButtonPositions,
  }) {
    return ZonesData(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      homePageBlockButtons: homePageBlockButtons ?? this.homePageBlockButtons,
      polyPointsData: polyPointsData ?? this.polyPointsData,
      categoryNamesBlockFloorMap:
          categoryNamesBlockFloorMap ?? this.categoryNamesBlockFloorMap,
      floorButtonPositions: floorButtonPositions ?? this.floorButtonPositions,
      roomButtonPositions: roomButtonPositions ?? this.roomButtonPositions,
    );
  }
}

Map<String, Map<String, ZonePoint>> _parseFloorButtonPositions(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    return {};
  }

  final parsed = <String, Map<String, ZonePoint>>{};
  raw.forEach((zone, floorsValue) {
    if (floorsValue is! Map<String, dynamic>) {
      return;
    }
    final floorMap = <String, ZonePoint>{};
    floorsValue.forEach((floor, pointValue) {
      if (pointValue is Map<String, dynamic>) {
        floorMap[floor] = ZonePoint.fromJson(pointValue);
      }
    });
    if (floorMap.isNotEmpty) {
      parsed[zone] = floorMap;
    }
  });

  return parsed;
}

Map<String, Map<String, Map<String, ZonePoint>>> _parseRoomButtonPositions(
  dynamic raw,
) {
  if (raw is! Map<String, dynamic>) {
    return {};
  }

  final parsed = <String, Map<String, Map<String, ZonePoint>>>{};
  raw.forEach((zone, floorsValue) {
    if (floorsValue is! Map<String, dynamic>) {
      return;
    }
    final floorMap = <String, Map<String, ZonePoint>>{};
    floorsValue.forEach((floor, roomsValue) {
      if (roomsValue is! Map<String, dynamic>) {
        return;
      }
      final roomMap = <String, ZonePoint>{};
      roomsValue.forEach((room, pointValue) {
        if (pointValue is Map<String, dynamic>) {
          roomMap[room] = ZonePoint.fromJson(pointValue);
        }
      });
      if (roomMap.isNotEmpty) {
        floorMap[floor] = roomMap;
      }
    });
    if (floorMap.isNotEmpty) {
      parsed[zone] = floorMap;
    }
  });

  return parsed;
}

Map<String, Map<String, List<String>>> _parseCategoryNamesBlockFloorMap(
  dynamic raw,
) {
  if (raw is! Map<String, dynamic>) {
    return {};
  }

  final canonical = <String, Map<String, List<String>>>{};
  var usedLegacyConversion = false;

  raw.forEach((zone, floorsValue) {
    if (floorsValue is Map<String, dynamic>) {
      final floors = <String, List<String>>{};
      floorsValue.forEach((floorName, roomsValue) {
        if (roomsValue is List<dynamic>) {
          floors[floorName] = roomsValue
              .map((room) => room.toString())
              .toList();
        }
      });
      canonical[zone] = floors;
      return;
    }

    if (floorsValue is List<dynamic>) {
      usedLegacyConversion = true;
      final floors = <String, List<String>>{};
      for (final floorName in floorsValue) {
        floors[floorName.toString()] = const <String>[];
      }
      canonical[zone] = floors;
    }
  });

  if (usedLegacyConversion) {
    debugPrint(
      'ZonesData.fromJson: legacy categoryNamesBlockFloorMap detected; '
      'converted zone->floors list into empty floor->rooms map.',
    );
  }

  return canonical;
}
