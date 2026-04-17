class ZonePoint {
  const ZonePoint({required this.x, required this.y});

  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory ZonePoint.fromJson(Map<String, dynamic> json) => ZonePoint(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );
}

class PolygonData {
  const PolygonData({required this.points, required this.fill});

  final List<ZonePoint> points;
  final String fill;

  Map<String, dynamic> toJson() => {
        'points': points.map((e) => e.toJson()).toList(),
        'fill': fill,
      };

  factory PolygonData.fromJson(Map<String, dynamic> json) => PolygonData(
        points: ((json['points'] as List?) ?? const [])
            .map((e) => ZonePoint.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        fill: json['fill'] as String? ?? '#44ffffff',
      );
}

class ZoneButton {
  const ZoneButton({
    required this.uiDisplayName,
    required this.buttonName,
    required this.xCoordinate,
    required this.yCoordinate,
    required this.active,
  });

  final String uiDisplayName;
  final String buttonName;
  final double xCoordinate;
  final double yCoordinate;
  final bool active;

  ZoneButton copyWith({
    String? uiDisplayName,
    String? buttonName,
    double? xCoordinate,
    double? yCoordinate,
    bool? active,
  }) =>
      ZoneButton(
        uiDisplayName: uiDisplayName ?? this.uiDisplayName,
        buttonName: buttonName ?? this.buttonName,
        xCoordinate: xCoordinate ?? this.xCoordinate,
        yCoordinate: yCoordinate ?? this.yCoordinate,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'ui_display_name': uiDisplayName,
        'button_name': buttonName,
        'x_coordinate': xCoordinate,
        'y_coordinate': yCoordinate,
        'active': active,
      };

  factory ZoneButton.fromJson(Map<String, dynamic> json) => ZoneButton(
        uiDisplayName: json['ui_display_name'] as String? ?? '',
        buttonName: json['button_name'] as String? ?? '',
        xCoordinate: (json['x_coordinate'] as num?)?.toDouble() ?? 0,
        yCoordinate: (json['y_coordinate'] as num?)?.toDouble() ?? 0,
        active: json['active'] as bool? ?? false,
      );
}

class ZonesData {
  const ZonesData({
    required this.homePageBlockButtons,
    required this.polyPointsData,
    required this.categoryNamesBlockFloorMap,
  });

  final List<ZoneButton> homePageBlockButtons;
  final List<PolygonData> polyPointsData;
  final Map<String, List<String>> categoryNamesBlockFloorMap;

  ZonesData copyWith({
    List<ZoneButton>? homePageBlockButtons,
    List<PolygonData>? polyPointsData,
    Map<String, List<String>>? categoryNamesBlockFloorMap,
  }) =>
      ZonesData(
        homePageBlockButtons: homePageBlockButtons ?? this.homePageBlockButtons,
        polyPointsData: polyPointsData ?? this.polyPointsData,
        categoryNamesBlockFloorMap: categoryNamesBlockFloorMap ?? this.categoryNamesBlockFloorMap,
      );

  Map<String, dynamic> toJson() => {
        'homePageBlockButtons': homePageBlockButtons.map((e) => e.toJson()).toList(),
        'polyPointsData': polyPointsData.map((e) => e.toJson()).toList(),
        'categoryNamesBlockFloorMap': categoryNamesBlockFloorMap,
      };

  factory ZonesData.fromJson(Map<String, dynamic> json) {
    final mapRaw = (json['categoryNamesBlockFloorMap'] as Map?)?.cast<String, dynamic>() ?? {};
    final map = <String, List<String>>{};
    for (final entry in mapRaw.entries) {
      map[entry.key] = ((entry.value as List?) ?? const []).map((e) => e.toString()).toList();
    }

    return ZonesData(
      homePageBlockButtons: ((json['homePageBlockButtons'] as List?) ?? const [])
          .map((e) => ZoneButton.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      polyPointsData: ((json['polyPointsData'] as List?) ?? const [])
          .map((e) => PolygonData.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      categoryNamesBlockFloorMap: map,
    );
  }
}
