import 'package:flutter/material.dart';

import '../models/service_status_entry.dart';

class ServiceTable extends StatelessWidget {
  const ServiceTable({super.key, required this.services, required this.onToggleAck});

  final List<ServiceStatusEntry> services;
  final ValueChanged<String> onToggleAck;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Room')),
            DataColumn(label: Text('Service Type')),
            DataColumn(label: Text('Activation Time')),
            DataColumn(label: Text('State')),
            DataColumn(label: Text('Delayed (min)')),
            DataColumn(label: Text('Ack')),
          ],
          rows: services
              .map((s) => DataRow(cells: [
                    DataCell(Text(s.roomNumber)),
                    DataCell(Text(s.serviceType)),
                    DataCell(Text(s.activationTime)),
                    DataCell(Text(s.serviceState)),
                    DataCell(Text('${s.delayedMinutes}')),
                    DataCell(
                      TextButton(
                        onPressed: () => onToggleAck(s.id),
                        child: Text(s.acknowledgement ?? '-'),
                      ),
                    ),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}
