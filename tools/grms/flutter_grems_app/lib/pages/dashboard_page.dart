import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../providers/hotel_status_provider.dart';
import '../providers/room_service_provider.dart';
import '../providers/coordinates_sync_provider.dart';
import '../models/dashboard_models.dart';
import '../widgets/energy_savings_chart.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(dashboardProvider);
    final stats = dashboardState.stats;
    final hotelSync = ref.watch(demoRoomHotelSyncStatusProvider);
    final serviceSync = ref.watch(demoRoomServiceSyncStatusProvider);
    final coordinatesSync = ref.watch(coordinatesSyncProvider);
    final size = MediaQuery.of(context).size;
    final isWideDesktop = size.width > 1200;
    final canUseFixedDesktopGrid = isWideDesktop && size.height > 860;
    final useCompactCards = size.height <= 920 || size.width <= 1360;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade900.withOpacity(0.8), Colors.black],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: canUseFixedDesktopGrid
                    // Desktop/tablet: fit cards into viewport without scrolling
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildResponsiveGrid(
                              context,
                              stats,
                              dashboardState,
                              hotelSync: hotelSync,
                              serviceSync: serviceSync,
                              coordinatesSync: coordinatesSync,
                              isDesktop: true,
                              useCompactCards: useCompactCards,
                            ),
                          ),
                        ],
                      )
                    // Constrained height / mobile: allow scrolling
                    : SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildResponsiveGrid(
                                context,
                                stats,
                                dashboardState,
                                hotelSync: hotelSync,
                                serviceSync: serviceSync,
                                coordinatesSync: coordinatesSync,
                                isDesktop: false,
                                useCompactCards: true,
                              ),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(
    BuildContext context,
    DashboardStats stats,
    DashboardState state, {
    required DemoRoomHotelSyncStatus hotelSync,
    required DemoRoomServiceSyncStatus serviceSync,
    required CoordinatesSyncState coordinatesSync,
    required bool isDesktop,
    required bool useCompactCards,
  }) {
    final communicationItems = <_CommunicationItem>[
      _CommunicationItem(
        label: 'RCU Link',
        value: hotelSync.targetUnreachable ? 'Offline' : 'Online',
        online: !hotelSync.targetUnreachable,
      ),
      _CommunicationItem(
        label: 'Service Bus',
        value: serviceSync.connected ? 'Online' : 'Offline',
        online: serviceSync.connected && !serviceSync.targetUnreachable,
      ),
      _CommunicationItem(
        label: 'Coordinates',
        value: coordinatesSync.connected ? 'Online' : 'Offline',
        online: coordinatesSync.connected,
      ),
      _CommunicationItem(
        label: 'PMS',
        value: 'Online',
        online: true,
      ),
    ];

    if (isDesktop) {
      return Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CommunicationPanel(
                    items: communicationItems,
                    compact: useCompactCards,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _AlarmPanel(
                    stats: stats.alarmStats,
                    compact: useCompactCards,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _HvacPanel(
                    stats: stats.hvacStats,
                    totalRooms: stats.totalRooms,
                    outsideTemp: state.outsideTemp,
                    compact: useCompactCards,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _OccupancyPanel(
                    stats: stats,
                    compact: useCompactCards,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ServicePanel(
                    stats: stats,
                    compact: useCompactCards,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _EnergyPanel(
                    isCompact: true,
                    compact: useCompactCards,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _CommunicationPanel(items: communicationItems, compact: useCompactCards),
        const SizedBox(height: 24),
        _AlarmPanel(stats: stats.alarmStats, compact: useCompactCards),
        const SizedBox(height: 24),
        _HvacPanel(
          stats: stats.hvacStats,
          totalRooms: stats.totalRooms,
          outsideTemp: state.outsideTemp,
          compact: useCompactCards,
        ),
        const SizedBox(height: 24),
        _OccupancyPanel(stats: stats, compact: useCompactCards),
        const SizedBox(height: 24),
        _ServicePanel(stats: stats, compact: useCompactCards),
        const SizedBox(height: 24),
        _EnergyPanel(isCompact: false, compact: useCompactCards),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool compact;

  const _GlassCard({
    required this.child,
    required this.title,
    this.subtitle,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = compact ? 18.0 : 24.0;
    final headerGap = compact ? 16.0 : 24.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compact ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: compact ? 12 : 13,
                        ),
                      ),
                    ],
                  ],
                ),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: headerGap),
            child,
          ],
        ),
      ),
    );
  }
}

class _AlarmPanel extends StatelessWidget {
  final List<AlarmStat> stats;
  final bool compact;
  const _AlarmPanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Alarm Status',
      subtitle: 'Last 24h snapshot',
      compact: compact,
      child: Column(
        children: stats.map((stat) => Padding(
          padding: EdgeInsets.only(bottom: compact ? 9.0 : 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 14 : 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 10,
                  vertical: compact ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: _getBadgeColor(stat.badgeClass).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getBadgeColor(stat.badgeClass).withOpacity(0.5)),
                ),
                child: Text(
                  stat.count.toString(),
                  style: TextStyle(
                    color: _getBadgeColor(stat.badgeClass),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Color _getBadgeColor(String badgeClass) {
    if (badgeClass == 'badge-danger') return Colors.redAccent;
    if (badgeClass == 'badge-success') return Colors.greenAccent;
    return Colors.orangeAccent;
  }
}

class _OccupancyPanel extends StatelessWidget {
  final DashboardStats stats;
  final bool compact;
  const _OccupancyPanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Occupancy Status',
      compact: compact,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${stats.occupancyRate}%',
            style: TextStyle(
              fontSize: compact ? 24 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          const Text('Total', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
      child: Column(
        children: [
          _StatRow(
            label: 'Occupied',
            value: '${stats.occupiedRooms} / ${stats.totalRooms}',
            color: Colors.blueAccent,
          ),
          const Divider(color: Colors.white10, height: 24),
          _StatRow(
            label: 'Vacant',
            value: '${stats.vacantRooms} / ${stats.totalRooms}',
            color: Colors.white70,
          ),
          const Divider(color: Colors.white10, height: 24),
          _StatRow(
            label: 'Housekeeping',
            value: '${stats.housekeepingRooms} / ${stats.totalRooms}',
            color: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }
}

class _ServicePanel extends StatelessWidget {
  final DashboardStats stats;
  final bool compact;
  const _ServicePanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Service Requests',
      subtitle: 'Live status overview',
      compact: compact,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _CountBox(
                  label: 'LND',
                  value: stats.lndCount.toString(),
                  compact: compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CountBox(
                  label: 'MUR',
                  value: stats.murCount.toString(),
                  compact: compact,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 16),
          Row(
            children: [
              Expanded(
                child: _SmallStat(
                  label: 'Delayed',
                  value: stats.delayedCount.toString(),
                  color: Colors.redAccent,
                  compact: compact,
                ),
              ),
              Expanded(
                child: _SmallStat(
                  label: 'In Progress',
                  value: stats.inProgressCount.toString(),
                  color: Colors.blueAccent,
                  compact: compact,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 16),
          _ResponseGauge(rate: stats.responseRate, compact: compact),
        ],
      ),
    );
  }
}

class _HvacPanel extends StatelessWidget {
  final List<HvacStat> stats;
  final int totalRooms;
  final double? outsideTemp;
  final bool compact;
  const _HvacPanel({
    required this.stats,
    required this.totalRooms,
    required this.outsideTemp,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'HVAC Status',
      compact: compact,
      trailing: outsideTemp != null ? Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${outsideTemp!.round()}°C',
            style: TextStyle(
              fontSize: compact ? 21 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text('Outside', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ) : null,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: compact ? 8 : 12,
        crossAxisSpacing: compact ? 8 : 12,
        childAspectRatio: compact ? 2.4 : 2.8,
        children: stats.take(4).map((stat) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${stat.rooms}',
                  style: TextStyle(
                    color: _getHvacColors(stat.label).first,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 23 : 26,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
                Text(
                  '/$totalRooms',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Color> _getHvacColors(String label) {
    if (label == 'Cooling') return [Colors.blue, Colors.cyan];
    if (label == 'Idle') return [Colors.green, Colors.lightGreenAccent];
    if (label == 'Heating') return [Colors.red, Colors.orange];
    return [Colors.grey, Colors.blueGrey];
  }
}

class _EnergyPanel extends StatelessWidget {
  final bool isCompact;
  final bool compact;

  const _EnergyPanel({required this.isCompact, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final chartHeight = isCompact
        ? (compact ? 160.0 : 200.0)
        : (compact ? 240.0 : 300.0);

    return _GlassCard(
      title: 'Energy Consumption',
      subtitle: 'Energy saving trend',
      compact: compact,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _EnergyLegendItem(
                label: 'Total',
                value: '148 kWh',
                compact: compact,
              ),
              _EnergyLegendItem(
                label: 'Peak',
                value: '182 kWh',
                compact: compact,
              ),
              _EnergyLegendItem(
                label: 'Off-Peak',
                value: '96 kWh',
                compact: compact,
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          SizedBox(
            height: chartHeight,
            child: const EnergySavingsChart(),
          ),
        ],
      ),
    );
  }
}

class _CommunicationItem {
  final String label;
  final String value;
  final bool online;

  const _CommunicationItem({
    required this.label,
    required this.value,
    required this.online,
  });
}

class _CommunicationPanel extends StatelessWidget {
  final List<_CommunicationItem> items;
  final bool compact;

  const _CommunicationPanel({required this.items, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Communication Status',
      subtitle: 'Controller and integration links',
      compact: compact,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: compact ? 8 : 10,
        crossAxisSpacing: compact ? 8 : 10,
        childAspectRatio: compact ? 2.3 : 2.6,
        children: items.map((item) {
          final color = item.online ? Colors.greenAccent : Colors.redAccent;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: compact ? 11 : 13,
                        ),
                      ),
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}

class _CountBox extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  const _CountBox({
    required this.label,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          SizedBox(height: compact ? 2 : 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 18 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool compact;
  const _SmallStat({
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white60, fontSize: compact ? 10 : 11),
        ),
        SizedBox(height: compact ? 1 : 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ResponseGauge extends StatelessWidget {
  final int rate;
  final bool compact;
  const _ResponseGauge({required this.rate, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Response Rate',
              style: TextStyle(
                color: Colors.white60,
                fontSize: compact ? 11 : 12,
              ),
            ),
            Text('$rate%', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: rate / 100,
            backgroundColor: Colors.white10,
            color: Colors.greenAccent,
            minHeight: compact ? 6 : 8,
          ),
        ),
      ],
    );
  }
}

class _EnergyLegendItem extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  const _EnergyLegendItem({
    required this.label,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white54, fontSize: compact ? 10 : 11),
        ),
        SizedBox(height: compact ? 2 : 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : 14,
          ),
        ),
      ],
    );
  }
}
