import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../widgets/chart_utils.dart' as cu;
import '../services/avg_day.dart' as avg;
import '../models/chart_models.dart';
import 'dart:math' as math;

class AverageDayChart extends StatelessWidget {
  final List<ChartBp> series;
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  final bool showSys;
  final bool showDia;
  final bool distribution; // median + IQR band per bin across days
  final List<ChartSecSample> secondarySamples;
  final String secondaryLabel;
  const AverageDayChart({
    super.key,
    required this.series,
    this.anchorMinute,
    this.showBands = false,
    this.showSys = true,
    this.showDia = true,
    this.distribution = false,
    this.secondarySamples = const [],
    this.secondaryLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final agg =
        avg.AverageDayAggregator(
          series: series
              .map((e) => avg.AvgBpInput(t: e.t, sbp: e.sbp, dbp: e.dbp))
              .toList(),
        ).compute(
          stepMinutes: 15,
          smoothMinutes: 45,
          anchorMinute: anchorMinute,
          withBands: showBands,
        );
    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    final sysQ50 = <FlSpot>[];
    final sysQ25 = <FlSpot>[];
    final sysQ75 = <FlSpot>[];
    final diaQ50 = <FlSpot>[];
    final diaQ25 = <FlSpot>[];
    final diaQ75 = <FlSpot>[];
    for (int i = 0; i < agg.minutes.length; i++) {
      final x = agg.minutes[i] / 60.0; // hours
      final s = agg.sysMean[i];
      final d = agg.diaMean[i];
      if (s != null) sysSpots.add(FlSpot(x, s));
      if (d != null) diaSpots.add(FlSpot(x, d));
      if (agg.sysQ50?[i] != null) sysQ50.add(FlSpot(x, agg.sysQ50![i]!));
      if (agg.sysQ25?[i] != null) sysQ25.add(FlSpot(x, agg.sysQ25![i]!));
      if (agg.sysQ75?[i] != null) sysQ75.add(FlSpot(x, agg.sysQ75![i]!));
      if (agg.diaQ50?[i] != null) diaQ50.add(FlSpot(x, agg.diaQ50![i]!));
      if (agg.diaQ25?[i] != null) diaQ25.add(FlSpot(x, agg.diaQ25![i]!));
      if (agg.diaQ75?[i] != null) diaQ75.add(FlSpot(x, agg.diaQ75![i]!));
    }
    final sysLower = <FlSpot>[];
    final sysUpper = <FlSpot>[];
    final diaLower = <FlSpot>[];
    final diaUpper = <FlSpot>[];
    if (showBands && agg.sysLower != null) {
      for (int i = 0; i < agg.minutes.length; i++) {
        final x = agg.minutes[i] / 60.0;
        final loS = agg.sysLower![i];
        final hiS = agg.sysUpper![i];
        final loD = agg.diaLower![i];
        final hiD = agg.diaUpper![i];
        if (loS != null) sysLower.add(FlSpot(x, loS));
        if (hiS != null) sysUpper.add(FlSpot(x, hiS));
        if (loD != null) diaLower.add(FlSpot(x, loD));
        if (hiD != null) diaUpper.add(FlSpot(x, hiD));
      }
    }

    final bars = <LineChartBarData>[];
    if (showBands && sysLower.isNotEmpty && sysUpper.isNotEmpty) {
      bars.addAll([
        LineChartBarData(
          spots: sysLower,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: sysUpper,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
      ]);
    }
    if (showBands && diaLower.isNotEmpty && diaUpper.isNotEmpty) {
      bars.addAll([
        LineChartBarData(
          spots: diaLower,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: diaUpper,
          isCurved: true,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        ),
      ]);
    }
    if (!distribution && showSys) {
      bars.add(
        LineChartBarData(
          spots: sysSpots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: Colors.red,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      );
    }
    if (!distribution && showDia) {
      bars.add(
        LineChartBarData(
          spots: diaSpots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: Colors.blue,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    // Distribution mode: IQR bands and median lines
    if (distribution) {
      if (showSys && sysQ50.isNotEmpty) {
        if (sysQ25.isNotEmpty && sysQ75.isNotEmpty) {
          bars.addAll([
            LineChartBarData(
              spots: sysQ25,
              isCurved: true,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: sysQ75,
              isCurved: true,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: sysQ50,
              isCurved: true,
              color: Colors.red,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ]);
        } else {
          bars.add(
            LineChartBarData(
              spots: sysQ50,
              isCurved: true,
              color: Colors.red,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          );
        }
      }
      if (showDia && diaQ50.isNotEmpty) {
        if (diaQ25.isNotEmpty && diaQ75.isNotEmpty) {
          bars.addAll([
            LineChartBarData(
              spots: diaQ25,
              isCurved: true,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: diaQ75,
              isCurved: true,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: diaQ50,
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ]);
        } else {
          bars.add(
            LineChartBarData(
              spots: diaQ50,
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          );
        }
      }

      // Overlay raw reading dots (smaller than Trend)
      if (showSys) {
        final rawSys = <FlSpot>[];
        for (final e in series) {
          final t = e.t;
          if (t == null || e.sbp == null) continue;
          var m = t.hour * 60 + t.minute + t.second / 60.0;
          if (anchorMinute != null) {
            m = (m - anchorMinute!) % 1440;
            if (m < 0) m += 1440;
          }
          rawSys.add(FlSpot(m / 60.0, e.sbp!));
        }
        if (rawSys.isNotEmpty) {
          bars.add(
            LineChartBarData(
              spots: rawSys,
              isCurved: false,
              color: Colors.red.withValues(alpha: 0.25),
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 1.5,
                  color: Colors.red.withValues(alpha: 0.35),
                  strokeWidth: 0,
                ),
              ),
            ),
          );
        }
      }
      if (showDia) {
        final rawDia = <FlSpot>[];
        for (final e in series) {
          final t = e.t;
          if (t == null || e.dbp == null) continue;
          var m = t.hour * 60 + t.minute + t.second / 60.0;
          if (anchorMinute != null) {
            m = (m - anchorMinute!) % 1440;
            if (m < 0) m += 1440;
          }
          rawDia.add(FlSpot(m / 60.0, e.dbp!));
        }
        if (rawDia.isNotEmpty) {
          bars.add(
            LineChartBarData(
              spots: rawDia,
              isCurved: false,
              color: Colors.blue.withValues(alpha: 0.25),
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 1.5,
                  color: Colors.blue.withValues(alpha: 0.35),
                  strokeWidth: 0,
                ),
              ),
            ),
          );
        }
      }
    }

    // Secondary series mapping
    List<FlSpot> secSpots = [];
    double? secMin, secMax;
    List<double?> secSeriesVals = List<double?>.filled(
      agg.minutes.length,
      null,
    );
    if (secondarySamples.isNotEmpty) {
      if (secondaryLabel == 'steps') {
        final sums = List<double>.filled(agg.minutes.length, 0.0);
        final mins = List<double>.filled(agg.minutes.length, 0.0);
        for (final s in secondarySamples) {
          final start = s.start ?? s.t.subtract(const Duration(minutes: 1));
          final end = s.end ?? s.t;
          double steps = s.v;
          final totalMin = (end.difference(start).inSeconds / 60.0).clamp(
            0.0,
            1440.0,
          );
          if (totalMin <= 0) {
            var m = s.t.hour * 60 + s.t.minute + s.t.second / 60.0;
            if (anchorMinute != null) {
              m = (m - anchorMinute!) % 1440;
              if (m < 0) m += 1440;
            }
            final idx = (m / 15).floor().clamp(0, agg.minutes.length - 1);
            sums[idx] += steps;
            mins[idx] += 15.0;
            continue;
          }
          DateTime cur = start;
          while (cur.isBefore(end)) {
            final binStartMin = ((cur.hour * 60 + cur.minute) ~/ 15) * 15;
            int binIdx;
            if (anchorMinute != null) {
              int anchored = (binStartMin - anchorMinute!) % 1440;
              if (anchored < 0) anchored += 1440;
              binIdx = (anchored / 15).floor();
            } else {
              binIdx = (binStartMin / 15).floor();
            }
            binIdx = binIdx.clamp(0, agg.minutes.length - 1);
            final binStart = DateTime(
              cur.year,
              cur.month,
              cur.day,
              binStartMin ~/ 60,
              binStartMin % 60,
            );
            final binEnd = binStart.add(const Duration(minutes: 15));
            final segEnd = end.isBefore(binEnd) ? end : binEnd;
            final overlap = (segEnd.difference(cur).inSeconds / 60.0).clamp(
              0.0,
              15.0,
            );
            if (overlap > 0) {
              final frac = overlap / (totalMin <= 0 ? overlap : totalMin);
              sums[binIdx] += steps * frac;
              mins[binIdx] += overlap;
            }
            cur = segEnd;
          }
        }
        for (int i = 0; i < agg.minutes.length; i++) {
          final m = mins[i];
          if (m > 0) secSeriesVals[i] = sums[i] / m;
        }
        secMin = 0;
        final ys = secSeriesVals.whereType<double>().toList();
        if (ys.isNotEmpty) secMax = ys.reduce(math.max);
      } else if (secondaryLabel == 'sleep') {
        final asleepMin = List<double>.filled(agg.minutes.length, 0.0);
        for (final s in secondarySamples) {
          final start = s.start ?? s.t.subtract(const Duration(minutes: 1));
          final end = s.end ?? s.t;
          DateTime cur = start;
          while (cur.isBefore(end)) {
            final binStartMin = ((cur.hour * 60 + cur.minute) ~/ 15) * 15;
            int binIdx;
            if (anchorMinute != null) {
              int anchored = (binStartMin - anchorMinute!) % 1440;
              if (anchored < 0) anchored += 1440;
              binIdx = (anchored / 15).floor();
            } else {
              binIdx = (binStartMin / 15).floor();
            }
            binIdx = binIdx.clamp(0, agg.minutes.length - 1);
            final binStart = DateTime(
              cur.year,
              cur.month,
              cur.day,
              binStartMin ~/ 60,
              binStartMin % 60,
            );
            final binEnd = binStart.add(const Duration(minutes: 15));
            final segEnd = end.isBefore(binEnd) ? end : binEnd;
            final overlap = (segEnd.difference(cur).inSeconds / 60.0).clamp(
              0.0,
              15.0,
            );
            if (overlap > 0) {
              asleepMin[binIdx] += overlap;
            }
            cur = segEnd;
          }
        }
        for (int i = 0; i < agg.minutes.length; i++) {
          if (asleepMin[i] > 0) {
            secSeriesVals[i] = (asleepMin[i] / 15.0).clamp(0.0, 1.0);
          }
        }
        secMin = 0;
        secMax = 1;
      } else {
        final bins = List.generate(agg.minutes.length, (_) => <double>[]);
        for (final s in secondarySamples) {
          var m = s.t.hour * 60 + s.t.minute + s.t.second / 60.0;
          if (anchorMinute != null) {
            m = (m - anchorMinute!) % 1440;
            if (m < 0) m += 1440;
          }
          final idx = (m / 15).floor().clamp(0, agg.minutes.length - 1);
          bins[idx].add(s.v);
        }
        for (int i = 0; i < bins.length; i++) {
          final b = bins[i];
          if (b.isNotEmpty) {
            secSeriesVals[i] = b.reduce((a, b) => a + b) / b.length;
          }
        }
        final ys = secSeriesVals.whereType<double>().toList();
        if (ys.isNotEmpty) {
          secMin = ys.reduce(math.min);
          secMax = ys.reduce(math.max);
        }
      }

      final leftMin = _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots]);
      final leftMax = _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots]);
      final leftRange = (leftMax - leftMin).abs() < 1e-6
          ? 1.0
          : (leftMax - leftMin);
      final secRange =
          (secMax != null && secMin != null && (secMax - secMin).abs() >= 1e-6)
          ? (secMax - secMin)
          : 1.0;
      for (int i = 0; i < secSeriesVals.length; i++) {
        final v = secSeriesVals[i];
        if (v == null) continue;
        final x = agg.minutes[i] / 60.0;
        final y = leftMin + (v - (secMin ?? 0)) * leftRange / secRange;
        secSpots.add(FlSpot(x, y));
      }
    }

    final minY =
        _autoMinY([
          if (!distribution && showSys) sysSpots,
          if (!distribution && showDia) diaSpots,
          if (distribution && showSys) sysQ25.isNotEmpty ? sysQ25 : sysQ50,
          if (distribution && showDia) diaQ25.isNotEmpty ? diaQ25 : diaQ50,
        ]) -
        10;
    final maxY =
        _autoMaxY([
          if (!distribution && showSys) sysSpots,
          if (!distribution && showDia) diaSpots,
          if (distribution && showSys) sysQ75.isNotEmpty ? sysQ75 : sysQ50,
          if (distribution && showDia) diaQ75.isNotEmpty ? diaQ75 : diaQ50,
        ]) +
        10;

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 20,
            ),
            axisNameWidget: const Text('mmHg'),
            axisNameSize: 18,
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3,
              getTitlesWidget: _hourTick,
            ),
            axisNameWidget: Text('Time of Day'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          ...bars,
          if (secSpots.isNotEmpty)
            LineChartBarData(
              spots: secSpots,
              isCurved: true,
              color: Colors.purple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
        ],
        betweenBarsData: [
          if (!distribution &&
              showBands &&
              sysLower.isNotEmpty &&
              sysUpper.isNotEmpty)
            BetweenBarsData(
              fromIndex: 0,
              toIndex: 1,
              color: const Color(0x26F44336),
            ),
          if (!distribution &&
              showBands &&
              diaLower.isNotEmpty &&
              diaUpper.isNotEmpty)
            BetweenBarsData(
              fromIndex: 2,
              toIndex: 3,
              color: const Color(0x1F2196F3),
            ),
          if (distribution && showSys && sysQ25.isNotEmpty && sysQ75.isNotEmpty)
            BetweenBarsData(
              fromIndex: bars.length - (showDia ? 6 : 3),
              toIndex: bars.length - (showDia ? 5 : 2),
              color: const Color(0x26F44336),
            ),
          if (distribution && showDia && diaQ25.isNotEmpty && diaQ75.isNotEmpty)
            BetweenBarsData(
              fromIndex: bars.length - 3,
              toIndex: bars.length - 2,
              color: const Color(0x1F2196F3),
            ),
        ],
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black12),
            bottom: BorderSide(color: Colors.black12),
          ),
        ),
        rangeAnnotations: cu.zoneAnnotations(
          showSys: showSys,
          showDia: showDia,
          enabled: false,
        ),
      ),
    );

    if (secSpots.isEmpty) return chart;

    // Overlay right-axis labels
    String fmtTick(double v) => secondaryLabel == 'sleep'
        ? (v * 100).round().toString()
        : v.round().toString();
    final ticks = <double>[];
    final tickVals = <String>[];
    final leftRange = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
    if (secMin != null && secMax != null) {
      for (int i = 0; i <= 4; i++) {
        final yLeft = minY + leftRange * (i / 4);
        final secVal =
            (secMin) + (yLeft - minY) * (secMax - secMin) / leftRange;
        ticks.add(yLeft);
        tickVals.add(fmtTick(secVal));
      }
    }

    return Stack(
      children: [
        Positioned.fill(child: chart),
        if (ticks.isNotEmpty)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(right: 2, top: 4, bottom: 18),
              child: Stack(
                children: [
                  for (int i = 0; i < tickVals.length; i++)
                    Align(
                      alignment: Alignment(
                        1,
                        1 -
                            2 *
                                (((ticks[i] - minY) / (maxY - minY)).clamp(
                                  0.0,
                                  1.0,
                                )),
                      ),
                      child: Text(
                        secondaryLabel == 'sleep'
                            ? '${tickVals[i]}%'
                            : tickVals[i],
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.purple,
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

  static Widget _hourTick(double value, TitleMeta meta) =>
      SideTitleWidget(meta: meta, child: Text('${value.round()}h'));

  double _autoMinY(List<List<FlSpot>> lists) {
    double m = 300;
    for (final l in lists) {
      for (final p in l) {
        if (p.y < m) m = p.y;
      }
    }
    if (m == 300) m = 40;
    return m.clamp(40.0, 300.0);
  }

  double _autoMaxY(List<List<FlSpot>> lists) {
    double m = 0;
    for (final l in lists) {
      for (final p in l) {
        if (p.y > m) m = p.y;
      }
    }
    if (m == 0) m = 200;
    return m.clamp(60.0, 300.0);
  }
}

// Secondary samples are provided via ChartSecSample
