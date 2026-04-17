import 'package:flutter/foundation.dart';

@immutable
class DashboardStats {
  final int totalRooms;
  final int occupiedRooms;
  final int vacantRooms;
  final int housekeepingRooms;
  final int occupancyRate;
  
  final List<HvacStat> hvacStats;
  final List<AlarmStat> alarmStats;
  
  final int lndCount;
  final int murCount;
  final int delayedCount;
  final int inProgressCount;
  final int responseRate;

  const DashboardStats({
    required this.totalRooms,
    required this.occupiedRooms,
    required this.vacantRooms,
    required this.housekeepingRooms,
    required this.occupancyRate,
    required this.hvacStats,
    required this.alarmStats,
    required this.lndCount,
    required this.murCount,
    required this.delayedCount,
    required this.inProgressCount,
    required this.responseRate,
  });

  factory DashboardStats.empty() {
    return const DashboardStats(
      totalRooms: 0,
      occupiedRooms: 0,
      vacantRooms: 0,
      housekeepingRooms: 0,
      occupancyRate: 0,
      hvacStats: [],
      alarmStats: [],
      lndCount: 0,
      murCount: 0,
      delayedCount: 0,
      inProgressCount: 0,
      responseRate: 100,
    );
  }
}

@immutable
class HvacStat {
  final String label;
  final int rooms;
  final int percent;

  const HvacStat({
    required this.label,
    required this.rooms,
    required this.percent,
  });
}

@immutable
class AlarmStat {
  final String label;
  final int count;
  final String badgeClass; // Not strictly needed in Flutter but keeps parity

  const AlarmStat({
    required this.label,
    required this.count,
    this.badgeClass = 'badge-warning',
  });
}
