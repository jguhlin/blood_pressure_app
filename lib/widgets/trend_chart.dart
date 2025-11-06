import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../widgets/chart_utils.dart' as cu;
import '../models/chart_models.dart';
import 'dart:math' as math;

class TrendChart extends StatelessWidget {
  final List<ChartBp> series;
  final DateTime start;
  final DateTime end;
  final bool showSys;
  final bool showDia;
  final bool distribution; // daily quantile bands
  final bool tooltipsEnabled;
  final String smoothingMethod; // 'ma' or 'ema'
  final bool smoothingEnabled;
  final int smoothingWindowDays;
  final List<ChartSecPoint> secondary;
  final String secondaryLabel;
  final bool showBands; // BP zone backgrounds
  final String zoneScheme; // 'acc_aha' or 'esc_esh'
  const TrendChart({
    super.key,
    required this.series,
    required this.start,
    required this.end,
    this.showSys = true,
    this.showDia = true,
    this.distribution = false,
    this.tooltipsEnabled = true,
    required this.smoothingMethod,
    this.smoothingEnabled = false,
    this.smoothingWindowDays = 7,
    this.secondary = const [],
    this.secondaryLabel = '',
    this.showBands = false,
    this.zoneScheme = 'acc_aha',
  });

  @override
  Widget build(BuildContext context) {
    DateTime effStart = start, effEnd = end;
    final times = series.where((e) => e.t != null).map((e) => e.t!).toList()
      ..sort();
    if (times.isNotEmpty) {
      if (times.first.isAfter(effStart)) {
        effStart = times.first;
      }
      if (times.last.isBefore(effEnd)) {
        effEnd = times.last;
      }
      if (!effEnd.isAfter(effStart)) {
        effEnd = effStart.add(const Duration(days: 1));
      }
    }
    double toX(DateTime t) => t.difference(effStart).inMinutes / 1440.0;

    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (final e in series) {
      final t = e.t;
      if (t == null) continue;
      final x = toX(t);
      if (showSys && e.sbp != null) sysSpots.add(FlSpot(x, e.sbp!));
      if (showDia && e.dbp != null) diaSpots.add(FlSpot(x, e.dbp!));
    }
    final maxX = effEnd
        .difference(effStart)
        .inDays
        .toDouble()
        .clamp(1.0, 365.0);

    // Distribution mode
    List<FlSpot> q50Sys = [], q25Sys = [], q75Sys = [];
    List<FlSpot> q50Dia = [], q25Dia = [], q75Dia = [];
    if (distribution) {
      final byDay = <DateTime, List<ChartBp>>{};
      for (final e in series) {
        if (e.t == null) continue;
        final day = DateTime(e.t!.year, e.t!.month, e.t!.day);
        (byDay[day] ??= []).add(e);
      }
      final days = <DateTime>[];
      DateTime cur = DateTime(effStart.year, effStart.month, effStart.day);
      final last = DateTime(effEnd.year, effEnd.month, effEnd.day);
      while (!cur.isAfter(last)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
      List<double?> mSys = List.filled(days.length, null),
          p25Sys = List.filled(days.length, null),
          p75SysL = List.filled(days.length, null);
      List<double?> mDia = List.filled(days.length, null),
          p25Dia = List.filled(days.length, null),
          p75DiaL = List.filled(days.length, null);
      for (int i = 0; i < days.length; i++) {
        final d = days[i];
        final list = byDay[d];
        if (list != null && showSys) {
          final vals =
              list.where((e) => e.sbp != null).map((e) => e.sbp!).toList()
                ..sort();
          if (vals.isNotEmpty) {
            mSys[i] = _q(vals, 0.5);
            p25Sys[i] = _q(vals, 0.25);
            p75SysL[i] = _q(vals, 0.75);
          }
        }
        if (list != null && showDia) {
          final vals =
              list.where((e) => e.dbp != null).map((e) => e.dbp!).toList()
                ..sort();
          if (vals.isNotEmpty) {
            mDia[i] = _q(vals, 0.5);
            p25Dia[i] = _q(vals, 0.25);
            p75DiaL[i] = _q(vals, 0.75);
          }
        }
      }
      void interp(List<double?> a) {
        int n = a.length;
        int i = 0;
        while (i < n) {
          if (a[i] != null) {
            i++;
            continue;
          }
          int j = i;
          while (j < n && a[j] == null) {
            j++;
          }
          double? left = i > 0 ? a[i - 1] : null;
          double? right = j < n ? a[j] : null;
          for (int k = i; k < j; k++) {
            if (left != null && right != null) {
              double t = (k - (i - 1)) / (j - (i - 1));
              a[k] = left * (1 - t) + right * t;
            } else if (left != null) {
              a[k] = left;
            } else if (right != null) {
              a[k] = right;
            }
          }
          i = j;
        }
      }

      if (showSys) {
        interp(mSys);
        interp(p25Sys);
        interp(p75SysL);
      }
      if (showDia) {
        interp(mDia);
        interp(p25Dia);
        interp(p75DiaL);
      }

      List<double?> smoothMA(List<double?> a, int halfWin) {
        final n = a.length;
        final out = List<double?>.filled(n, null);
        for (int i = 0; i < n; i++) {
          int s = (i - halfWin).clamp(0, n - 1);
          int e = (i + halfWin).clamp(0, n - 1);
          double sum = 0;
          int c = 0;
          for (int k = s; k <= e; k++) {
            final v = a[k];
            if (v != null) {
              sum += v;
              c++;
            }
          }
          out[i] = c > 0 ? sum / c : a[i];
        }
        return out;
      }

      List<double?> smoothEMA(List<double?> a, int windowDays) {
        final n = a.length;
        final alpha = 2 / (windowDays + 1);
        final f = List<double?>.filled(n, null);
        double? prev;
        for (int i = 0; i < n; i++) {
          final v = a[i];
          if (v == null) {
            f[i] = prev;
            continue;
          }
          prev = (prev == null) ? v : (alpha * v + (1 - alpha) * prev);
          f[i] = prev;
        }
        final b = List<double?>.filled(n, null);
        prev = null;
        for (int i = n - 1; i >= 0; i--) {
          final v = a[i];
          if (v == null) {
            b[i] = prev;
            continue;
          }
          prev = (prev == null) ? v : (alpha * v + (1 - alpha) * prev);
          b[i] = prev;
        }
        final out = List<double?>.filled(n, null);
        for (int i = 0; i < n; i++) {
          final x = f[i];
          final y = b[i];
          if (x != null && y != null) {
            out[i] = (x + y) / 2;
          } else {
            out[i] = x ?? y ?? a[i];
          }
        }
        return out;
      }

      if (smoothingEnabled) {
        int half = ((smoothingWindowDays.clamp(1, 31)) - 1) ~/ 2;
        if (half < 1) half = 1;
        if (smoothingMethod == 'ema') {
          if (showSys) {
            mSys = smoothEMA(mSys, smoothingWindowDays);
            p25Sys = smoothEMA(p25Sys, smoothingWindowDays);
            p75SysL = smoothEMA(p75SysL, smoothingWindowDays);
          }
          if (showDia) {
            mDia = smoothEMA(mDia, smoothingWindowDays);
            p25Dia = smoothEMA(p25Dia, smoothingWindowDays);
            p75DiaL = smoothEMA(p75DiaL, smoothingWindowDays);
          }
        } else {
          if (showSys) {
            mSys = smoothMA(mSys, half);
            p25Sys = smoothMA(p25Sys, half);
            p75SysL = smoothMA(p75SysL, half);
          }
          if (showDia) {
            mDia = smoothMA(mDia, half);
            p25Dia = smoothMA(p25Dia, half);
            p75DiaL = smoothMA(p75DiaL, half);
          }
        }
      }
      for (int i = 0; i < days.length; i++) {
        final x = days[i].difference(effStart).inDays.toDouble();
        if (showSys && mSys[i] != null) q50Sys.add(FlSpot(x, mSys[i]!));
        if (showSys && p25Sys[i] != null) q25Sys.add(FlSpot(x, p25Sys[i]!));
        if (showSys && p75SysL[i] != null) q75Sys.add(FlSpot(x, p75SysL[i]!));
        if (showDia && mDia[i] != null) q50Dia.add(FlSpot(x, mDia[i]!));
        if (showDia && p25Dia[i] != null) q25Dia.add(FlSpot(x, p25Dia[i]!));
        if (showDia && p75DiaL[i] != null) q75Dia.add(FlSpot(x, p75DiaL[i]!));
      }
    }

    final lines = <LineChartBarData>[];
    final between = <BetweenBarsData>[];
    if (!distribution) {
      if (showSys) {
        lines.add(
          LineChartBarData(
            spots: sysSpots,
            isCurved: false,
            color: Colors.red,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        );
      }
      if (showDia) {
        lines.add(
          LineChartBarData(
            spots: diaSpots,
            isCurved: false,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        );
      }
    } else {
      // In distribution mode, also overlay raw readings as faint dots
      if (showSys && sysSpots.isNotEmpty) {
        lines.add(
          LineChartBarData(
            spots: sysSpots,
            isCurved: false,
            color: Colors.red.withValues(alpha: 0.25),
            barWidth: 0,
            dotData: const FlDotData(show: true),
          ),
        );
      }
      if (showDia && diaSpots.isNotEmpty) {
        lines.add(
          LineChartBarData(
            spots: diaSpots,
            isCurved: false,
            color: Colors.blue.withValues(alpha: 0.25),
            barWidth: 0,
            dotData: const FlDotData(show: true),
          ),
        );
      }
      if (showSys) {
        lines.add(
          LineChartBarData(
            spots: q25Sys,
            isCurved: true,
            color: Colors.transparent,
            barWidth: 0,
            dotData: const FlDotData(show: false),
          ),
        );
        lines.add(
          LineChartBarData(
            spots: q75Sys,
            isCurved: true,
            color: Colors.transparent,
            barWidth: 0,
            dotData: const FlDotData(show: false),
          ),
        );
        lines.add(
          LineChartBarData(
            spots: q50Sys,
            isCurved: true,
            color: Colors.red,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        );
        between.add(
          BetweenBarsData(
            fromIndex: lines.length - 3,
            toIndex: lines.length - 2,
            color: const Color(0x26F44336),
          ),
        );
      }
      if (showDia) {
        lines.add(
          LineChartBarData(
            spots: q25Dia,
            isCurved: true,
            color: Colors.transparent,
            barWidth: 0,
            dotData: const FlDotData(show: false),
          ),
        );
        lines.add(
          LineChartBarData(
            spots: q75Dia,
            isCurved: true,
            color: Colors.transparent,
            barWidth: 0,
            dotData: const FlDotData(show: false),
          ),
        );
        lines.add(
          LineChartBarData(
            spots: q50Dia,
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        );
        between.add(
          BetweenBarsData(
            fromIndex: lines.length - 3,
            toIndex: lines.length - 2,
            color: const Color(0x1F2196F3),
          ),
        );
      }
    }

    // Secondary mapping to right axis
    final List<FlSpot> secSpots = [];
    double? secMin, secMax;
    if (secondary.isNotEmpty) {
      final ys = <double>[];
      for (final p in secondary) {
        ys.add(p.value);
      }
      if (ys.isNotEmpty) {
        secMin = ys.reduce(math.min);
        secMax = ys.reduce(math.max);
      }
      final minY =
          _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots]) - 10;
      final maxY =
          _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots]) + 10;
      final leftRange = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
      final secRange =
          (secMax != null && secMin != null && (secMax - secMin).abs() >= 1e-6)
          ? (secMax - secMin)
          : 1.0;
      for (final sp in secondary) {
        final x = toX(sp.date);
        final y = minY + (sp.value - (secMin ?? 0)) * leftRange / secRange;
        secSpots.add(FlSpot(x, y));
      }
    }

    // Left axis limits based only on BP series
    final minY = _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots]) - 10;
    final maxY = _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots]) + 10;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
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
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (maxX / 5).clamp(1, 30),
              getTitlesWidget: (value, meta) {
                final d = effStart.add(Duration(days: value.round()));
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${d.month}/${d.day}'),
                );
              },
            ),
            axisNameWidget: const Text('Date'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: secondary.isEmpty
                ? const SideTitles(showTitles: false)
                : SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: (secMax != null && secMin != null)
                        ? ((secMax - secMin) / 4).clamp(1, 1000)
                        : 1,
                    getTitlesWidget: (value, meta) {
                      if (secMin == null || secMax == null) {
                        return const SizedBox.shrink();
                      }
                      final leftRange = maxY - minY;
                      final secRange = (secMax - secMin).abs() < 1e-6
                          ? 1.0
                          : (secMax - secMin);
                      final secVal =
                          secMin + (value - minY) * secRange / leftRange;
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(secVal.toStringAsFixed(0)),
                      );
                    },
                  ),
          ),
        ),
        lineBarsData: [
          ...lines,
          if (secSpots.isNotEmpty)
            LineChartBarData(
              spots: secSpots,
              isCurved: true,
              color: Colors.purple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
        ],
        betweenBarsData: between,
        lineTouchData: LineTouchData(enabled: tooltipsEnabled),
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
          enabled: showBands,
          scheme: zoneScheme,
        ),
      ),
    );
  }

  static double _q(List<double> sorted, double q) {
    if (sorted.isEmpty) return double.nan;
    final pos = (sorted.length - 1) * q;
    final i = pos.floor();
    final frac = pos - i;
    if (i + 1 < sorted.length) {
      return sorted[i] * (1 - frac) + sorted[i + 1] * frac;
    }
    return sorted[i];
  }

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

// no private DTOs; charts use shared models in lib/models/chart_models.dart
