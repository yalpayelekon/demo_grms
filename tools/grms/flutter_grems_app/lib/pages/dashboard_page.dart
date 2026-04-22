import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../providers/dashboard_provider.dart';
import '../providers/hotel_status_provider.dart';
import '../providers/room_service_provider.dart';
import '../providers/coordinates_sync_provider.dart';
import '../models/dashboard_models.dart';
import '../widgets/energy_savings_chart.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  _DashboardViewportInfo? _viewportInfo;

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final stats = dashboardState.stats;
    final hotelSync = ref.watch(demoRoomHotelSyncStatusProvider);
    final serviceSync = ref.watch(demoRoomServiceSyncStatusProvider);
    final coordinatesSync = ref.watch(coordinatesSyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: _DashboardDebugTitle(info: _viewportInfo),
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
              final viewportInfo = _DashboardViewportInfo.fromConstraints(
                constraints,
              );
              _syncViewportInfo(viewportInfo);
              return Padding(
                padding: EdgeInsets.all(
                  viewportInfo.useTightTabletSpacing ? 18.0 : 24.0,
                ),
                child: viewportInfo.canUseFixedGrid
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
                              useCompactCards: viewportInfo.useCompactCards,
                              useUltraCompactCards:
                                  viewportInfo.useUltraCompactCards,
                              useTightTabletSpacing:
                                  viewportInfo.useTightTabletSpacing,
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
                                useUltraCompactCards:
                                    viewportInfo.useUltraCompactCards,
                                useTightTabletSpacing:
                                    viewportInfo.useTightTabletSpacing,
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

  void _syncViewportInfo(_DashboardViewportInfo nextInfo) {
    if (_viewportInfo == nextInfo) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewportInfo == nextInfo) {
        return;
      }
      setState(() {
        _viewportInfo = nextInfo;
      });
    });
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = pinToViewport
            ? 3
            : (constraints.maxWidth >= 850 ? 2 : 1);
        final desktopFontDelta =
            pinToViewport &&
                constraints.maxWidth >= 1400 &&
                !useUltraCompactCards
            ? 2.0
            : 0.0;
        final cardTextScale =
            pinToViewport &&
                constraints.maxWidth >= 1400 &&
                !useUltraCompactCards
            ? 1.4
            : 1.0;
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
            desktopFontDelta: desktopFontDelta,
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
            desktopFontDelta: desktopFontDelta,
          ),
          _ServicePanel(
            stats: stats,
            compact: useCompactCards,
            ultraCompact: useUltraCompactCards,
            desktopFontDelta: desktopFontDelta,
          ),
          _EnergyPanel(
            compact: useCompactCards,
            ultraCompact: useUltraCompactCards,
            desktopFontDelta: desktopFontDelta,
          ),
        ];
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
          itemBuilder: (context, index) =>
              _ScaledCardText(scale: cardTextScale, child: cards[index]),
        );
      },
    );
  }
}

class _ScaledCardText extends StatelessWidget {
  final double scale;
  final Widget child;

  const _ScaledCardText({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) {
      return child;
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    );
  }
}

class _DashboardDebugTitle extends StatelessWidget {
  final _DashboardViewportInfo? info;

  const _DashboardDebugTitle({required this.info});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          info?.summaryLabel ?? 'Dashboard',
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DashboardViewportInfo {
  final double width;
  final double height;
  final bool canUseFixedDesktopGrid;
  final bool canUseFixedTabletGrid;
  final bool useCompactCards;
  final bool useUltraCompactCards;
  final bool useTightTabletSpacing;

  const _DashboardViewportInfo({
    required this.width,
    required this.height,
    required this.canUseFixedDesktopGrid,
    required this.canUseFixedTabletGrid,
    required this.useCompactCards,
    required this.useUltraCompactCards,
    required this.useTightTabletSpacing,
  });

  factory _DashboardViewportInfo.fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final canUseClassicTabletGrid = width >= 800 && height >= 600;
    final canUseShortLandscapeTabletGrid = width >= 900 && height >= 500;
    return _DashboardViewportInfo(
      width: width,
      height: height,
      canUseFixedDesktopGrid: width >= 1400 && height >= 760,
      canUseFixedTabletGrid:
          canUseClassicTabletGrid || canUseShortLandscapeTabletGrid,
      useCompactCards: height <= 900 || width <= 1400,
      useUltraCompactCards: height <= 760 || width < 1200,
      useTightTabletSpacing: height <= 760 || width < 1320,
    );
  }

  bool get canUseFixedGrid => canUseFixedDesktopGrid || canUseFixedTabletGrid;

  String get modeLabel {
    if (canUseFixedDesktopGrid) {
      return 'Desktop';
    }
    if (canUseFixedTabletGrid) {
      return 'Tablet';
    }
    return 'Mobile';
  }

  String get cardDensityLabel {
    if (useUltraCompactCards) {
      return 'Ultra';
    }
    if (useCompactCards) {
      return 'Compact';
    }
    return 'Regular';
  }

  String get spacingLabel => useTightTabletSpacing ? 'Tight' : 'Regular';

  String get gridLabel => canUseFixedGrid ? '3x2 fixed' : 'scroll';

  String get summaryLabel =>
      '${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)} | '
      '$modeLabel | $gridLabel | $cardDensityLabel | $spacingLabel';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _DashboardViewportInfo &&
        other.width.round() == width.round() &&
        other.height.round() == height.round() &&
        other.canUseFixedDesktopGrid == canUseFixedDesktopGrid &&
        other.canUseFixedTabletGrid == canUseFixedTabletGrid &&
        other.useCompactCards == useCompactCards &&
        other.useUltraCompactCards == useUltraCompactCards &&
        other.useTightTabletSpacing == useTightTabletSpacing;
  }

  @override
  int get hashCode => Object.hash(
    width.round(),
    height.round(),
    canUseFixedDesktopGrid,
    canUseFixedTabletGrid,
    useCompactCards,
    useUltraCompactCards,
    useTightTabletSpacing,
  );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool compact;
  final bool ultraCompact;
  final bool expandChild;

  const _GlassCard({
    required this.child,
    required this.title,
    this.subtitle,
    this.trailing,
    this.compact = false,
    this.ultraCompact = false,
    this.expandChild = false,
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
            if (expandChild) Expanded(child: child) else child,
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
  final double desktopFontDelta;
  const _AlarmPanel({
    required this.stats,
    required this.totalRooms,
    this.compact = false,
    this.ultraCompact = false,
    this.desktopFontDelta = 0,
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
                  fontSize: (compact ? 12 : 13) + desktopFontDelta,
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
                  desktopFontDelta: desktopFontDelta,
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
  final double desktopFontDelta;

  const _AlarmCategoryCard({
    required this.label,
    required this.count,
    this.totalRooms,
    this.icon,
    this.imageAssetPath,
    this.compact = false,
    this.tightHeight = false,
    this.desktopFontDelta = 0,
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
                      fontSize: (compact ? 9 : 10) + desktopFontDelta,
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
              fontSize: (compact ? 12 : 13) + desktopFontDelta,
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
  final double desktopFontDelta;
  const _OccupancyPanel({
    required this.stats,
    this.compact = false,
    this.ultraCompact = false,
    this.desktopFontDelta = 0,
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
              fontSize: compact ? 16 : 20,
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
                desktopFontDelta: desktopFontDelta,
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
  final double desktopFontDelta;
  const _ServicePanel({
    required this.stats,
    this.compact = false,
    this.ultraCompact = false,
    this.desktopFontDelta = 0,
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
                desktopFontDelta: desktopFontDelta,
              ),
              _ServiceCompactCard(
                label: 'Laundry',
                valueText: stats.lndCount.toString(),
                icon: Icons.local_laundry_service_outlined,
                compact: compact,
                desktopFontDelta: desktopFontDelta,
              ),
              _ServiceCompactCard(
                label: 'Make Up Room',
                valueText: stats.murCount.toString(),
                icon: Icons.cleaning_services_outlined,
                compact: compact,
                desktopFontDelta: desktopFontDelta,
              ),
              _ServiceCompactCard(
                label: 'Delayed',
                valueText: stats.delayedCount.toString(),
                icon: Icons.schedule_outlined,
                compact: compact,
                desktopFontDelta: desktopFontDelta,
              ),
              _ServiceCompactCard(
                label: 'In Progress',
                valueText: stats.inProgressCount.toString(),
                icon: Icons.sync_outlined,
                compact: compact,
                desktopFontDelta: desktopFontDelta,
              ),
              _ServiceCompactCard(
                label: 'Avg Response Time',
                valueText: '${stats.averageServiceRequestMinutes} min',
                icon: Icons.timer_outlined,
                compact: compact,
                desktopFontDelta: desktopFontDelta,
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
  final double desktopFontDelta;

  const _ServiceCompactCard({
    required this.label,
    required this.valueText,
    required this.icon,
    this.compact = false,
    this.desktopFontDelta = 0,
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
                      fontSize: (compact ? 9 : 10) + desktopFontDelta,
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
              fontSize: (compact ? 12 : 13) + desktopFontDelta,
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
  final bool compact;
  final bool ultraCompact;
  final double desktopFontDelta;

  const _EnergyPanel({
    this.compact = false,
    this.ultraCompact = false,
    this.desktopFontDelta = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hideSummaryMetrics = ultraCompact;

    return _GlassCard(
      title: 'Energy Consumption',
      subtitle: 'Energy saving trend',
      compact: compact,
      ultraCompact: ultraCompact,
      expandChild: true,
      trailing: hideSummaryMetrics
          ? _EnergySummaryInfoButton(compact: compact)
          : null,
      child: Column(
        children: [
          if (!hideSummaryMetrics) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _EnergyLegendItem(
                  label: 'Total',
                  value: '148 kWh',
                  compact: compact,
                  desktopFontDelta: desktopFontDelta,
                ),
                _EnergyLegendItem(
                  label: 'Peak',
                  value: '182 kWh',
                  compact: compact,
                  desktopFontDelta: desktopFontDelta,
                ),
                _EnergyLegendItem(
                  label: 'Off-Peak',
                  value: '96 kWh',
                  compact: compact,
                  desktopFontDelta: desktopFontDelta,
                ),
              ],
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: ultraCompact ? 0 : 4),
              child: EnergySavingsChart(
                compactMode: ultraCompact,
                desktopFontDelta: desktopFontDelta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnergySummaryInfoButton extends StatelessWidget {
  final bool compact;

  const _EnergySummaryInfoButton({required this.compact});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF232A3A),
            title: const Text(
              'Energy Summary',
              style: TextStyle(color: Colors.white),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EnergySummaryDialogRow(label: 'Total', value: '148 kWh'),
                SizedBox(height: 12),
                _EnergySummaryDialogRow(label: 'Peak', value: '182 kWh'),
                SizedBox(height: 12),
                _EnergySummaryDialogRow(label: 'Off-Peak', value: '96 kWh'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: compact ? 28 : 32,
        height: compact ? 28 : 32,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(
          Icons.info_outline,
          size: compact ? 16 : 18,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _EnergySummaryDialogRow extends StatelessWidget {
  final String label;
  final String value;

  const _EnergySummaryDialogRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
  final double desktopFontDelta;
  const _EnergyLegendItem({
    required this.label,
    required this.value,
    this.compact = false,
    this.desktopFontDelta = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white54,
            fontSize: (compact ? 10 : 11) + desktopFontDelta,
          ),
        ),
        SizedBox(height: compact ? 2 : 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: (compact ? 13 : 14) + desktopFontDelta,
          ),
        ),
      ],
    );
  }
}
