import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/alarm_models.dart';
import '../models/dashboard_models.dart';
import '../models/room_models.dart';
import '../models/service_models.dart';
import 'zones_provider.dart';
import 'hotel_status_provider.dart';
import 'alarms_provider.dart';
import 'room_service_provider.dart';

class DashboardState {
  final double? outsideTemp;
  final DashboardStats stats;

  DashboardState({
    this.outsideTemp,
    required this.stats,
  });

  DashboardState copyWith({
    double? outsideTemp,
    DashboardStats? stats,
  }) {
    return DashboardState(
      outsideTemp: outsideTemp ?? this.outsideTemp,
      stats: stats ?? this.stats,
    );
  }
}

class DashboardNotifier extends Notifier<DashboardState> {
  Timer? _weatherTimer;

  @override
  DashboardState build() {
    _fetchWeather();
    _weatherTimer = Timer.periodic(const Duration(minutes: 30), (_) => _fetchWeather());

    ref.onDispose(() {
      _weatherTimer?.cancel();
    });

    final zonesState = ref.watch(zonesProvider);
    final hotelStatusState = ref.watch(hotelStatusProvider);
    final alarmsState = ref.watch(alarmsProvider);
    final roomServiceState = ref.watch(roomServiceProvider);

    final stats = _calculateStats(
      zonesState,
      hotelStatusState,
      alarmsState,
      roomServiceState,
    );

    return DashboardState(stats: stats);
  }

  DashboardStats _calculateStats(
    ZonesState zones,
    HotelStatusState hotelStatus,
    AlarmsState alarms,
    List<RoomServiceEntry> services,
  ) {
    final allRoomNumbers = zones.zonesData.categoryNamesBlockFloorMap.values
        .expand((floors) => floors.values.expand((rooms) => rooms))
        .toList();

    final totalRooms = allRoomNumbers.length;
    if (totalRooms == 0) return DashboardStats.empty();

    final List<RoomData> roomDataList = allRoomNumbers.map((roomNumber) {
      return hotelStatus.rooms[roomNumber] ?? _generateMockState(roomNumber);
    }).toList();

    // Occupancy Stats
    final occupiedRooms = roomDataList.where((r) => r.status == RoomStatus.rentedOccupied).length;
    final vacantRooms = roomDataList.where((r) => r.status == RoomStatus.rentedVacant || r.status == RoomStatus.unrentedVacant).length;
    final housekeepingRooms = roomDataList.where((r) => r.status == RoomStatus.rentedHK || r.status == RoomStatus.unrentedHK).length;
    final occupancyRate = totalRooms == 0 ? 0 : ((occupiedRooms / totalRooms) * 100).round();

    // HVAC Stats
    final cooling = roomDataList.where((r) => r.hvac == HvacStatus.cold).length;
    final heating = roomDataList.where((r) => r.hvac == HvacStatus.hot).length;
    final hvacOff = totalRooms - cooling - heating;

    final hvacStats = [
      HvacStat(label: 'Cooling', rooms: cooling, percent: (cooling / totalRooms * 100).round()),
      HvacStat(label: 'Off', rooms: hvacOff, percent: (hvacOff / totalRooms * 100).round()),
      HvacStat(label: 'Heating', rooms: heating, percent: (heating / totalRooms * 100).round()),
    ];

    // Alarm Stats
    final filteredAlarms = alarms.filteredAlarms.where((a) => a.status != AlarmStatus.fixed).toList();
    final Map<String, int> alarmCounts = {};
    for (var alarm in filteredAlarms) {
      final category = _normalizeCategory(alarm.category);
      alarmCounts[category] = (alarmCounts[category] ?? 0) + 1;
    }

    final alarmStats = alarmCounts.entries.map((e) => AlarmStat(
      label: e.key,
      count: e.value,
      badgeClass: _getBadgeClass(e.key),
    )).toList();

    // Room Service Stats
    int lnd = 0;
    int mur = 0;
    int delayed = 0;
    int inProgress = 0;
    int totalActive = 0;

    for (var s in services) {
      if (s.serviceType != ServiceType.laundry && s.serviceType != ServiceType.mur) continue;
      
      final activeStates = {'Requested', 'Delayed', 'Started'};
      if (!activeStates.contains(s.serviceState)) continue;

      totalActive++;
      if (s.serviceType == ServiceType.laundry) lnd++;
      if (s.serviceType == ServiceType.mur) mur++;
      if (s.serviceState == 'Delayed') delayed++;
      if (s.serviceState == 'Started') inProgress++;
    }

    final responseRate = totalActive == 0 ? 100 : (((totalActive - delayed) / totalActive) * 100).round();

    return DashboardStats(
      totalRooms: totalRooms,
      occupiedRooms: occupiedRooms,
      vacantRooms: vacantRooms,
      housekeepingRooms: housekeepingRooms,
      occupancyRate: occupancyRate,
      hvacStats: hvacStats,
      alarmStats: alarmStats,
      lndCount: lnd,
      murCount: mur,
      delayedCount: delayed,
      inProgressCount: inProgress,
      responseRate: responseRate,
    );
  }

  String _normalizeCategory(String cat) {
    if (cat.contains('RCU')) return 'RCU';
    if (cat.contains('Lighting')) return 'Lighting';
    if (cat.contains('HVAC')) return 'HVAC';
    if (cat.contains('PMS')) return 'PMS';
    if (cat.contains('Door')) return 'Door Sys';
    if (cat.contains('Inact')) return 'Long Inact.';
    return cat;
  }

  String _getBadgeClass(String cat) {
    switch (cat) {
      case 'Long Inact.': return 'badge-danger';
      case 'Door Sys': return 'badge-danger';
      case 'RCU': return 'badge-danger';
      case 'Lighting': return 'badge-success';
      default: return 'badge-warning';
    }
  }

  RoomData _generateMockState(String number) {
    final hash = number.hashCode;
    
    return RoomData(
      number: number,
      status: RoomStatus.values[hash % RoomStatus.values.length],
      hasAlarm: hash % 13 == 0,
      lightingOn: hash % 3 == 0,
      hvac: HvacStatus.values[hash % HvacStatus.values.length],
      dnd: DndStatus.off,
      mur: MurStatus.finished,
      laundry: LaundryStatus.finished,
    );
  }

  Future<void> _fetchWeather() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=36.8969&longitude=30.7133&current=temperature_2m&timezone=auto'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final temp = (data['current']['temperature_2m'] as num).toDouble();
        state = state.copyWith(outsideTemp: temp);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Weather error: $e');
      }
    }
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, DashboardState>(DashboardNotifier.new);

