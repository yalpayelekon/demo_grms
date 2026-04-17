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
  DateRange _dateRange = DateRange.lastMonth;
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
        previousValue = consumption;
        result.add(_EnergyData(
          label: DateFormat('E').format(d),
          value: consumption,
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
        previousValue = consumption;
        result.add(_EnergyData(
          label: d.day.toString(),
          value: consumption,
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
        previousValue = consumption;
        result.add(_EnergyData(
          label: DateFormat('MMM').format(d),
          value: consumption,
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
        const SizedBox(height: 16),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 50,
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
                    interval: 50,
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
              minX: 0,
              maxX: _data.length.toDouble() - 1,
              minY: 0,
              maxY: 300,
              lineBarsData: [
                LineChartBarData(
                  spots: _data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList(),
                  isCurved: true,
                  gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [Colors.blue.withOpacity(0.3), Colors.blue.withOpacity(0)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
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
  final double value;
  const _EnergyData({required this.label, required this.value});
}
