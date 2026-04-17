import 'package:flutter/material.dart';

import '../models/alarm.dart';

class AlarmTable extends StatelessWidget {
  const AlarmTable({super.key, required this.alarms});

  final List<Alarm> alarms;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Room')),
            DataColumn(label: Text('Incident Time')),
            DataColumn(label: Text('Category')),
            DataColumn(label: Text('Ack')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Details')),
          ],
          rows: alarms
              .map((a) => DataRow(cells: [
                    DataCell(Text(a.room)),
                    DataCell(Text(a.incidentTime)),
                    DataCell(Text(a.category)),
                    DataCell(Text(a.acknowledgement)),
                    DataCell(Text(a.status)),
                    DataCell(SizedBox(width: 240, child: Text(a.details))),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}
