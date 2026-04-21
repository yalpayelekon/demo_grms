import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
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
              final contentWidth = constraints.maxWidth;
              final contentHeight = constraints.maxHeight;
              final canUseFixedDesktopGrid =
                  contentWidth >= 1400 && contentHeight >= 760;
              final canUseFixedTabletGrid =
                  contentWidth >= 900 && contentHeight >= 620;
              final useCompactCards =
                  contentHeight <= 900 || contentWidth <= 1400;
              final useUltraCompactCards =
                  contentHeight <= 760 || contentWidth < 1200;
              final useTightTabletSpacing =
                  contentHeight <= 760 || contentWidth < 1320;
              final canUseFixedGrid =
                  canUseFixedDesktopGrid || canUseFixedTabletGrid;

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
        final crossAxisCount = pinToViewport ? 3 : (constraints.maxWidth >= 850 ? 2 : 1);
        final spacing = useTightTabletSpacing ? 12.0 : 16.0;
        final rowCount = (cards.length / crossAxisCount).ceil();
        final usableWidth = math.max(
          1.0,
          constraints.maxWidth - (spacing * (crossAxisCount - 1)),
        );
        final tileWidth = usableWidth / crossAxisCount;
        final tileHeight = pinToViewport
            ? math.max(
                1.0,
                (constraints.maxHeight - (spacing * (rowCount - 1))) / rowCount,
              )
            : tileWidth / (useUltraCompactCards ? 1.18 : 1.28);

        return GridView.builder(
          shrinkWrap: !pinToViewport,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: tileWidth / tileHeight,
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
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: compact ? 6 : 8,
              crossAxisSpacing: compact ? 6 : 8,
              childAspectRatio: compact ? 2.6 : 2.8,
              children: sortedStats.map((stat) {
                return _AlarmCategoryCard(
                  label: stat.label,
                  count: stat.count,
                  totalRooms: totalRooms,
                  icon: _alarmIconForLabel(stat.label),
                  compact: compact,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  IconData _alarmIconForLabel(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('door')) return Icons.door_front_door_outlined;
    if (normalized.contains('lighting')) return Icons.lightbulb_outline;
    if (normalized.contains('hvac')) return Icons.ac_unit;
    if (normalized.contains('rcu')) return Icons.memory_outlined;
    if (normalized.contains('pms')) return Icons.meeting_room_outlined;
    if (normalized.contains('inact')) return Icons.hourglass_empty;
    return Icons.warning_amber_rounded;
  }
}

class _AlarmCategoryCard extends StatelessWidget {
  final String label;
  final int count;
  final int? totalRooms;
  final IconData? icon;
  final String? imageAssetPath;
  final bool compact;
  final bool tightHeight;

  const _AlarmCategoryCard({
    required this.label,
    required this.count,
    this.totalRooms,
    this.icon,
    this.imageAssetPath,
    this.compact = false,
    this.tightHeight = false,
  }) : assert(icon != null || imageAssetPath != null);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: tightHeight ? (compact ? 3 : 4) : (compact ? 5 : 6),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (imageAssetPath != null)
                  Image.asset(
                    imageAssetPath!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  )
                else
                  Icon(icon, size: compact ? 25 : 28, color: Colors.white70),
                SizedBox(width: compact ? 4 : 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            totalRooms == null ? count.toString() : '$count / $totalRooms',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 12 : 13,
            ),
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
            'Rented % ${stats.rentedRate}',
            style: TextStyle(
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text(
            'Total rented ratio',
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
            mainAxisSpacing: compact ? 4 : 6,
            crossAxisSpacing: compact ? 6 : 8,
            childAspectRatio: compact ? 3.0 : 3.2,
            children: stats.roomStatusStats.asMap().entries.map((entry) {
              final statusStat = entry.value;
              return _AlarmCategoryCard(
                label: statusStat.label,
                count: statusStat.rooms,
                totalRooms: stats.totalRooms,
                imageAssetPath: _occupancyAssetForLabel(statusStat.label),
                compact: compact,
                tightHeight: true,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _occupancyAssetForLabel(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('unrented') && normalized.contains('hk')) {
      return 'assets/images/room_status/whitehousekeeping.png';
    }
    if (normalized.contains('unrented') && normalized.contains('vacant')) {
      return 'assets/images/room_status/white.png';
    }
    if (normalized.contains('rented') && normalized.contains('occupied')) {
      return 'assets/images/room_status/greenadamvaliz.png';
    }
    if (normalized.contains('rented') && normalized.contains('hk')) {
      return 'assets/images/room_status/greenhousekeeping.png';
    }
    if (normalized.contains('rented') && normalized.contains('vacant')) {
      return 'assets/images/room_status/greenvaliz.png';
    }
    if (normalized.contains('malfunction')) {
      return 'assets/images/room_status/redadamvaliz.png';
    }
    return 'assets/images/room_status/white.png';
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: compact ? 4 : 6,
            crossAxisSpacing: compact ? 6 : 8,
            childAspectRatio: compact ? 3.0 : 3.2,
            children: [
              _ServiceCompactCard(
                label: 'DND',
                valueText: stats.dndCount.toString(),
                icon: Icons.do_not_disturb_on_outlined,
                compact: compact,
              ),
              _ServiceCompactCard(
                label: 'Laundry',
                valueText: stats.lndCount.toString(),
                icon: Icons.local_laundry_service_outlined,
                compact: compact,
              ),
              _ServiceCompactCard(
                label: 'Make Up Room',
                valueText: stats.murCount.toString(),
                icon: Icons.cleaning_services_outlined,
                compact: compact,
              ),
              _ServiceCompactCard(
                label: 'Delayed',
                valueText: stats.delayedCount.toString(),
                icon: Icons.schedule_outlined,
                compact: compact,
              ),
              _ServiceCompactCard(
                label: 'In Progress',
                valueText: stats.inProgressCount.toString(),
                icon: Icons.sync_outlined,
                compact: compact,
              ),
              _ServiceCompactCard(
                label: 'Avg Response Time',
                valueText: '${stats.averageServiceRequestMinutes} min',
                icon: Icons.timer_outlined,
                compact: compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceCompactCard extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final bool compact;

  const _ServiceCompactCard({
    required this.label,
    required this.valueText,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: compact ? 25 : 28, color: Colors.white70),
                SizedBox(width: compact ? 4 : 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            valueText,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 12 : 13,
            ),
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
        childAspectRatio: compact ? 1.8 : 2.1,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hvacIconForLabel(stat.label),
                      size: compact ? 34 : 36,
                      color: Colors.white70,
                    ),
                    SizedBox(width: compact ? 4 : 6),
                    Text(
                      stat.label,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: compact ? 10 : 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${stat.rooms} / $totalRooms',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 20 : 22,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _hvacIconForLabel(String label) {
    if (label == 'Cooling') return Icons.ac_unit;
    if (label == 'Idle') return Icons.pause_circle_outline;
    if (label == 'Heating') return Icons.local_fire_department_outlined;
    return Icons.power_settings_new;
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
                Icon(Icons.circle, size: 25, color: color),
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
