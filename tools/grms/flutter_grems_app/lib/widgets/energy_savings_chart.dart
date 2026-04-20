import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

enum DateRange { lastWeek, lastMonth, lastYear }

class EnergySavingsChart extends StatefulWidget {
  const EnergySavingsChart({super.key});

  @override
  State<EnergySavingsChart> createState() => _EnergySavingsChartState();
}

class _EnergySavingsChartState extends State<EnergySavingsChart> {
  DateRange _dateRange = DateRange.lastYear;
  late List<_EnergyData> _data;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _generateData();
  }

  void _generateData() {
    final result = <_EnergyData>[];
    final today = DateTime.now();
    final baseValue = _dateRange == DateRange.lastWeek ? 120.0 : _dateRange == DateRange.lastMonth ? 145.0 : 170.0;
    final randomRange = _dateRange == DateRange.lastWeek ? 25.0 : _dateRange == DateRange.lastMonth ? 35.0 : 40.0;

    if (_dateRange == DateRange.lastWeek) {
      double previousValue = baseValue;
      for (int i = 6; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        final seasonal = _getSeasonalAdjustment(d.month);
        final trend = (6 - i) * 3.0;
        final variation = (_random.nextDouble() - 0.5) * randomRange;
        final momentum = (previousValue - baseValue) * 0.3;
        final consumption = baseValue + trend + variation + momentum + seasonal;
        final savingsRatio = 0.17 + _random.nextDouble() * 0.16;
        final savings = max(12.0, consumption * savingsRatio);
        previousValue = consumption;
        result.add(_EnergyData(
          label: DateFormat('E').format(d),
          consumption: consumption,
          savings: savings,
        ));
      }
    } else if (_dateRange == DateRange.lastMonth) {
      double previousValue = baseValue;
      for (int i = 29; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        final seasonal = _getSeasonalAdjustment(d.month);
        final trend = (29 - i) * 1.2;
        final variation = (_random.nextDouble() - 0.5) * randomRange;
        final momentum = (previousValue - baseValue) * 0.2;
        final consumption = baseValue + trend + variation + momentum + seasonal;
        final savingsRatio = 0.16 + _random.nextDouble() * 0.15;
        final savings = max(10.0, consumption * savingsRatio);
        previousValue = consumption;
        result.add(_EnergyData(
          label: d.day.toString(),
          consumption: consumption,
          savings: savings,
        ));
      }
    } else {
      double previousValue = baseValue;
      for (int i = 11; i >= 0; i--) {
        final d = DateTime(today.year, today.month - i, 1);
        final seasonal = _getSeasonalAdjustment(d.month);
        final trend = i * 4.0;
        final variation = (_random.nextDouble() - 0.5) * randomRange;
        final momentum = (previousValue - baseValue) * 0.25;
        final consumption = baseValue + trend + variation + momentum + seasonal;
        final savingsRatio = 0.15 + _random.nextDouble() * 0.14;
        final savings = max(8.0, consumption * savingsRatio);
        previousValue = consumption;
        result.add(_EnergyData(
          label: DateFormat('MMM').format(d),
          consumption: consumption,
          savings: savings,
        ));
      }
    }
    setState(() {
      _data = result;
    });
  }

  double _getSeasonalAdjustment(int month) {
    if (month == 12 || month == 1 || month == 2) return 35;
    if (month >= 6 && month <= 8) return -25;
    if (month >= 3 && month <= 5) return 12;
    return 7;
  }

  @override
  Widget build(BuildContext context) {
    final maxSeriesValue = _data
        .map((entry) => max(entry.consumption, entry.savings))
        .reduce(max);
    final chartMaxY = ((maxSeriesValue * 1.25) / 20).ceil() * 20.0;
    final yInterval = _getYInterval(chartMaxY);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildSelector('Week', DateRange.lastWeek),
            _buildSelector('Month', DateRange.lastMonth),
            _buildSelector('Year', DateRange.lastYear),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SeriesLegend(color: Color(0xFF47A3FF), label: 'Consumed'),
            SizedBox(width: 16),
            _SeriesLegend(color: Color(0xFF36D084), label: 'Saved'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: _getInterval(),
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= _data.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _data[value.toInt()].label,
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: yInterval,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: chartMaxY,
              barGroups: _data.asMap().entries.map((entry) {
                final index = entry.key;
                final point = entry.value;
                return BarChartGroupData(
                  x: index,
                  barsSpace: 3,
                  barRods: [
                    BarChartRodData(
                      toY: point.consumption,
                      width: 6,
                      borderRadius: BorderRadius.circular(2),
                      color: const Color(0xFF47A3FF),
                    ),
                    BarChartRodData(
                      toY: point.savings,
                      width: 6,
                      borderRadius: BorderRadius.circular(2),
                      color: const Color(0xFF36D084),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  double _getInterval() {
    if (_dateRange == DateRange.lastMonth) return 5;
    return 1;
  }

  double _getYInterval(double maxY) {
    if (maxY <= 120) return 20;
    if (maxY <= 240) return 40;
    return 50;
  }

  Widget _buildSelector(String label, DateRange range) {
    final active = _dateRange == range;
    return GestureDetector(
      onTap: () {
        setState(() => _dateRange = range);
        _generateData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: active ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? Colors.blue : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.blue : Colors.white60,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _EnergyData {
  final String label;
  final double consumption;
  final double savings;

  const _EnergyData({
    required this.label,
    required this.consumption,
    required this.savings,
  });
}

class _SeriesLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _SeriesLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
