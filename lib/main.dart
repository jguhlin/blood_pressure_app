import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

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
  bool _isCustomRange = false;
  late DateTime _rangeEnd;
  late DateTime _rangeStart;
  _ViewMode _mode = _ViewMode.trend;
  // Compare mode state
  DateTimeRange? _rangeA;
  DateTimeRange? _rangeB;
  _AvgDay? _avgA;
  _AvgDay? _avgB;

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
      final ok = await _ensurePermissions();
      if (!ok) {
        setState(() {
          _loading = false;
          _error = 'Health permission not granted';
        });
        return;
      }

      _rangeEnd = DateTime.now();
      if (!_isCustomRange) {
        _rangeStart = _rangeEnd.subtract(Duration(days: _rangeDays));
      }
      var points = await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
          HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        ],
        startTime: _rangeStart,
        endTime: _rangeEnd,
      );

      // If nothing in last 30 days, try requesting history permission and extend window
      if (points.isEmpty) {
        try {
          final histGranted = await _health.requestHealthDataHistoryAuthorization();
          if (histGranted) {
            if (!_isCustomRange) {
              _rangeStart = _rangeEnd.subtract(const Duration(days: 365));
            }
            points = await _health.getHealthDataFromTypes(
              types: const [
                HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
                HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
              ],
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

  Future<bool> _ensurePermissions() async {
    await _health.configure();
    const types = <HealthDataType>[
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ];
    const permissions = <HealthDataAccess>[
      HealthDataAccess.READ,
      HealthDataAccess.READ,
    ];
    final hasPerm = await _health.hasPermissions(types, permissions: permissions) ?? false;
    if (!hasPerm) {
      final granted = await _health.requestAuthorization(types, permissions: permissions);
      if (!granted) return false;
    }
    return true;
  }

  Future<void> _fetchCompare() async {
    setState(() {
      _loading = true;
      _error = null;
      _avgA = null;
      _avgB = null;
    });
    try {
      final ok = await _ensurePermissions();
      if (!ok) {
        setState(() {
          _loading = false;
          _error = 'Health permission not granted';
        });
        return;
      }

      if (_rangeA == null || _rangeB == null) {
        setState(() {
          _loading = false;
          _error = 'Pick both ranges to compare';
        });
        return;
      }

      final types = const [
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      ];

      // Range A
      var pointsA = await _health.getHealthDataFromTypes(
        types: types,
        startTime: _rangeA!.start,
        endTime: _rangeA!.end,
      );
      if (pointsA.isEmpty) {
        try {
          final histGranted = await _health.requestHealthDataHistoryAuthorization();
          if (histGranted) {
            pointsA = await _health.getHealthDataFromTypes(
              types: types,
              startTime: _rangeA!.start,
              endTime: _rangeA!.end,
            );
          }
        } catch (_) {}
      }
      final seriesA = _combineSeries(pointsA);

      // Range B
      var pointsB = await _health.getHealthDataFromTypes(
        types: types,
        startTime: _rangeB!.start,
        endTime: _rangeB!.end,
      );
      if (pointsB.isEmpty) {
        try {
          final histGranted = await _health.requestHealthDataHistoryAuthorization();
          if (histGranted) {
            pointsB = await _health.getHealthDataFromTypes(
              types: types,
              startTime: _rangeB!.start,
              endTime: _rangeB!.end,
            );
          }
        } catch (_) {}
      }
      final seriesB = _combineSeries(pointsB);

      final aggA = _AverageDayAggregator(series: seriesA).compute(stepMinutes: 15, smoothMinutes: 45);
      final aggB = _AverageDayAggregator(series: seriesB).compute(stepMinutes: 15, smoothMinutes: 45);

      setState(() {
        _avgA = aggA;
        _avgB = aggB;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _labelRange(String tag, DateTimeRange r) {
    String mmdd(DateTime d) => '${d.month}/${d.day}';
    return '$tag: ${mmdd(r.start)}–${mmdd(r.end)}';
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
            // Range and mode selectors
            if (_mode != _ViewMode.compare)
              Row(
                children: [
                  const Text('Range:'),
                  const SizedBox(width: 8),
                  ToggleButtons(
                    isSelected: [
                      _rangeDays == 7 && !_isCustomRange,
                      _rangeDays == 30 && !_isCustomRange,
                      _rangeDays == 90 && !_isCustomRange,
                    ],
                    onPressed: (i) {
                      final days = i == 0 ? 7 : i == 1 ? 30 : 90;
                      setState(() {
                        _isCustomRange = false;
                        _rangeDays = days;
                      });
                      _fetchData();
                    },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('7d')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('30d')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('90d')),
                    ],
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                        lastDate: DateTime.now(),
                        initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
                      );
                      if (picked != null) {
                        setState(() {
                          _isCustomRange = true;
                          _rangeStart = DateTime(picked.start.year, picked.start.month, picked.start.day);
                          _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
                        });
                        _fetchData();
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(_isCustomRange ? 'Custom' : 'Custom...'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                        lastDate: DateTime.now(),
                        initialDateRange: _rangeA ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
                      );
                      if (picked != null) {
                        setState(() => _rangeA = picked);
                      }
                    },
                    icon: const Icon(Icons.looks_one, size: 18),
                    label: Text(_rangeA == null ? 'Pick Range A' : _labelRange('A', _rangeA!)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                        lastDate: DateTime.now(),
                        initialDateRange: _rangeB ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now()),
                      );
                      if (picked != null) {
                        setState(() => _rangeB = picked);
                      }
                    },
                    icon: const Icon(Icons.looks_two, size: 18),
                    label: Text(_rangeB == null ? 'Pick Range B' : _labelRange('B', _rangeB!)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: (_rangeA != null && _rangeB != null && !_loading) ? _fetchCompare : null,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Fetch'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('View:'),
                const SizedBox(width: 8),
                ToggleButtons(
                  isSelected: [
                    _mode == _ViewMode.trend,
                    _mode == _ViewMode.averageDay,
                    _mode == _ViewMode.compare,
                  ],
                  onPressed: (i) {
                    setState(() => _mode = i == 0
                        ? _ViewMode.trend
                        : i == 1
                            ? _ViewMode.averageDay
                            : _ViewMode.compare);
                  },
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Trend')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Average Day')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Compare')),
                  ],
                ),
              ],
            ),
            // Legend: systolic/diastolic with units or compare A/B
            if (_mode != _ViewMode.compare)
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
              )
            else
              Row(
                children: const [
                  _LegendDot(color: Colors.red),
                  SizedBox(width: 6),
                  Text('A: Systolic'),
                  SizedBox(width: 12),
                  _LegendDot(color: Colors.blue),
                  SizedBox(width: 6),
                  Text('A: Diastolic'),
                  SizedBox(width: 18),
                  _LegendDot(color: Colors.orange),
                  SizedBox(width: 6),
                  Text('B: Systolic'),
                  SizedBox(width: 12),
                  _LegendDot(color: Colors.lightBlue),
                  SizedBox(width: 6),
                  Text('B: Diastolic'),
                ],
              ),
            const SizedBox(height: 8),
            if (_mode == _ViewMode.compare)
              SizedBox(
                height: 260,
                child: (_avgA != null && _avgB != null)
                    ? _AverageDayCompareChart(avgA: _avgA!, avgB: _avgB!)
                    : const Center(child: Text('Pick two ranges and tap Fetch.')),
              )
            else if (_series.isNotEmpty)
              SizedBox(
                height: 260,
                child: _mode == _ViewMode.trend
                    ? _TrendChart(series: _series, start: _rangeStart, end: _rangeEnd)
                    : _AverageDayChart(series: _series),
              )
            else
              const Text('No data available for selected range.'),
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

class _AverageDayChart extends StatelessWidget {
  final List<_BPEntry> series;
  const _AverageDayChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final agg = _AverageDayAggregator(series: series).compute(stepMinutes: 15, smoothMinutes: 45);
    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (int i = 0; i < agg.minutes.length; i++) {
      final x = agg.minutes[i] / 60.0; // hours
      final s = agg.sysMean[i];
      final d = agg.diaMean[i];
      if (s != null) sysSpots.add(FlSpot(x, s));
      if (d != null) diaSpots.add(FlSpot(x, d));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
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
              interval: 3,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(meta: meta, child: Text('${value.round()}h'));
              },
            ),
            axisNameWidget: const Text('Time of Day'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: sysSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: Colors.red,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: diaSpots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
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

class _AverageDayCompareChart extends StatelessWidget {
  final _AvgDay avgA;
  final _AvgDay avgB;
  const _AverageDayCompareChart({required this.avgA, required this.avgB});

  @override
  Widget build(BuildContext context) {
    final aSys = <FlSpot>[];
    final aDia = <FlSpot>[];
    final bSys = <FlSpot>[];
    final bDia = <FlSpot>[];
    for (int i = 0; i < avgA.minutes.length; i++) {
      final x = avgA.minutes[i] / 60.0;
      final s = avgA.sysMean[i];
      final d = avgA.diaMean[i];
      if (s != null) aSys.add(FlSpot(x, s));
      if (d != null) aDia.add(FlSpot(x, d));
    }
    for (int i = 0; i < avgB.minutes.length; i++) {
      final x = avgB.minutes[i] / 60.0;
      final s = avgB.sysMean[i];
      final d = avgB.diaMean[i];
      if (s != null) bSys.add(FlSpot(x, s));
      if (d != null) bDia.add(FlSpot(x, d));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
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
              interval: 3,
              getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, child: Text('${value.round()}h')),
            ),
            axisNameWidget: const Text('Time of Day'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          // A curves
          LineChartBarData(spots: aSys, isCurved: true, curveSmoothness: 0.25, color: Colors.red, barWidth: 2, dotData: const FlDotData(show: false)),
          LineChartBarData(spots: aDia, isCurved: true, curveSmoothness: 0.25, color: Colors.blue, barWidth: 2, dotData: const FlDotData(show: false)),
          // B curves
          LineChartBarData(spots: bSys, isCurved: true, curveSmoothness: 0.25, color: Colors.orange, barWidth: 2, dotData: const FlDotData(show: false)),
          LineChartBarData(spots: bDia, isCurved: true, curveSmoothness: 0.25, color: Colors.lightBlue, barWidth: 2, dotData: const FlDotData(show: false)),
        ],
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

class _AverageDayAggregator {
  final List<_BPEntry> series;
  _AverageDayAggregator({required this.series});

  _AvgDay compute({int stepMinutes = 15, int smoothMinutes = 45}) {
    final step = stepMinutes;
    final bins = (24 * 60) ~/ step;
    final days = <DateTime, _DayBins>{};

    double clamp(double v) => v.clamp(40.0, 220.0);

    for (final e in series) {
      final t = e.timestamp;
      if (t == null) continue;
      final dayKey = DateTime(t.year, t.month, t.day);
      final d = days.putIfAbsent(dayKey, () => _DayBins(bins));
      final m = t.hour * 60 + t.minute + t.second / 60.0;
      final f = m / step;
      int i0 = f.floor();
      final frac = f - i0;
      int i1 = (i0 + 1) % bins;
      if (i0 >= bins) i0 = bins - 1;

      if (e.systolic != null) {
        final v = clamp(e.systolic!);
        d.sysSum[i0] += v * (1 - frac);
        d.sysW[i0] += (1 - frac);
        d.sysSum[i1] += v * frac;
        d.sysW[i1] += frac;
      }
      if (e.diastolic != null) {
        final v = clamp(e.diastolic!);
        d.diaSum[i0] += v * (1 - frac);
        d.diaW[i0] += (1 - frac);
        d.diaSum[i1] += v * frac;
        d.diaW[i1] += frac;
      }
    }

    // Per-day means per bin
    final perDaySys = <List<double?>>[];
    final perDayDia = <List<double?>>[];
    for (final d in days.values) {
      final sys = List<double?>.filled(bins, null);
      final dia = List<double?>.filled(bins, null);
      for (int i = 0; i < bins; i++) {
        if (d.sysW[i] > 0) sys[i] = d.sysSum[i] / d.sysW[i];
        if (d.diaW[i] > 0) dia[i] = d.diaSum[i] / d.diaW[i];
      }
      perDaySys.add(sys);
      perDayDia.add(dia);
    }

    List<double?> avgOfDays(List<List<double?>> perDay) {
      final out = List<double?>.filled(bins, null);
      for (int i = 0; i < bins; i++) {
        double sum = 0;
        int n = 0;
        for (final day in perDay) {
          final v = day[i];
          if (v != null) {
            sum += v;
            n++;
          }
        }
        if (n > 0) out[i] = sum / n;
      }
      return out;
    }

    final sysMean = avgOfDays(perDaySys);
    final diaMean = avgOfDays(perDayDia);

    // Circular Gaussian smoothing
    List<double?> smooth(List<double?> src) {
      final sigmaBins = (smoothMinutes / step).clamp(1, 12).toDouble();
      final radius = (sigmaBins * 3).ceil();
      final out = List<double?>.filled(bins, null);
      for (int i = 0; i < bins; i++) {
        double wsum = 0, vsum = 0;
        for (int off = -radius; off <= radius; off++) {
          final j = (i + off) % bins;
          final jj = j < 0 ? j + bins : j;
          final v = src[jj];
          if (v == null) continue;
          final w = math.exp(-(off * off) / (2 * sigmaBins * sigmaBins));
          vsum += w * v;
          wsum += w;
        }
        if (wsum > 0) out[i] = vsum / wsum;
      }
      return out;
    }

    final sysSmooth = smooth(sysMean);
    final diaSmooth = smooth(diaMean);

    final minutes = List<int>.generate(bins, (i) => i * step);
    return _AvgDay(minutes: minutes, sysMean: sysSmooth, diaMean: diaSmooth);
  }
}

class _DayBins {
  final List<double> sysSum;
  final List<double> diaSum;
  final List<double> sysW;
  final List<double> diaW;
  _DayBins(int bins)
      : sysSum = List.filled(bins, 0),
        diaSum = List.filled(bins, 0),
        sysW = List.filled(bins, 0),
        diaW = List.filled(bins, 0);
}

class _AvgDay {
  final List<int> minutes; // minutes since midnight
  final List<double?> sysMean; // smoothed means
  final List<double?> diaMean;
  _AvgDay({required this.minutes, required this.sysMean, required this.diaMean});
}

enum _ViewMode { trend, averageDay, compare }

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
