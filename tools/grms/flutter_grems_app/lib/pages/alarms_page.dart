import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_models.dart';
import '../providers/alarms_provider.dart';

class AlarmsPage extends ConsumerStatefulWidget {
  const AlarmsPage({super.key});

  @override
  ConsumerState<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends ConsumerState<AlarmsPage> {
  int _rowsPerPage = 10;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final alarmsState = ref.watch(alarmsProvider);
    final filteredAlarms = alarmsState.filteredAlarms;
    final totalPages = (filteredAlarms.length / _rowsPerPage).ceil();
    final startIndex = _currentPage * _rowsPerPage;
    final paginatedAlarms = filteredAlarms.skip(startIndex).take(_rowsPerPage).toList();

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(alarmsState),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Room')),
                              DataColumn(label: Text('Incident Time')),
                              DataColumn(label: Text('Category')),
                              DataColumn(label: Text('Ack')),
                              DataColumn(label: Text('Ack Time')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Details')),
                            ],
                            rows: paginatedAlarms.map((alarm) => _buildRow(alarm)).toList(),
                          ),
                        ),
                      ),
                    ),
                    _buildFooter(filteredAlarms.length, totalPages),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AlarmsState state) {
    final notifier = ref.read(alarmsProvider.notifier);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          const Text('Alarms', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(width: 32),
          _buildFilterGroup('Category', state.categoryFilter, (v) => notifier.setFilters(category: v), ['All', 'Long Inact.', 'Open Door', 'PMS', 'RCU', 'Lighting', 'HVAC', 'HK']),
          const SizedBox(width: 16),
          _buildFilterGroup('Acknowledgement', state.ackFilter, (v) => notifier.setFilters(ack: v), ['All', 'Waiting Ack', 'Acknowledged']),
          const SizedBox(width: 16),
          _buildFilterGroup('Status', state.statusFilter, (v) => notifier.setFilters(status: v), ['All', 'Waiting Ack', 'Acknowledged', 'Waiting Repair/Cancel', 'Fixed']),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterGroup(String label, String value, ValueChanged<String?> onChanged, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        DropdownButton<String>(
          value: value,
          isDense: true,
          underline: const SizedBox(),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  DataRow _buildRow(AlarmData alarm) {
    return DataRow(cells: [
      DataCell(Text(alarm.room)),
      DataCell(Text(alarm.incidentTime)),
      DataCell(_buildCategoryBadge(alarm.category)),
      DataCell(_buildAckBadge(alarm)),
      DataCell(Text(alarm.acknowledgementTime)),
      DataCell(_buildStatusBadge(alarm)),
      DataCell(TextButton(
        onPressed: () => _showDetails(alarm),
        child: const Text('View Details'),
      )),
    ]);
  }

  Widget _buildCategoryBadge(String category) {
    return Chip(
      label: Text(category, style: const TextStyle(fontSize: 10)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildAckBadge(AlarmData alarm) {
    final isAck = alarm.acknowledgement == AlarmAcknowledgement.acknowledged;
    return InkWell(
      onTap: () => ref.read(alarmsProvider.notifier).toggleAcknowledgement(alarm.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isAck ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isAck ? Colors.green : Colors.red),
        ),
        child: Text(
          alarm.acknowledgement.label,
          style: TextStyle(color: isAck ? Colors.green : Colors.red, fontSize: 10),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(AlarmData alarm) {
    if (alarm.acknowledgement != AlarmAcknowledgement.acknowledged) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange),
        ),
        child: const Text('Waiting Repair/Cancel', style: TextStyle(color: Colors.orange, fontSize: 10)),
      );
    }

    final isFixed = alarm.status == AlarmStatus.fixed;
    return InkWell(
      onTap: () => ref.read(alarmsProvider.notifier).toggleStatus(alarm.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isFixed ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isFixed ? Colors.green : Colors.orange),
        ),
        child: Text(
          alarm.status.label,
          style: TextStyle(color: isFixed ? Colors.green : Colors.orange, fontSize: 10),
        ),
      ),
    );
  }

  Widget _buildFooter(int totalAlarms, int totalPages) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text('Rows per page:'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _rowsPerPage,
            items: [5, 10, 25, 50].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
            onChanged: (v) => setState(() {
              _rowsPerPage = v!;
              _currentPage = 0;
            }),
          ),
          const Spacer(),
          Text('${_currentPage + 1} of $totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
          ),
        ],
      ),
    );
  }

  void _showDetails(AlarmData alarm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alarm Details - ${alarm.room}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Incident Time', alarm.incidentTime),
            _detailRow('Category', alarm.category),
            _detailRow('Acknowledgement', alarm.acknowledgement.label),
            _detailRow('Ack Time', alarm.acknowledgementTime),
            _detailRow('Status', alarm.status.label),
            if (alarm.ipAddress != null) _detailRow('IP Address', alarm.ipAddress!),
            const SizedBox(height: 16),
            const Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(alarm.details),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
