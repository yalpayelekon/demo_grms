import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm_models.dart';
import '../models/service_models.dart';
import '../models/zones_models.dart';
import 'alarms_provider.dart';
import 'room_service_provider.dart';
import 'zones_provider.dart';

@immutable
class ZoneBadgeStats {
  const ZoneBadgeStats({
    this.alarms = 0,
    this.delayedServices = 0,
  });

  final int alarms;
  final int delayedServices;

  ZoneBadgeStats copyWith({
    int? alarms,
    int? delayedServices,
  }) {
    return ZoneBadgeStats(
      alarms: alarms ?? this.alarms,
      delayedServices: delayedServices ?? this.delayedServices,
    );
  }
}

Map<String, ZoneBadgeStats> computeZoneBadgeCounts({
  required ZonesData zonesData,
  required List<RoomServiceEntry> services,
  required List<AlarmData> alarms,
  required String? Function(String roomLabel) resolveZoneForRoomLabel,
  bool excludeFixedAlarms = true,
}) {
  final counts = <String, ZoneBadgeStats>{
    for (final btn in zonesData.homePageBlockButtons) btn.buttonName: const ZoneBadgeStats(),
  };

  var mappedDelayedServices = 0;
  var mappedAlarms = 0;

  for (final service in services) {
    final isDelayed =
        service.serviceState == 'Delayed' || service.delayedMinutes > 0;
    if (!isDelayed) {
      continue;
    }
    final zoneId = resolveZoneForRoomLabel(service.roomNumber);
    if (zoneId == null || !counts.containsKey(zoneId)) {
      continue;
    }
    final current = counts[zoneId]!;
    counts[zoneId] = current.copyWith(
      delayedServices: current.delayedServices + 1,
    );
    mappedDelayedServices += 1;
  }

  for (final alarm in alarms) {
    if (excludeFixedAlarms && alarm.status == AlarmStatus.fixed) {
      continue;
    }
    final zoneId = resolveZoneForRoomLabel(alarm.room);
    if (zoneId == null || !counts.containsKey(zoneId)) {
      continue;
    }
    final current = counts[zoneId]!;
    counts[zoneId] = current.copyWith(alarms: current.alarms + 1);
    mappedAlarms += 1;
  }

  if (kDebugMode) {
    final nonZero = counts.entries
        .where((entry) => entry.value.alarms > 0 || entry.value.delayedServices > 0)
        .map(
          (entry) =>
              '${entry.key}(a=${entry.value.alarms},d=${entry.value.delayedServices})',
        )
        .join(', ');
    debugPrint(
      'HomeZoneCounts: mappedAlarms=$mappedAlarms mappedDelayedServices=$mappedDelayedServices',
    );
    if (nonZero.isNotEmpty) {
      debugPrint('HomeZoneCounts: nonZero=$nonZero');
    }
  }

  return counts;
}

final homeZoneCountsProvider = Provider<Map<String, ZoneBadgeStats>>((ref) {
  final zonesState = ref.watch(zonesProvider);
  final alarmsState = ref.watch(alarmsProvider);
  final services = ref.watch(roomServiceProvider);
  final zonesNotifier = ref.read(zonesProvider.notifier);

  return computeZoneBadgeCounts(
    zonesData: zonesState.zonesData,
    services: services,
    alarms: alarmsState.allAlarms,
    resolveZoneForRoomLabel: zonesNotifier.findZoneForRoomLabel,
    excludeFixedAlarms: true,
  );
});
