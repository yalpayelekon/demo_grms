import 'package:flutter/foundation.dart';

@immutable
class DashboardStats {
  final int totalRooms;
  final int occupiedRooms;
  final int vacantRooms;
  final int housekeepingRooms;
  final int occupancyRate;
  final int rentedRate;

  final List<RoomStatusStat> roomStatusStats;
  final List<HvacStat> hvacStats;
  final List<AlarmStat> alarmStats;

  final int lndCount;
  final int murCount;
  final int dndCount;
  final int delayedCount;
  final int inProgressCount;
  final int responseRate;
  final int averageServiceRequestMinutes;

  const DashboardStats({
    required this.totalRooms,
    required this.occupiedRooms,
    required this.vacantRooms,
    required this.housekeepingRooms,
    required this.occupancyRate,
    required this.rentedRate,
    required this.roomStatusStats,
    required this.hvacStats,
    required this.alarmStats,
    required this.lndCount,
    required this.murCount,
    required this.dndCount,
    required this.delayedCount,
    required this.inProgressCount,
    required this.responseRate,
    required this.averageServiceRequestMinutes,
  });

  factory DashboardStats.empty() {
    return const DashboardStats(
      totalRooms: 0,
      occupiedRooms: 0,
      vacantRooms: 0,
      housekeepingRooms: 0,
      occupancyRate: 0,
      rentedRate: 0,
      roomStatusStats: [],
      hvacStats: [],
      alarmStats: [],
      lndCount: 0,
      murCount: 0,
      dndCount: 0,
      delayedCount: 0,
      inProgressCount: 0,
      responseRate: 100,
      averageServiceRequestMinutes: 0,
    );
  }
}

@immutable
class RoomStatusStat {
  final String label;
  final int rooms;

  const RoomStatusStat({required this.label, required this.rooms});
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
