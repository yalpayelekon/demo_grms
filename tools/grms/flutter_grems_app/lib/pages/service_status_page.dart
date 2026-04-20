import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/room_service_provider.dart';
import '../providers/zones_provider.dart';
import '../models/service_models.dart';

class ServiceStatusPage extends ConsumerStatefulWidget {
  const ServiceStatusPage({super.key});

  @override
  ConsumerState<ServiceStatusPage> createState() => _ServiceStatusPageState();
}

class _ServiceStatusPageState extends ConsumerState<ServiceStatusPage> {
  int _rowsPerPage = 10;
  int _currentPage = 0;

  final List<String> _allStatusOptions = [
    'Off',
    'On',
    'Requested',
    'Delayed',
    'Started',
    'Finished',
    'Canceled',
  ];

  late final Set<String> _activeStatusFilters = _allStatusOptions.toSet();

  @override
  Widget build(BuildContext context) {
    final serviceState = ref.watch(roomServiceProvider);
    final syncStatus = ref.watch(demoRoomServiceSyncStatusProvider);
    final zonesState = ref.watch(zonesProvider);

    final filteredServices = serviceState.where((s) {
      return _activeStatusFilters.isEmpty ||
          _activeStatusFilters.contains(s.serviceState);
    }).toList();
    final totalPages = (filteredServices.length / _rowsPerPage).ceil();
    final startIndex = _currentPage * _rowsPerPage;
    final paginatedServices = filteredServices
        .skip(startIndex)
        .take(_rowsPerPage)
        .toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (syncStatus.targetUnreachable &&
                    (syncStatus.message?.isNotEmpty ?? false)) ...[
                  const SizedBox(width: 12),
                  Text(
                    syncStatus.message!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _buildHeader(),
            const SizedBox(height: 12),
            Expanded(child: _buildTable(paginatedServices, zonesState)),
            if (filteredServices.isNotEmpty)
              _buildFooter(filteredServices.length, totalPages),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1100;
        if (isNarrow) {
          return _buildFilters();
        }

        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildFilters(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allStatusOptions.map((option) {
            final isActive = _activeStatusFilters.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isActive,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _activeStatusFilters.add(option);
                  } else {
                    _activeStatusFilters.remove(option);
                  }
                  _currentPage = 0;
                });
              },
              selectedColor: Colors.blue.withOpacity(0.3),
              checkmarkColor: Colors.blue,
              labelStyle: TextStyle(
                color: isActive ? Colors.blue : Colors.white,
                fontSize: 13,
              ),
              backgroundColor: Colors.white.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isActive ? Colors.blue : Colors.white.withOpacity(0.1),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTable(List<RoomServiceEntry> entries, ZonesState zones) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('No room services found matching the criteria.'),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(0.82),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
            5: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05)),
              children: const [
                _TableHeaderCell('Room'),
                _TableHeaderCell('Service Type'),
                _TableHeaderCell('Request Time'),
                _TableHeaderCell('Status'),
                _TableHeaderCell('Ack'),
                _TableHeaderCell('Ack Time'),
              ],
            ),
            ...entries.map((entry) {
              final zoneName = _getZoneName(entry.roomNumber, zones);
              return TableRow(
                children: [
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.roomNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (zoneName != null)
                            Text(
                              zoneName,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _buildServicePill(entry),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _buildTimeCell(entry.activationTime),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _buildStatusBadge(entry),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _buildAckBadge(entry),
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: _buildTimeCell(entry.acknowledgementTime ?? '—'),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(int totalServices, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('Rows per page:'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _rowsPerPage,
            items: [5, 10, 25, 50]
                .map(
                  (v) => DropdownMenuItem(value: v, child: Text(v.toString())),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _rowsPerPage = v!;
              _currentPage = 0;
            }),
          ),
          const Spacer(),
          Text('${_currentPage + 1} of $totalPages ($totalServices total)'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCell(String time) {
    if (time == '—') {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }
    final parts = time.split(' ');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(parts[0], style: const TextStyle(fontSize: 12)),
        if (parts.length > 1)
          Text(
            parts[1],
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  Widget _buildServicePill(RoomServiceEntry entry) {
    String emoji = '🛎️';
    if (entry.serviceType == ServiceType.dnd) emoji = '🚫';
    if (entry.serviceType == ServiceType.mur) emoji = '🧹';
    if (entry.serviceType == ServiceType.laundry) emoji = '🧺';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.serviceType.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              entry.serviceState,
              style: TextStyle(
                fontSize: 10,
                color: _isStatusDelayed(entry) ? Colors.orange : Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isStatusDelayed(RoomServiceEntry entry) {
    return entry.serviceState == 'Delayed' || entry.delayedMinutes > 0;
  }

  Widget _buildStatusBadge(RoomServiceEntry entry) {
    Color bgColor = Colors.grey.withOpacity(0.1);
    Color textColor = Colors.grey;
    String text = entry.serviceState;

    if (entry.serviceState == 'Requested') {
      bgColor = Colors.red.withOpacity(0.1);
      textColor = Colors.redAccent;
      text = 'requested';
    } else if (entry.serviceState == 'Started') {
      bgColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orangeAccent;
      text = 'started';
    } else if (entry.serviceState == 'Delayed') {
      bgColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orangeAccent;
      text = 'delayed ${entry.delayedMinutes} min';
    } else if (entry.serviceState == 'Finished') {
      bgColor = Colors.green.withOpacity(0.1);
      textColor = Colors.greenAccent;
      text = entry.finishedMinutes != null
          ? 'finished in ${entry.finishedMinutes} min'
          : 'finished';
    } else if (entry.serviceState == 'Canceled') {
      bgColor = Colors.grey.withOpacity(0.1);
      textColor = Colors.grey;
      text = 'canceled';
    } else if (entry.serviceType == ServiceType.dnd) {
      final isOn = entry.serviceState == 'On';
      bgColor = isOn
          ? Colors.orange.withOpacity(0.1)
          : Colors.grey.withOpacity(0.1);
      textColor = isOn ? Colors.orangeAccent : Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAckBadge(RoomServiceEntry entry) {
    if (entry.serviceType == ServiceType.dnd) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }

    final isAck = entry.acknowledgement == ServiceAcknowledgement.acknowledged;
    final isWaiting =
        entry.acknowledgement == ServiceAcknowledgement.waitingAck;

    if (!isAck && !isWaiting) {
      return const Text('—', style: TextStyle(color: Colors.grey));
    }

    return InkWell(
      onTap: () => ref
          .read(roomServiceProvider.notifier)
          .toggleAcknowledgement(entry.id),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isAck ? Colors.green : Colors.red).withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          entry.acknowledgement.label,
          style: TextStyle(
            color: isAck ? Colors.greenAccent : Colors.redAccent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String? _getZoneName(String roomNumber, ZonesState zones) {
    // Search in categoryNamesBlockFloorMap
    for (var zoneEntry in zones.zonesData.categoryNamesBlockFloorMap.entries) {
      for (var floorEntry in zoneEntry.value.entries) {
        if (floorEntry.value.contains(roomNumber)) {
          // Now find the display name in homePageBlockButtons
          final zoneBtn = zones.zonesData.homePageBlockButtons.firstWhere(
            (b) => b.buttonName == zoneEntry.key,
            orElse: () => zones.zonesData.homePageBlockButtons.firstWhere(
              (b) => b.active,
              orElse: () => zones.zonesData.homePageBlockButtons[0],
            ),
          );
          return zoneBtn.uiDisplayName;
        }
      }
    }
    return null;
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String label;

  const _TableHeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
