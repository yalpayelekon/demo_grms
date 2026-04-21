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
    final isTablet = size.width >= 850 && size.width < 1200;
    final canUseFixedTabletGrid =
        isTablet && size.width >= 1100 && size.height >= 800;
    final canUseFixedLandscapeTabletGrid =
        size.width >= 1200 && size.width < 1360 && size.height >= 820;
    final useCompactCards = size.height <= 920 || size.width <= 1360;
    final useUltraCompactCards =
        isTablet || size.width < 850 || canUseFixedLandscapeTabletGrid;
    final useTightTabletSpacing =
        canUseFixedTabletGrid || canUseFixedLandscapeTabletGrid;
    final canUseFixedGrid =
        canUseFixedDesktopGrid ||
        canUseFixedTabletGrid ||
        canUseFixedLandscapeTabletGrid;

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
            colors: const [Color(0xFF1E2330), Color(0xFF171B26)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: EdgeInsets.all(useTightTabletSpacing ? 18.0 : 24.0),
                child: canUseFixedGrid
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
                              isDesktop: canUseFixedDesktopGrid,
                              pinToViewport: true,
                              useCompactCards: useCompactCards,
                              useUltraCompactCards: useUltraCompactCards,
                              useTightTabletSpacing: useTightTabletSpacing,
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
                                pinToViewport: false,
                                useCompactCards: true,
                                useUltraCompactCards: useUltraCompactCards,
                                useTightTabletSpacing: useTightTabletSpacing,
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
    required bool pinToViewport,
    required bool useCompactCards,
    required bool useUltraCompactCards,
    required bool useTightTabletSpacing,
  }) {
    final communicationItems = <_CommunicationItem>[
      _CommunicationItem(
        label: 'RCU Link',
        value: '363 / ${stats.totalRooms}',
        online: true,
      ),
      _CommunicationItem(label: 'BMS', value: 'Online', online: true),
      _CommunicationItem(label: 'Door Lock', value: 'Online', online: true),
      _CommunicationItem(label: 'PMS', value: 'Online', online: true),
    ];

    if (isDesktop || pinToViewport) {
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
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
                SizedBox(width: useTightTabletSpacing ? 12 : 16),
                Expanded(
                  child: _AlarmPanel(
                    stats: stats.alarmStats,
                    totalRooms: stats.totalRooms,
                    compact: useCompactCards,
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
                SizedBox(width: useTightTabletSpacing ? 12 : 16),
                Expanded(
                  child: _HvacPanel(
                    stats: stats.hvacStats,
                    totalRooms: stats.totalRooms,
                    outsideTemp: state.outsideTemp,
                    compact: useCompactCards,
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: useTightTabletSpacing ? 12 : 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _OccupancyPanel(
                    stats: stats,
                    compact: useCompactCards,
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
                SizedBox(width: useTightTabletSpacing ? 12 : 16),
                Expanded(
                  child: _ServicePanel(
                    stats: stats,
                    compact: useCompactCards,
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
                SizedBox(width: useTightTabletSpacing ? 12 : 16),
                Expanded(
                  child: _EnergyPanel(
                    isCompact: true,
                    compact: useCompactCards,
                    ultraCompact: useUltraCompactCards,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final cards = <Widget>[
      _CommunicationPanel(
        items: communicationItems,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
      _AlarmPanel(
        stats: stats.alarmStats,
        totalRooms: stats.totalRooms,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
      _HvacPanel(
        stats: stats.hvacStats,
        totalRooms: stats.totalRooms,
        outsideTemp: state.outsideTemp,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
      _OccupancyPanel(
        stats: stats,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
      _ServicePanel(
        stats: stats,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
      _EnergyPanel(
        isCompact: true,
        compact: useCompactCards,
        ultraCompact: useUltraCompactCards,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 850 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: !pinToViewport,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: useTightTabletSpacing ? 12 : 16,
            crossAxisSpacing: useTightTabletSpacing ? 12 : 16,
            childAspectRatio: pinToViewport
                ? (useUltraCompactCards ? 1.34 : 1.42)
                : (useUltraCompactCards ? 1.18 : 1.28),
          ),
          itemBuilder: (context, index) => cards[index],
        );
      },
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool compact;
  final bool ultraCompact;

  const _GlassCard({
    required this.child,
    required this.title,
    this.subtitle,
    this.trailing,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = ultraCompact ? 10.0 : (compact ? 14.0 : 24.0);
    final headerGap = ultraCompact ? 8.0 : (compact ? 12.0 : 24.0);
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
                        fontSize: ultraCompact ? 15 : (compact ? 17 : 20),
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
                          fontSize: ultraCompact ? 9 : (compact ? 11 : 13),
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
  final int totalRooms;
  final bool compact;
  final bool ultraCompact;
  const _AlarmPanel({
    required this.stats,
    required this.totalRooms,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sortedStats = [...stats]..sort((a, b) => b.count.compareTo(a.count));

    return _GlassCard(
      title: 'Alarm Status',
      compact: compact,
      ultraCompact: ultraCompact,
      child: Column(
        children: [
          if (sortedStats.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: compact ? 4 : 6),
              child: Text(
                'Aktif alarm yok',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 760 ? 3 : 2;
                final spacing = compact ? 6.0 : 8.0;
                final baseCardWidth =
                    (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;
                final cardWidth = baseCardWidth * 0.65;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: sortedStats.map((stat) {
                    return SizedBox(
                      width: cardWidth,
                      child: _AlarmCategoryCard(
                        label: stat.label,
                        count: stat.count,
                        totalRooms: totalRooms,
                        color: _getBadgeColor(stat.badgeClass),
                        compact: compact,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Color _getBadgeColor(String badgeClass) {
    if (badgeClass == 'badge-danger') return Colors.redAccent;
    if (badgeClass == 'badge-success') return Colors.greenAccent;
    return Colors.orangeAccent;
  }
}

class _AlarmCategoryCard extends StatelessWidget {
  final String label;
  final int count;
  final int? totalRooms;
  final Color color;
  final bool compact;

  const _AlarmCategoryCard({
    required this.label,
    required this.count,
    this.totalRooms,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, fontSize: compact ? 9 : 10),
          ),
          SizedBox(height: compact ? 2 : 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                totalRooms == null ? count.toString() : '$count / $totalRooms',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 13 : 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccupancyPanel extends StatelessWidget {
  final DashboardStats stats;
  final bool compact;
  final bool ultraCompact;
  const _OccupancyPanel({
    required this.stats,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Occupancy Status',
      compact: compact,
      ultraCompact: ultraCompact,
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
          const Text(
            'Total',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
      child: Column(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: compact ? 6 : 8,
            crossAxisSpacing: compact ? 6 : 8,
            childAspectRatio: compact ? 3.3 : 3.6,
            children: stats.roomStatusStats.asMap().entries.map((entry) {
              final index = entry.key;
              final statusStat = entry.value;
              return _AlarmCategoryCard(
                label: statusStat.label,
                count: statusStat.rooms,
                totalRooms: stats.totalRooms,
                color: _statusColor(index),
                compact: compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _statusColor(int index) {
    const palette = [
      Colors.lightBlueAccent,
      Colors.orangeAccent,
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.white70,
      Colors.redAccent,
    ];
    return palette[index % palette.length];
  }
}

class _ServicePanel extends StatelessWidget {
  final DashboardStats stats;
  final bool compact;
  final bool ultraCompact;
  const _ServicePanel({
    required this.stats,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Service Requests',
      subtitle: 'Live status overview',
      compact: compact,
      ultraCompact: ultraCompact,
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
          SizedBox(height: compact ? 10 : 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Avg Request Time',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: compact ? 11 : 12,
                ),
              ),
              Text(
                '${stats.averageServiceRequestMinutes} min',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            ],
          ),
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
  final bool ultraCompact;
  const _HvacPanel({
    required this.stats,
    required this.totalRooms,
    required this.outsideTemp,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'HVAC Status',
      compact: compact,
      ultraCompact: ultraCompact,
      trailing: outsideTemp != null
          ? Column(
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
                const Text(
                  'Outside',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            )
          : null,
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
                  '${stat.rooms} / $totalRooms',
                  style: TextStyle(
                    color: _getHvacColors(stat.label).first,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 20 : 22,
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
  final bool ultraCompact;

  const _EnergyPanel({
    required this.isCompact,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final chartHeight = isCompact
        ? (compact ? 160.0 : 200.0)
        : (compact ? 240.0 : 300.0);

    return _GlassCard(
      title: 'Energy Consumption',
      subtitle: 'Energy saving trend',
      compact: compact,
      ultraCompact: ultraCompact,
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
          SizedBox(height: chartHeight, child: const EnergySavingsChart()),
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
  final bool ultraCompact;

  const _CommunicationPanel({
    required this.items,
    this.compact = false,
    this.ultraCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      title: 'Communication Status',
      subtitle: 'Controller and integration links',
      compact: compact,
      ultraCompact: ultraCompact,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: ultraCompact ? 6 : (compact ? 8 : 10),
        crossAxisSpacing: ultraCompact ? 6 : (compact ? 8 : 10),
        childAspectRatio: ultraCompact ? 2.0 : (compact ? 2.3 : 2.6),
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
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
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
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
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
            Text(
              '$rate%',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
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
