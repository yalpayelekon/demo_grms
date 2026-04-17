import 'package:flutter/material.dart';

class RoomControlRow extends StatelessWidget {
  const RoomControlRow({
    super.key,
    required this.room,
    required this.hvacValue,
    required this.onHvacSetPoint,
    required this.devices,
    required this.onSetDevice,
  });

  final String room;
  final double hvacValue;
  final ValueChanged<double> onHvacSetPoint;
  final List<Map<String, dynamic>> devices;
  final void Function(int address, int level, String type) onSetDevice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room $room', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('HVAC Setpoint')),
                Expanded(
                  child: Slider(
                    value: hvacValue,
                    min: 16,
                    max: 30,
                    divisions: 14,
                    label: hvacValue.toStringAsFixed(1),
                    onChanged: onHvacSetPoint,
                  ),
                ),
              ],
            ),
            for (final device in devices)
              Row(
                children: [
                  SizedBox(width: 180, child: Text(device['name'].toString())),
                  Expanded(
                    child: Slider(
                      value: ((device['targetLevel'] as int?) ?? 0).toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${device['targetLevel'] ?? 0}',
                      onChanged: (v) => onSetDevice(device['address'] as int, v.round(), device['type'] as String? ?? 'dali'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
