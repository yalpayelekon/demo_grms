import 'package:intl/intl.dart';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_models.dart';
import '../models/service_models.dart';
import '../providers/alarms_provider.dart';
import '../providers/room_service_provider.dart';

enum ReportType { alarm, service, energy, activity }

class ReportData {
  final List<String> headers;
  final List<List<dynamic>> rows;
  final String filename;
  final String title;

  ReportData({
    required this.headers,
    required this.rows,
    required this.filename,
    required this.title,
  });
}

class ReportsService {
  final List<AlarmData> alarms;
  final List<RoomServiceEntry> roomServices;

  ReportsService({
    required this.alarms,
    required this.roomServices,
  });

  ReportData? buildReport(ReportType type, DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) return null;

    // Adjust endDate to include the full day
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    final String dateSuffix = "${DateFormat('yyyy-MM-dd').format(start)}_to_${DateFormat('yyyy-MM-dd').format(end)}";

    switch (type) {
      case ReportType.alarm:
        final filtered = _filterAlarms(start, end);
        return ReportData(
          headers: ['ID', 'Room', 'Incident Time', 'Category', 'Status', 'Acknowledgement', 'Ack Time', 'IP Address', 'Details'],
          rows: filtered.map((a) => [
            a.id,
            a.room,
            a.incidentTime.replaceAll('\n', ' '),
            a.category,
            a.status.label,
            a.acknowledgement.label,
            a.acknowledgementTime,
            a.ipAddress ?? '',
            a.details,
          ]).toList(),
          filename: "Alarm_Report_$dateSuffix",
          title: "Alarm Reports",
        );

      case ReportType.service:
        final filtered = _filterServices(start, end);
        return ReportData(
          headers: ['Row', 'Room', 'Floor', 'Service Type', 'Service State', 'Activation Time', 'Delayed Min', 'Note'],
          rows: filtered.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final s = entry.value;
            return [
              idx,
              s.roomNumber,
              s.floor,
              s.serviceType.label,
              s.serviceState,
              s.activationTime,
              s.delayedMinutes,
              s.note ?? '',
            ];
          }).toList(),
          filename: "Service_Report_$dateSuffix",
          title: "Service Reports",
        );

      case ReportType.energy:
        final data = _generateEnergyData(start, end);
        return ReportData(
          headers: ['Date', 'Room', 'Energy Consumption (kWh)', 'Cost (\$)'],
          rows: data.map((e) => [e['date'], e['room'], e['energyConsumption'], e['cost']]).toList(),
          filename: "Energy_Report_$dateSuffix",
          title: "Energy Reports",
        );

      case ReportType.activity:
        final data = _generateActivityData(start, end);
        return ReportData(
          headers: ['ID', 'Source', 'Message', 'Timestamp'],
          rows: data.map((e) => [e['id'], e['source'], e['message'], e['timestamp']]).toList(),
          filename: "Activity_Report_$dateSuffix",
          title: "Activity Reports",
        );
    }
  }

  List<AlarmData> _filterAlarms(DateTime start, DateTime end) {
    final fmt = DateFormat('yyyy-MM-dd');
    return alarms.where((a) {
      try {
        final datePart = a.incidentTime.split('\n')[0].trim();
        final itemDate = fmt.parse(datePart);
        return itemDate.isAfter(start.subtract(const Duration(seconds: 1))) && 
               itemDate.isBefore(end.add(const Duration(seconds: 1)));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  List<RoomServiceEntry> _filterServices(DateTime start, DateTime end) {
    final format = DateFormat('yyyy-MM-dd HH:mm');
    return roomServices.where((s) {
      try {
        final activationTime = format.parse(s.activationTime);
        return activationTime.isAfter(start.subtract(const Duration(seconds: 1))) && 
               activationTime.isBefore(end.add(const Duration(seconds: 1)));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  List<Map<String, dynamic>> _generateEnergyData(DateTime start, DateTime end) {
    final random = Random();
    final days = end.difference(start).inDays;
    final List<Map<String, dynamic>> data = [];
    
    for (int i = 0; i <= min(days, 30); i++) {
      final date = start.add(Duration(days: i));
      data.add({
        'date': DateFormat('yyyy-MM-dd').format(date),
        'room': 'Room ${random.nextInt(450) + 1}',
        'energyConsumption': (random.nextDouble() * 50 + 10).toStringAsFixed(2),
        'cost': (random.nextDouble() * 20 + 5).toStringAsFixed(2),
      });
    }
    return data;
  }

  List<Map<String, dynamic>> _generateActivityData(DateTime start, DateTime end) {
    // Activity is partially derived from alarms and room services
    final List<Map<String, dynamic>> activities = [];
    
    for (var a in _filterAlarms(start, end)) {
      activities.add({
        'id': 'AL-${a.id}',
        'source': 'Alarm System',
        'message': 'Alarm ${a.category} triggered in ${a.room}',
        'timestamp': a.incidentTime.replaceAll('\n', ' '),
      });
    }

    for (var s in _filterServices(start, end)) {
      activities.add({
        'id': 'SRV-${s.id}',
        'source': 'Service System',
        'message': 'Service ${s.serviceState} for room ${s.roomNumber}',
        'timestamp': s.activationTime,
      });
    }

    return activities;
  }

  String convertToCSV(ReportData report) {
    final List<List<dynamic>> csvData = [
      report.headers,
      ...report.rows,
    ];
    // Standard CSV implementation as fallback for package issues
    return csvData.map((row) => row.map((e) {
      final s = e.toString().replaceAll('"', '""');
      return s.contains(',') || s.contains('\n') || s.contains('"') ? '"$s"' : s;
    }).join(',')).join('\r\n');
  }
}

final reportsServiceProvider = Provider<ReportsService>((ref) {
  final alarms = ref.watch(alarmsProvider).allAlarms;
  final roomServices = ref.watch(roomServiceProvider);
  return ReportsService(alarms: alarms, roomServices: roomServices);
});
