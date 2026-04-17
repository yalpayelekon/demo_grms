import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_result.dart';
import '../models/zones_models.dart';
import 'state_merge_policy.dart';
import 'api_providers.dart';

@immutable
class ZoneOccupancyState {
  const ZoneOccupancyState({
    required this.zoneId,
    required this.isOccupied,
    required this.metadata,
  });

  final String zoneId;
  final bool isOccupied;
  final MergeMetadata metadata;

  ZoneOccupancyState copyWith({bool? isOccupied, MergeMetadata? metadata}) {
    return ZoneOccupancyState(
      zoneId: zoneId,
      isOccupied: isOccupied ?? this.isOccupied,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ZonesState {
  final ZonesData zonesData;
  final Map<String, ZoneOccupancyState> occupancyById;

  ZonesState({required this.zonesData, this.occupancyById = const {}});

  ZonesState copyWith({
    ZonesData? zonesData,
    Map<String, ZoneOccupancyState>? occupancyById,
  }) {
    return ZonesState(
      zonesData: zonesData ?? this.zonesData,
      occupancyById: occupancyById ?? this.occupancyById,
    );
  }
}

class ZonesNotifier extends Notifier<ZonesState> {
  static const Set<String> _removedZoneIds = {'Block C', 'Villas'};
  static const List<String> _defaultDemoRooms = [
    '1001',
    '1002',
    '1003',
    '1004',
    '1005',
    '1006',
    '1007',
    '1008',
    '1009',
    '1010',
    '1011',
    '1012',
    '1013',
    '1014',
    '1015',
    '1016',
    '1017',
    '1018',
    '1019',
    '1020',
    '1021',
    '1022',
    '1023',
    '1024',
    '1025',
    '1026',
    '1027',
    '1028',
    '1029',
    '1030',
    '1031',
    '1032',
    '1033',
    '1034',
    '1035',
    '1037',
    '1039',
  ];

  static const Map<String, List<String>> _defaultFloors = {
    'Floor 1': _defaultDemoRooms,
    'Floor 2': _defaultDemoRooms,
    'Floor 3': _defaultDemoRooms,
    'Floor 4': _defaultDemoRooms,
    'Ground': _defaultDemoRooms,
  };

  static const ZonesData _defaultZonesData = ZonesData(
    schemaVersion: 2,
    homePageBlockButtons: [
      ZoneButton(
        uiDisplayName: 'Block A',
        buttonName: 'Block A',
        xCoordinate: 430,
        yCoordinate: 560,
        active: true,
      ),
      ZoneButton(
        uiDisplayName: 'Block B',
        buttonName: 'Block B',
        xCoordinate: 1240,
        yCoordinate: 510,
        active: true,
      ),
    ],
    polyPointsData: [
      PolygonData(
        points: [
          ZonePoint(x: 260, y: 450),
          ZonePoint(x: 600, y: 450),
          ZonePoint(x: 670, y: 640),
          ZonePoint(x: 300, y: 700),
        ],
        fill: '#D64E4E88',
      ),
      PolygonData(
        points: [
          ZonePoint(x: 1100, y: 430),
          ZonePoint(x: 1450, y: 430),
          ZonePoint(x: 1520, y: 590),
          ZonePoint(x: 1140, y: 650),
        ],
        fill: '#4D64D688',
      ),
    ],
    categoryNamesBlockFloorMap: {
      'Block A': _defaultFloors,
      'Block B': _defaultFloors,
    },
  );

  final StateMergePolicy _mergePolicy = const StateMergePolicy();
  bool _isCoordinateEditInProgress = false;
  ZonesData _lastBackendZonesData = _defaultZonesData;

  @override
  ZonesState build() {
    _lastBackendZonesData = _defaultZonesData;
    unawaited(_loadMetadataFromAssets());
    return ZonesState(zonesData: _defaultZonesData);
  }

  void beginCoordinateEdit() => _isCoordinateEditInProgress = true;

  void endCoordinateEdit() => _isCoordinateEditInProgress = false;

  void applyCoordinatesPayload(Map<String, dynamic> zonesJson) {
    if (_isCoordinateEditInProgress) {
      if (kDebugMode) {
        debugPrint(
          'ZonesNotifier: backend coordinates ignored during active edit',
        );
      }
      return;
    }
    try {
      final parsed = _sanitizeZonesData(ZonesData.fromJson(zonesJson));
      final nextZonesData = mergeIncomingCoordinatesIntoCurrent(
        current: state.zonesData,
        incomingCoordinates: parsed,
      );
      state = state.copyWith(zonesData: nextZonesData);
      _lastBackendZonesData = nextZonesData;
      if (kDebugMode) {
        final totals = countZoneRooms(nextZonesData.categoryNamesBlockFloorMap);
        debugPrint(
          'ZonesNotifier: applied zones payload. '
          'source=coordinates_only_merge '
          'zoneMaps=${nextZonesData.categoryNamesBlockFloorMap.length} '
          'floors=${totals.$1} rooms=${totals.$2}',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('ZonesNotifier: invalid zones payload ignored: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // Mapping helpers for badge aggregation
  Map<String, String> get roomToZoneMap {
    final mapping = <String, String>{};
    for (final entry in state.zonesData.categoryNamesBlockFloorMap.entries) {
      final zoneId = entry.key;
      final floorMap = entry.value;
      for (final rooms in floorMap.values) {
        for (final roomNumber in rooms) {
          mapping[roomNumber] = zoneId;
        }
      }
    }
    return mapping;
  }

  String? findZoneForRoomLabel(String roomLabel) {
    final numericSegments = RegExp(
      r'\d+',
    ).allMatches(roomLabel).map((m) => m.group(0)!);
    final roomMap = roomToZoneMap;

    for (final segment in numericSegments) {
      if (roomMap.containsKey(segment)) {
        return roomMap[segment];
      }
    }

    final normalizedLabel = roomLabel.toLowerCase();
    for (final btn in state.zonesData.homePageBlockButtons) {
      final zoneId = btn.buttonName;
      final zoneLabel = btn.uiDisplayName.toLowerCase();

      final normalizedZone = zoneId.toLowerCase();
      if (normalizedZone.length == 1) {
        if (RegExp('\\b$normalizedZone(\\b|\\d)').hasMatch(normalizedLabel)) {
          return zoneId;
        }
      }

      if (normalizedLabel.contains(zoneLabel) ||
          normalizedLabel.contains(normalizedZone)) {
        return zoneId;
      }
    }

    return null;
  }

  // Layout Management
  void updateZoneLayout(int index, ZoneButton zone, {bool persist = true}) {
    final buttons = List<ZoneButton>.from(state.zonesData.homePageBlockButtons);
    if (index >= 0 && index < buttons.length) {
      buttons[index] = zone;
      final updatedData = state.zonesData.copyWith(
        homePageBlockButtons: buttons,
      );
      state = state.copyWith(zonesData: updatedData);

      if (persist) {
        unawaited(_persistZonesData(updatedData));
      }
    }
  }

  void updateFloorButtonPosition(
    String zoneId,
    String floorName,
    ZonePoint point, {
    bool persist = true,
  }) {
    final floorPositions = <String, Map<String, ZonePoint>>{};
    for (final zoneEntry in state.zonesData.floorButtonPositions.entries) {
      floorPositions[zoneEntry.key] = <String, ZonePoint>{
        ...zoneEntry.value,
      };
    }
    final zoneFloorPositions = floorPositions[zoneId] ?? <String, ZonePoint>{};
    zoneFloorPositions[floorName] = point;
    floorPositions[zoneId] = zoneFloorPositions;

    final updatedData = state.zonesData.copyWith(
      floorButtonPositions: floorPositions,
    );
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  void updateRoomButtonPosition(
    String zoneId,
    String floorName,
    String roomName,
    ZonePoint point, {
    bool persist = true,
  }) {
    final roomPositions = <String, Map<String, Map<String, ZonePoint>>>{};
    for (final zoneEntry in state.zonesData.roomButtonPositions.entries) {
      final floorMap = <String, Map<String, ZonePoint>>{};
      for (final floorEntry in zoneEntry.value.entries) {
        floorMap[floorEntry.key] = <String, ZonePoint>{
          ...floorEntry.value,
        };
      }
      roomPositions[zoneEntry.key] = floorMap;
    }

    final zoneRoomPositions =
        roomPositions[zoneId] ?? <String, Map<String, ZonePoint>>{};
    final floorRoomPositions =
        zoneRoomPositions[floorName] ?? <String, ZonePoint>{};
    floorRoomPositions[roomName] = point;
    zoneRoomPositions[floorName] = floorRoomPositions;
    roomPositions[zoneId] = zoneRoomPositions;

    final updatedData = state.zonesData.copyWith(
      roomButtonPositions: roomPositions,
    );
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  void updatePolygonPoint(
    int polygonIndex,
    int pointIndex,
    ZonePoint point, {
    bool persist = true,
  }) {
    final polygons = List<PolygonData>.from(state.zonesData.polyPointsData);
    if (polygonIndex < 0 || polygonIndex >= polygons.length) {
      return;
    }

    final polygon = polygons[polygonIndex];
    final points = List<ZonePoint>.from(polygon.points);
    if (pointIndex < 0 || pointIndex >= points.length) {
      return;
    }

    points[pointIndex] = point;
    polygons[polygonIndex] = PolygonData(points: points, fill: polygon.fill);
    final updatedData = state.zonesData.copyWith(polyPointsData: polygons);
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  void addZoneLayout(ZoneButton zone, {bool persist = true}) {
    final buttons = List<ZoneButton>.from(state.zonesData.homePageBlockButtons)
      ..add(zone);
    final updatedData = state.zonesData.copyWith(homePageBlockButtons: buttons);
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  void deleteZoneLayout(int index, {bool persist = true}) {
    final buttons = List<ZoneButton>.from(state.zonesData.homePageBlockButtons);
    if (index < 0 || index >= buttons.length) return;

    buttons.removeAt(index);
    final updatedData = state.zonesData.copyWith(homePageBlockButtons: buttons);
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  void resetZoneLayouts({bool persist = true}) {
    final updatedData = state.zonesData.copyWith(
      homePageBlockButtons: _defaultZonesData.homePageBlockButtons,
      polyPointsData: _defaultZonesData.polyPointsData,
    );
    state = state.copyWith(zonesData: updatedData);

    if (persist) {
      unawaited(_persistZonesData(updatedData));
    }
  }

  Future<void> _loadMetadataFromAssets() async {
    try {
      final zonesRaw = await rootBundle.loadString('assets/json/zones.json');
      final engineeringRaw = await rootBundle.loadString(
        'assets/json/engineering_tool_data.json',
      );
      final zonesJson = jsonDecode(zonesRaw) as Map<String, dynamic>;
      final engineeringJson =
          jsonDecode(engineeringRaw) as Map<String, dynamic>;
      final metadataJson = mergeZonesMetadataWithEngineeringData(
        zonesLayoutJson: zonesJson,
        engineeringJson: engineeringJson,
      );
      final metadata = ZonesData.fromJson(metadataJson);
      final sanitizedMetadata = _sanitizeZonesData(metadata);
      final mergedButtons = mergeMetadataButtonsIntoCurrent(
        currentButtons: state.zonesData.homePageBlockButtons,
        metadataButtons: sanitizedMetadata.homePageBlockButtons,
      );
      final merged = state.zonesData.copyWith(
        schemaVersion: sanitizedMetadata.schemaVersion,
        homePageBlockButtons: mergedButtons,
        polyPointsData: sanitizedMetadata.polyPointsData,
        categoryNamesBlockFloorMap: sanitizedMetadata.categoryNamesBlockFloorMap,
      );
      state = state.copyWith(zonesData: merged);
      _lastBackendZonesData = merged;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('ZonesNotifier: metadata asset load failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _persistZonesData(ZonesData updatedData) async {
    try {
      final result = await ref.read(coordinatesApiProvider).saveZones(
        updatedData.toJson(),
      );
      if (result is Failure<void>) {
        if (kDebugMode) {
          debugPrint(
            'ZonesNotifier: saveZones failed, reverting to backend snapshot: ${result.error.message}',
          );
        }
        state = state.copyWith(zonesData: _lastBackendZonesData);
        return;
      }
      _lastBackendZonesData = updatedData;
    } finally {
      _isCoordinateEditInProgress = false;
    }
  }

  // Occupancy Management
  void applyLocalOptimisticUpdate({
    required String zoneId,
    required bool isOccupied,
    int? version,
    DateTime? eventTimestamp,
  }) {
    _merge(
      ZoneOccupancyState(
        zoneId: zoneId,
        isOccupied: isOccupied,
        metadata: MergeMetadata(
          source: MergeSource.localOptimistic,
          observedAt: DateTime.now(),
          eventTimestamp: eventTimestamp,
          version: version,
        ),
      ),
    );
  }

  void applyWebsocketEvent({
    required String zoneId,
    required bool isOccupied,
    required DateTime observedAt,
    DateTime? eventTimestamp,
    int? version,
    bool isReplay = false,
  }) {
    _merge(
      ZoneOccupancyState(
        zoneId: zoneId,
        isOccupied: isOccupied,
        metadata: MergeMetadata(
          source: MergeSource.websocketEvent,
          observedAt: observedAt,
          eventTimestamp: eventTimestamp,
          version: version,
          isReplay: isReplay,
        ),
      ),
    );
  }

  void _merge(ZoneOccupancyState incoming) {
    final current = state.occupancyById[incoming.zoneId];
    final next = _mergePolicy.mergeEntity<ZoneOccupancyState>(
      current: current,
      incoming: incoming,
      metadataOf: (value) => value.metadata,
    );
    if (!identical(next, current)) {
      final updatedOccupancy = Map<String, ZoneOccupancyState>.from(
        state.occupancyById,
      );
      updatedOccupancy[incoming.zoneId] = next;
      state = state.copyWith(occupancyById: updatedOccupancy);
    }
  }

  ZonesData _sanitizeZonesData(ZonesData data) {
    final keptButtonsWithIndex = data.homePageBlockButtons
        .asMap()
        .entries
        .where((entry) => !_removedZoneIds.contains(entry.value.buttonName))
        .toList();
    final keptButtons = keptButtonsWithIndex.map((entry) => entry.value).toList();

    final hasOnePolygonPerButton =
        data.polyPointsData.length == data.homePageBlockButtons.length;
    final sanitizedPolygons = hasOnePolygonPerButton
        ? keptButtonsWithIndex
              .map((entry) => data.polyPointsData[entry.key])
              .toList()
        : data.polyPointsData;

    final sanitizedCategoryMap = <String, Map<String, List<String>>>{};
    for (final entry in data.categoryNamesBlockFloorMap.entries) {
      if (_removedZoneIds.contains(entry.key)) {
        continue;
      }
      sanitizedCategoryMap[entry.key] = entry.value;
    }

    final sanitizedFloorPositions = <String, Map<String, ZonePoint>>{};
    for (final entry in data.floorButtonPositions.entries) {
      if (_removedZoneIds.contains(entry.key)) {
        continue;
      }
      sanitizedFloorPositions[entry.key] = entry.value;
    }

    final sanitizedRoomPositions = <String, Map<String, Map<String, ZonePoint>>>{};
    for (final entry in data.roomButtonPositions.entries) {
      if (_removedZoneIds.contains(entry.key)) {
        continue;
      }
      sanitizedRoomPositions[entry.key] = entry.value;
    }

    return data.copyWith(
      homePageBlockButtons: keptButtons,
      polyPointsData: sanitizedPolygons,
      categoryNamesBlockFloorMap: sanitizedCategoryMap,
      floorButtonPositions: sanitizedFloorPositions,
      roomButtonPositions: sanitizedRoomPositions,
    );
  }
}

final zonesProvider = NotifierProvider<ZonesNotifier, ZonesState>(
  ZonesNotifier.new,
);

ZonesData mergeIncomingCoordinatesIntoCurrent({
  required ZonesData current,
  required ZonesData incomingCoordinates,
}) {
  final incomingButtonsByName = <String, ZoneButton>{
    for (final button in incomingCoordinates.homePageBlockButtons)
      button.buttonName: button,
  };
  final mergedButtons = current.homePageBlockButtons.map((button) {
    final incoming = incomingButtonsByName[button.buttonName];
    if (incoming == null) {
      return button;
    }
    return button.copyWith(
      xCoordinate: incoming.xCoordinate,
      yCoordinate: incoming.yCoordinate,
    );
  }).toList();

  final mergedFloorPositions = <String, Map<String, ZonePoint>>{};
  for (final zoneEntry in current.categoryNamesBlockFloorMap.entries) {
    final zoneId = zoneEntry.key;
    final knownFloors = zoneEntry.value.keys.toSet();
    final incomingZoneFloors = incomingCoordinates.floorButtonPositions[zoneId];
    if (incomingZoneFloors == null) {
      continue;
    }
    final filtered = <String, ZonePoint>{};
    for (final floorEntry in incomingZoneFloors.entries) {
      if (knownFloors.contains(floorEntry.key)) {
        filtered[floorEntry.key] = floorEntry.value;
      }
    }
    if (filtered.isNotEmpty) {
      mergedFloorPositions[zoneId] = filtered;
    }
  }

  final mergedRoomPositions = <String, Map<String, Map<String, ZonePoint>>>{};
  for (final zoneEntry in current.categoryNamesBlockFloorMap.entries) {
    final zoneId = zoneEntry.key;
    final incomingZoneRooms = incomingCoordinates.roomButtonPositions[zoneId];
    if (incomingZoneRooms == null) {
      continue;
    }
    final zoneFloorMap = <String, Map<String, ZonePoint>>{};
    for (final floorEntry in zoneEntry.value.entries) {
      final floorName = floorEntry.key;
      final knownRooms = floorEntry.value.toSet();
      final incomingFloorRooms = incomingZoneRooms[floorName];
      if (incomingFloorRooms == null) {
        continue;
      }
      final filtered = <String, ZonePoint>{};
      for (final roomEntry in incomingFloorRooms.entries) {
        if (knownRooms.contains(roomEntry.key)) {
          filtered[roomEntry.key] = roomEntry.value;
        }
      }
      if (filtered.isNotEmpty) {
        zoneFloorMap[floorName] = filtered;
      }
    }
    if (zoneFloorMap.isNotEmpty) {
      mergedRoomPositions[zoneId] = zoneFloorMap;
    }
  }

  return current.copyWith(
    schemaVersion: incomingCoordinates.schemaVersion,
    homePageBlockButtons: mergedButtons,
    polyPointsData: current.polyPointsData,
    floorButtonPositions: mergedFloorPositions,
    roomButtonPositions: mergedRoomPositions,
  );
}

List<ZoneButton> mergeMetadataButtonsIntoCurrent({
  required List<ZoneButton> currentButtons,
  required List<ZoneButton> metadataButtons,
}) {
  final currentByName = <String, ZoneButton>{
    for (final button in currentButtons) button.buttonName: button,
  };
  return metadataButtons.map((metadataButton) {
    final current = currentByName[metadataButton.buttonName];
    if (current == null) {
      return metadataButton;
    }
    return current.copyWith(
      uiDisplayName: metadataButton.uiDisplayName,
      active: metadataButton.active,
    );
  }).toList();
}

(int, int) countZoneRooms(Map<String, Map<String, List<String>>> map) {
  var floorCount = 0;
  var roomCount = 0;
  for (final floors in map.values) {
    floorCount += floors.length;
    for (final rooms in floors.values) {
      roomCount += rooms.length;
    }
  }
  return (floorCount, roomCount);
}

Map<String, dynamic> mergeZonesMetadataWithEngineeringData({
  required Map<String, dynamic> zonesLayoutJson,
  required Map<String, dynamic> engineeringJson,
}) {
  final engineeringMap =
      engineeringJson['categoryNamesBlockFloorMap'] as Map<String, dynamic>?;

  return {
    'schemaVersion': 2,
    'homePageBlockButtons': zonesLayoutJson['homePageBlockButtons'] ?? const [],
    'polyPointsData': zonesLayoutJson['polyPointsData'] ?? const [],
    'categoryNamesBlockFloorMap':
        engineeringMap ??
        zonesLayoutJson['categoryNamesBlockFloorMap'] ??
        const {},
    'floorButtonPositions': const <String, dynamic>{},
    'roomButtonPositions': const <String, dynamic>{},
  };
}

