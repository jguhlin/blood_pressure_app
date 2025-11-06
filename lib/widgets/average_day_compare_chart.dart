import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/avg_day.dart' as avg;
import '../models/chart_models.dart';

class AverageDayCompareChart extends StatelessWidget {
  final List<ChartBp> seriesA;
  final List<ChartBp> seriesB;
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  const AverageDayCompareChart({
    super.key,
    required this.seriesA,
    required this.seriesB,
    this.anchorMinute,
    this.showBands = false,
  });

  @override
  Widget build(BuildContext context) {
    final aggA =
        avg.AverageDayAggregator(
          series: seriesA
              .map((e) => avg.AvgBpInput(t: e.t, sbp: e.sbp, dbp: e.dbp))
              .toList(),
        ).compute(
          stepMinutes: 15,
          smoothMinutes: 45,
          anchorMinute: anchorMinute,
          withBands: showBands,
        );
    final aggB =
        avg.AverageDayAggregator(
          series: seriesB
              .map((e) => avg.AvgBpInput(t: e.t, sbp: e.sbp, dbp: e.dbp))
              .toList(),
        ).compute(
          stepMinutes: 15,
          smoothMinutes: 45,
          anchorMinute: anchorMinute,
          withBands: showBands,
        );
    final aSys = <FlSpot>[],
        aDia = <FlSpot>[],
        bSys = <FlSpot>[],
        bDia = <FlSpot>[];
    for (int i = 0; i < aggA.minutes.length; i++) {
      final x = aggA.minutes[i] / 60.0;
      final s = aggA.sysMean[i];
      final d = aggA.diaMean[i];
      if (s != null) aSys.add(FlSpot(x, s));
      if (d != null) aDia.add(FlSpot(x, d));
    }
    for (int i = 0; i < aggB.minutes.length; i++) {
      final x = aggB.minutes[i] / 60.0;
      final s = aggB.sysMean[i];
      final d = aggB.diaMean[i];
      if (s != null) bSys.add(FlSpot(x, s));
      if (d != null) bDia.add(FlSpot(x, d));
    }
    final bars = <LineChartBarData>[
      LineChartBarData(
        spots: aSys,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.red,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ),
      LineChartBarData(
        spots: aDia,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.blue,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ),
      LineChartBarData(
        spots: bSys,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.orange,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ),
      LineChartBarData(
        spots: bDia,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.lightBlue,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ),
    ];
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: 40,
        maxY: 200,
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
        lineBarsData: bars,
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 2,
            color: const Color(0x33FFA500),
          ),
          BetweenBarsData(
            fromIndex: 1,
            toIndex: 3,
            color: const Color(0x331E90FF),
          ),
        ],
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black12),
            bottom: BorderSide(color: Colors.black12),
          ),
        ),
      ),
    );
  }

  static Widget _hourTick(double value, TitleMeta meta) =>
      SideTitleWidget(meta: meta, child: Text('${value.round()}h'));
}
