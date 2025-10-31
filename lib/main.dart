import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const BPApp());

class BPApp extends StatelessWidget {
  const BPApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Pressure',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)),
      home: const LatestBPPage(),
    );
  }
}

class LatestBPPage extends StatefulWidget {
  final bool autoFetch;
  const LatestBPPage({super.key, this.autoFetch = true});
  @override
  State<LatestBPPage> createState() => _LatestBPPageState();
}

class _LatestBPPageState extends State<LatestBPPage> {
  final Health _health = Health();
  bool _loading = false;
  String? _error;
  _BPEntry? _latest;
  List<_BPEntry> _series = const [];
  int _rangeDays = 30;
  late DateTime _rangeEnd;
  late DateTime _rangeStart;

  @override
  void initState() {
    super.initState();
    _rangeEnd = DateTime.now();
    _rangeStart = _rangeEnd.subtract(Duration(days: _rangeDays));
    if (widget.autoFetch) _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _health.configure();
      final types = <HealthDataType>[
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      ];
      final permissions = <HealthDataAccess>[
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ];

      final hasPerm = await _health.hasPermissions(types, permissions: permissions) ?? false;
      if (!hasPerm) {
        final granted = await _health.requestAuthorization(types, permissions: permissions);
        if (!granted) {
          setState(() {
            _loading = false;
            _error = 'Health permission not granted';
          });
          return;
        }
      }

      _rangeEnd = DateTime.now();
      _rangeStart = _rangeEnd.subtract(Duration(days: _rangeDays));
      var points = await _health.getHealthDataFromTypes(
        types: types,
        startTime: _rangeStart,
        endTime: _rangeEnd,
      );

      // If nothing in last 30 days, try requesting history permission and extend window
      if (points.isEmpty) {
        try {
          final histGranted = await _health.requestHealthDataHistoryAuthorization();
          if (histGranted) {
            _rangeStart = _rangeEnd.subtract(const Duration(days: 365));
            points = await _health.getHealthDataFromTypes(
              types: types,
              startTime: _rangeStart,
              endTime: _rangeEnd,
            );
          }
        } catch (_) {
          // Ignore; not all platforms/versions support this call
        }
      }

      final series = _combineSeries(points);
      final latest = series.isNotEmpty ? series.last : null;
      setState(() {
        _latest = latest;
        _series = series;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_BPEntry> _combineSeries(List<HealthDataPoint> points) {
    if (points.isEmpty) return const [];
    points.sort((a, b) => a.dateTo.compareTo(b.dateTo));

    final systolic = <HealthDataPoint>[];
    final diastolic = <HealthDataPoint>[];
    for (final p in points) {
      if (p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC) systolic.add(p);
      if (p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC) diastolic.add(p);
    }

    final usedDia = <int>{};
    final entries = <_BPEntry>[];

    for (final s in systolic) {
      final idx = _closestIndex(diastolic, s.dateTo, exclude: usedDia);
      HealthDataPoint? d;
      if (idx != null) {
        d = diastolic[idx];
        if ((d.dateTo.difference(s.dateTo)).abs() <= const Duration(minutes: 10)) {
          usedDia.add(idx);
        } else {
          d = null;
        }
      }
      entries.add(_BPEntry(
        timestamp: s.dateTo,
        systolic: _toDouble(s.value),
        diastolic: _toDouble(d?.value),
        source: s.sourceId,
      ));
    }
    for (int i = 0; i < diastolic.length; i++) {
      if (usedDia.contains(i)) continue;
      final d = diastolic[i];
      entries.add(_BPEntry(
        timestamp: d.dateTo,
        systolic: null,
        diastolic: _toDouble(d.value),
        source: d.sourceId,
      ));
    }

    entries.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    return entries;
  }

  int? _closestIndex(List<HealthDataPoint> list, DateTime t, {Set<int>? exclude}) {
    if (list.isEmpty) return null;
    int? best;
    var bestDelta = const Duration(days: 365);
    for (int i = 0; i < list.length; i++) {
      if (exclude != null && exclude.contains(i)) continue;
      final d = (list[i].dateTo.difference(t)).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = i;
      }
    }
    return best;
  }

  // _combineLatestBP removed; latest is derived from combined series

  // helper removed

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    try {
      // Some plugin versions wrap numeric types; fallback to parsing
      return double.parse(value.toString());
    } catch (_) {
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest Blood Pressure'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Range:'),
                const SizedBox(width: 8),
                ToggleButtons(
                  isSelected: [
                    _rangeDays == 30,
                    _rangeDays == 90,
                  ],
                  onPressed: (i) {
                    final days = i == 0 ? 30 : 90;
                    if (days != _rangeDays) {
                      setState(() => _rangeDays = days);
                      _fetchData();
                    }
                  },
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('30d')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('90d')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Legend: systolic/diastolic with units
            Row(
              children: const [
                _LegendDot(color: Colors.red),
                SizedBox(width: 6),
                Text('Systolic (mmHg)'),
                SizedBox(width: 16),
                _LegendDot(color: Colors.blue),
                SizedBox(width: 6),
                Text('Diastolic (mmHg)'),
              ],
            ),
            const SizedBox(height: 8),
            if (_series.isNotEmpty)
              SizedBox(
                height: 240,
                child: _TrendChart(series: _series, start: _rangeStart, end: _rangeEnd),
              )
            else
              const Text('No trend data available for selected range.'),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            const Text('Latest entry (if available):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _LatestTable(entry: _latest),
            const Spacer(),
            const Text(
              'Note: Health Connect access may initially show recent data only. '
              'If no result appears, try granting history access when prompted.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestTable extends StatelessWidget {
  final _BPEntry? entry;
  const _LatestTable({required this.entry});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: const [
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Time')),
        DataColumn(label: Text('Systolic (mmHg)')),
        DataColumn(label: Text('Diastolic (mmHg)')),
        DataColumn(label: Text('Source')),
      ], rows: [
        DataRow(cells: [
          DataCell(Text(_formatDate(entry?.timestamp))),
          DataCell(Text(_formatTime(entry?.timestamp))),
          DataCell(Text(entry?.systolic?.toStringAsFixed(0) ?? '-')),
          DataCell(Text(entry?.diastolic?.toStringAsFixed(0) ?? '-')),
          DataCell(Text(entry?.source ?? '-')),
        ])
      ]),
    );
  }

  String _formatDate(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}

class _BPEntry {
  final DateTime? timestamp;
  final double? systolic;
  final double? diastolic;
  final String? source;
  const _BPEntry({this.timestamp, this.systolic, this.diastolic, this.source});
}

class _TrendChart extends StatelessWidget {
  final List<_BPEntry> series;
  final DateTime start;
  final DateTime end;
  const _TrendChart({required this.series, required this.start, required this.end});

  double _toX(DateTime t) => t.difference(start).inMinutes / 1440.0; // days as double

  @override
  Widget build(BuildContext context) {
    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (final e in series) {
      if (e.timestamp == null) continue;
      final x = _toX(e.timestamp!);
      if (e.systolic != null) sysSpots.add(FlSpot(x, e.systolic!));
      if (e.diastolic != null) diaSpots.add(FlSpot(x, e.diastolic!));
    }
    final maxX = end.difference(start).inDays.toDouble().clamp(1.0, 365.0);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 40,
        maxY: 200,
        gridData: const FlGridData(show: true, drawVerticalLine: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 20),
            axisNameWidget: const Text('mmHg'),
            axisNameSize: 18,
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (maxX / 5).clamp(1, 30),
              getTitlesWidget: (value, meta) {
                final d = start.add(Duration(days: value.round()));
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${d.month}/${d.day}'),
                );
              },
            ),
            axisNameWidget: const Text('Date'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: sysSpots,
            isCurved: true,
            curveSmoothness: 0.15,
            color: Colors.red,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: diaSpots,
            isCurved: true,
            curveSmoothness: 0.15,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((barSpot) {
                final days = barSpot.x;
                final dt = start.add(Duration(days: days.round()));
                final value = barSpot.y;
                final label = '${dt.month}/${dt.day}  •  ${value.toStringAsFixed(0)} mmHg';
                return LineTooltipItem(label, TextStyle(color: barSpot.bar.color ?? Colors.black));
              }).toList();
            },
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black12),
            bottom: BorderSide(color: Colors.black12),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
