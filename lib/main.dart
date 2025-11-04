import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
  bool _hasPermissions = false;
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
  List<_BPEntry>? _seriesA;
  List<_BPEntry>? _seriesB;
  // Bands + medication anchor
  bool _showBands = false;
  bool _anchorToDose = false;
  TimeOfDay? _doseTime;

  @override
  void initState() {
    super.initState();
    _rangeEnd = DateTime.now();
    _rangeStart = _rangeEnd.subtract(Duration(days: _rangeDays));
    _loadPrefs();
    if (widget.autoFetch) _fetchData();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final anchor = prefs.getBool('anchor_to_dose') ?? false;
    final doseH = prefs.getInt('dose_hour');
    final doseM = prefs.getInt('dose_minute');
    final isCustom = prefs.getBool('is_custom_range') ?? false;
    final days = prefs.getInt('range_days') ?? _rangeDays;
    final startIso = prefs.getString('range_start');
    final endIso = prefs.getString('range_end');
    final aStartIso = prefs.getString('rangeA_start');
    final aEndIso = prefs.getString('rangeA_end');
    final bStartIso = prefs.getString('rangeB_start');
    final bEndIso = prefs.getString('rangeB_end');
    if (!mounted) return;
    setState(() {
      _anchorToDose = anchor;
      if (doseH != null && doseM != null) {
        _doseTime = TimeOfDay(hour: doseH, minute: doseM);
      }
      _isCustomRange = isCustom;
      _rangeDays = days;
      if (startIso != null && endIso != null) {
        _rangeStart = DateTime.tryParse(startIso) ?? _rangeStart;
        _rangeEnd = DateTime.tryParse(endIso) ?? _rangeEnd;
      }
      if (aStartIso != null && aEndIso != null) {
        final aS = DateTime.tryParse(aStartIso);
        final aE = DateTime.tryParse(aEndIso);
        if (aS != null && aE != null) _rangeA = DateTimeRange(start: aS, end: aE);
      }
      if (bStartIso != null && bEndIso != null) {
        final bS = DateTime.tryParse(bStartIso);
        final bE = DateTime.tryParse(bEndIso);
        if (bS != null && bE != null) _rangeB = DateTimeRange(start: bS, end: bE);
      }
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('anchor_to_dose', _anchorToDose);
    if (_doseTime != null) {
      await prefs.setInt('dose_hour', _doseTime!.hour);
      await prefs.setInt('dose_minute', _doseTime!.minute);
    }
    await prefs.setBool('is_custom_range', _isCustomRange);
    await prefs.setInt('range_days', _rangeDays);
    await prefs.setString('range_start', _rangeStart.toIso8601String());
    await prefs.setString('range_end', _rangeEnd.toIso8601String());
    if (_rangeA != null) {
      await prefs.setString('rangeA_start', _rangeA!.start.toIso8601String());
      await prefs.setString('rangeA_end', _rangeA!.end.toIso8601String());
    }
    if (_rangeB != null) {
      await prefs.setString('rangeB_start', _rangeB!.start.toIso8601String());
      await prefs.setString('rangeB_end', _rangeB!.end.toIso8601String());
    }
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
          _hasPermissions = false;
        });
        return;
      }
      setState(() => _hasPermissions = true);

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
      _seriesA = null;
      _seriesB = null;
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

      setState(() {
        _seriesA = seriesA;
        _seriesB = seriesB;
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
    // Health package uses HealthValue; extract numericValue when present
    try {
      if (value is NumericHealthValue) {
        return (value.numericValue).toDouble();
      }
      final json = value.toJson();
      final dyn = json['numericValue'] ?? json['value'];
      if (dyn is num) return dyn.toDouble();
      if (dyn is String) return double.tryParse(dyn);
    } catch (_) {}
    try {
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
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: _loading ? null : _exportTsv,
            tooltip: 'Export TSV',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            if (!_hasPermissions)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Health permissions are required to read blood pressure.', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ElevatedButton.icon(
                          onPressed: _requestPermsManually,
                          icon: const Icon(Icons.verified_user),
                          label: const Text('Grant in app'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openHealthConnectSettings,
                          icon: const Icon(Icons.settings),
                          label: const Text('Open Health Connect'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
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
                    _savePrefs();
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
                      _savePrefs();
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
                        _savePrefs();
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
                        _savePrefs();
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('View:'),
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
                Row(children: [
                  const Text('Bands'),
                  const SizedBox(width: 6),
                  Switch(
                    value: _showBands,
                    onChanged: (v) => setState(() => _showBands = v),
                  ),
                ]),
                Row(children: [
                  const Text('Anchor to dose'),
                  const SizedBox(width: 6),
                  Switch(
                    value: _anchorToDose,
                    onChanged: (v) {
                      setState(() => _anchorToDose = v);
                      _savePrefs();
                    },
                  ),
                ]),
                OutlinedButton.icon(
                  onPressed: !_anchorToDose
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _doseTime ?? const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (picked != null) {
                            setState(() => _doseTime = picked);
                            _savePrefs();
                          }
                        },
                  icon: const Icon(Icons.medication),
                  label: Text(_doseTime == null
                      ? 'Dose time'
                      : '${_doseTime!.hour.toString().padLeft(2, '0')}:${_doseTime!.minute.toString().padLeft(2, '0')}'),
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
                child: (_seriesA != null && _seriesB != null)
                    ? _AverageDayCompareChart(
                        seriesA: _seriesA!,
                        seriesB: _seriesB!,
                        anchorMinute: _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null,
                        showBands: _showBands,
                      )
                    : const Center(child: Text('Pick two ranges and tap Fetch.')),
              )
            else if (_series.isNotEmpty)
              SizedBox(
                height: 260,
                child: _mode == _ViewMode.trend
                    ? _TrendChart(series: _series, start: _rangeStart, end: _rangeEnd)
                    : _AverageDayChart(
                        series: _series,
                        anchorMinute: _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null,
                        showBands: _showBands,
                      ),
              )
            else
              const Text('No data available for selected range.'),
            const SizedBox(height: 12),
            _SummaryCards(
              mode: _mode,
              series: _series,
              seriesA: _seriesA,
              seriesB: _seriesB,
              anchorMinute: _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            const Text('Latest entry (if available):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _LatestTable(entry: _latest),
            const SizedBox(height: 12),
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

  Future<void> _exportTsv() async {
    try {
      final now = DateTime.now().toIso8601String().replaceAll(':', '-');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/bp_export_$now.tsv';
      final file = File(path);

      final buf = StringBuffer();
      if (_mode == _ViewMode.trend) {
        buf.writeln('mode\tstart\tend');
        buf.writeln('trend\t${_rangeStart.toIso8601String()}\t${_rangeEnd.toIso8601String()}');
        buf.writeln('timestamp\tsystolic_mmHg\tdiastolic_mmHg\tsource');
        for (final e in _series) {
          final ts = e.timestamp?.toIso8601String() ?? '';
          buf.writeln('$ts\t${e.systolic?.toStringAsFixed(1) ?? ''}\t${e.diastolic?.toStringAsFixed(1) ?? ''}\t${e.source ?? ''}');
        }
      } else if (_mode == _ViewMode.averageDay) {
        final agg = _AverageDayAggregator(series: _series).compute(stepMinutes: 15, smoothMinutes: 45);
        buf.writeln('mode\tstart\tend');
        buf.writeln('average_day\t${_rangeStart.toIso8601String()}\t${_rangeEnd.toIso8601String()}');
        buf.writeln('minute_of_day\ttime_label\tsystolic_mean_mmHg\tdiastolic_mean_mmHg');
        for (int i = 0; i < agg.minutes.length; i++) {
          final m = agg.minutes[i];
          final h = (m / 60).floor();
          final min = m % 60;
          String two(int n) => n.toString().padLeft(2, '0');
          final label = '${two(h)}:${two(min)}';
          final s = agg.sysMean[i]?.toStringAsFixed(1) ?? '';
          final d = agg.diaMean[i]?.toStringAsFixed(1) ?? '';
          buf.writeln('$m\t$label\t$s\t$d');
        }
      } else if (_mode == _ViewMode.compare) {
        if (_seriesA == null || _seriesB == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick two ranges and Fetch first.')));
          return;
        }
        buf.writeln('mode');
        buf.writeln('compare');
        buf.writeln('rangeA_start\trangeA_end\trangeB_start\trangeB_end');
        buf.writeln('${_rangeA?.start.toIso8601String() ?? ''}\t${_rangeA?.end.toIso8601String() ?? ''}\t${_rangeB?.start.toIso8601String() ?? ''}\t${_rangeB?.end.toIso8601String() ?? ''}');
        buf.writeln('minute_of_day\ttime_label\tA_systolic\tA_diastolic\tB_systolic\tB_diastolic\tDelta_systolic(B-A)\tDelta_diastolic(B-A)');
        final anchorMin = _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null;
        final aggA = _AverageDayAggregator(series: _seriesA!).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMin);
        final aggB = _AverageDayAggregator(series: _seriesB!).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMin);
        for (int i = 0; i < aggA.minutes.length; i++) {
          final m = aggA.minutes[i];
          final h = (m / 60).floor();
          final min = m % 60;
          String two(int n) => n.toString().padLeft(2, '0');
          final label = '${two(h)}:${two(min)}';
          final aS = aggA.sysMean[i];
          final aD = aggA.diaMean[i];
          final bS = aggB.sysMean[i];
          final bD = aggB.diaMean[i];
          String f(double? v) => v == null ? '' : v.toStringAsFixed(1);
          final dS = (bS != null && aS != null) ? (bS - aS).toStringAsFixed(1) : '';
          final dD = (bD != null && aD != null) ? (bD - aD).toStringAsFixed(1) : '';
          buf.writeln('$m\t$label\t${f(aS)}\t${f(aD)}\t${f(bS)}\t${f(bD)}\t$dS\t$dD');
        }
      }

      await file.writeAsString(buf.toString());
      final x = XFile(file.path, mimeType: 'text/tab-separated-values', name: file.uri.pathSegments.last);
      await Share.shareXFiles([x], subject: 'Blood Pressure Export (TSV)', text: 'Attached TSV export from Blood Pressure app.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _requestPermsManually() async {
    try {
      final ok = await _ensurePermissions();
      if (ok) {
        setState(() => _hasPermissions = true);
        _fetchData();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission still not granted. Open Health Connect.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission error: $e')));
    }
  }

  static const _hcChannel = MethodChannel('app.healthconnect');
  Future<void> _openHealthConnectSettings() async {
    try {
      await _hcChannel.invokeMethod('openSettings');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to open Health Connect: $e')));
    }
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
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  const _AverageDayChart({required this.series, this.anchorMinute, this.showBands = false});

  @override
  Widget build(BuildContext context) {
    final agg = _AverageDayAggregator(series: series)
        .compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute, withBands: showBands);
    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (int i = 0; i < agg.minutes.length; i++) {
      final x = agg.minutes[i] / 60.0; // hours
      final s = agg.sysMean[i];
      final d = agg.diaMean[i];
      if (s != null) sysSpots.add(FlSpot(x, s));
      if (d != null) diaSpots.add(FlSpot(x, d));
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
        LineChartBarData(spots: sysLower, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: sysUpper, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)),
      ]);
    }
    if (showBands && diaLower.isNotEmpty && diaUpper.isNotEmpty) {
      bars.addAll([
        LineChartBarData(spots: diaLower, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: diaUpper, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)),
      ]);
    }
    bars.add(LineChartBarData(
      spots: sysSpots,
      isCurved: true,
      curveSmoothness: 0.25,
      color: Colors.red,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    ));
    bars.add(LineChartBarData(
      spots: diaSpots,
      isCurved: true,
      curveSmoothness: 0.25,
      color: Colors.blue,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    ));

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
        lineBarsData: bars,
        betweenBarsData: [
          if (showBands && sysLower.isNotEmpty && sysUpper.isNotEmpty)
            BetweenBarsData(fromIndex: 0, toIndex: 1, color: const Color(0x26F44336)),
          if (showBands && diaLower.isNotEmpty && diaUpper.isNotEmpty)
            BetweenBarsData(fromIndex: 2, toIndex: 3, color: const Color(0x1F2196F3)),
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
  final List<_BPEntry> seriesA;
  final List<_BPEntry> seriesB;
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  const _AverageDayCompareChart({required this.seriesA, required this.seriesB, this.anchorMinute, this.showBands = false});

  @override
  Widget build(BuildContext context) {
    final aggA = _AverageDayAggregator(series: seriesA)
        .compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute, withBands: showBands);
    final aggB = _AverageDayAggregator(series: seriesB)
        .compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute, withBands: showBands);
    final aSys = <FlSpot>[];
    final aDia = <FlSpot>[];
    final bSys = <FlSpot>[];
    final bDia = <FlSpot>[];
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
      LineChartBarData(spots: aSys, isCurved: true, curveSmoothness: 0.25, color: Colors.red, barWidth: 2, dotData: const FlDotData(show: false)),
      LineChartBarData(spots: aDia, isCurved: true, curveSmoothness: 0.25, color: Colors.blue, barWidth: 2, dotData: const FlDotData(show: false)),
      LineChartBarData(spots: bSys, isCurved: true, curveSmoothness: 0.25, color: Colors.orange, barWidth: 2, dotData: const FlDotData(show: false)),
      LineChartBarData(spots: bDia, isCurved: true, curveSmoothness: 0.25, color: Colors.lightBlue, barWidth: 2, dotData: const FlDotData(show: false)),
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
        lineBarsData: bars,
        betweenBarsData: [
          // Between-lines shading only (A vs B) for both SBP and DBP
          BetweenBarsData(fromIndex: 0, toIndex: 2, color: const Color(0x33FFA500)), // SBP A vs B
          BetweenBarsData(fromIndex: 1, toIndex: 3, color: const Color(0x331E90FF)), // DBP A vs B
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

  _AvgDay compute({int stepMinutes = 15, int smoothMinutes = 45, int? anchorMinute, bool withBands = false}) {
    final step = stepMinutes;
    final bins = (24 * 60) ~/ step;
    final days = <DateTime, _DayBins>{};

    double clamp(double v) => v.clamp(40.0, 220.0);

    for (final e in series) {
      final t = e.timestamp;
      if (t == null) continue;
      final dayKey = DateTime(t.year, t.month, t.day);
      final d = days.putIfAbsent(dayKey, () => _DayBins(bins));
      var m = t.hour * 60 + t.minute + t.second / 60.0;
      if (anchorMinute != null) {
        m = (m - anchorMinute) % 1440;
        if (m < 0) m += 1440;
      }
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

    List<int> countOfDays(List<List<double?>> perDay) {
      final out = List<int>.filled(bins, 0);
      for (int i = 0; i < bins; i++) {
        int n = 0;
        for (final day in perDay) {
          if (day[i] != null) n++;
        }
        out[i] = n;
      }
      return out;
    }
    List<double?> stdOfDays(List<List<double?>> perDay, List<double?> mean) {
      final out = List<double?>.filled(bins, null);
      for (int i = 0; i < bins; i++) {
        double sum2 = 0;
        int n = 0;
        for (final day in perDay) {
          final v = day[i];
          if (v != null && mean[i] != null) {
            final d = v - mean[i]!;
            sum2 += d * d;
            n++;
          }
        }
        if (n > 1) out[i] = math.sqrt(sum2 / (n - 1));
      }
      return out;
    }

    final sysN = countOfDays(perDaySys);
    final diaN = countOfDays(perDayDia);
    var sysStd = stdOfDays(perDaySys, sysMean);
    var diaStd = stdOfDays(perDayDia, diaMean);

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
    if (withBands) {
      sysStd = smooth(sysStd);
      diaStd = smooth(diaStd);
    }

    final minutes = List<int>.generate(bins, (i) => i * step);
    List<double?>? lower(List<double?> mean, List<double?> std, List<int> n) {
      final out = List<double?>.filled(mean.length, null);
      for (int i = 0; i < mean.length; i++) {
        if (withBands && mean[i] != null && std[i] != null && n[i] > 1) {
          final se = std[i]! / math.sqrt(n[i]);
          out[i] = mean[i]! - 1.96 * se;
        }
      }
      return out;
    }
    List<double?>? upper(List<double?> mean, List<double?> std, List<int> n) {
      final out = List<double?>.filled(mean.length, null);
      for (int i = 0; i < mean.length; i++) {
        if (withBands && mean[i] != null && std[i] != null && n[i] > 1) {
          final se = std[i]! / math.sqrt(n[i]);
          out[i] = mean[i]! + 1.96 * se;
        }
      }
      return out;
    }

    return _AvgDay(
      minutes: minutes,
      sysMean: sysSmooth,
      diaMean: diaSmooth,
      sysLower: withBands ? lower(sysSmooth, sysStd, sysN) : null,
      sysUpper: withBands ? upper(sysSmooth, sysStd, sysN) : null,
      diaLower: withBands ? lower(diaSmooth, diaStd, diaN) : null,
      diaUpper: withBands ? upper(diaSmooth, diaStd, diaN) : null,
    );
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
  final List<double?>? sysLower; // optional 95% CI lower
  final List<double?>? sysUpper;
  final List<double?>? diaLower;
  final List<double?>? diaUpper;
  _AvgDay({
    required this.minutes,
    required this.sysMean,
    required this.diaMean,
    this.sysLower,
    this.sysUpper,
    this.diaLower,
    this.diaUpper,
  });
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

class _SummaryCards extends StatelessWidget {
  final _ViewMode mode;
  final List<_BPEntry> series;
  final List<_BPEntry>? seriesA;
  final List<_BPEntry>? seriesB;
  final int? anchorMinute;
  const _SummaryCards({required this.mode, required this.series, this.seriesA, this.seriesB, this.anchorMinute});

  @override
  Widget build(BuildContext context) {
    if (mode == _ViewMode.trend && series.isEmpty) return const SizedBox.shrink();
    if (mode == _ViewMode.averageDay && series.isEmpty) return const SizedBox.shrink();
    if (mode == _ViewMode.compare && (seriesA == null || seriesB == null)) return const SizedBox.shrink();

    late final List<_CardData> cards;
    if (mode == _ViewMode.compare) {
      final aggA = _AverageDayAggregator(series: seriesA!).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      final aggB = _AverageDayAggregator(series: seriesB!).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      cards = _buildCompareCards(aggA, aggB);
    } else {
      final agg = _AverageDayAggregator(series: series).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      cards = _buildSingleCards(agg);
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final c in cards) _SummaryCard(data: c)],
    );
  }

  List<_CardData> _buildSingleCards(_AvgDay agg) {
    final segs = _segments();
    return [
      for (final s in segs)
        _CardData(
          title: s.label,
          sbp: _segMean(agg.minutes, agg.sysMean, s.startMin, s.endMin),
          dbp: _segMean(agg.minutes, agg.diaMean, s.startMin, s.endMin),
        )
    ];
  }

  List<_CardData> _buildCompareCards(_AvgDay a, _AvgDay b) {
    final segs = _segments();
    return [
      for (final s in segs)
        _CardData(
          title: s.label,
          deltaSbp: _segDelta(a.minutes, a.sysMean, b.minutes, b.sysMean, s.startMin, s.endMin),
          deltaDbp: _segDelta(a.minutes, a.diaMean, b.minutes, b.diaMean, s.startMin, s.endMin),
          isDelta: true,
        )
    ];
  }

  double? _segMean(List<int> mins, List<double?> values, int startMin, int endMin) {
    double sum = 0; int n = 0;
    for (int i = 0; i < mins.length; i++) {
      final m = mins[i];
      if (_inSeg(m, startMin, endMin)) {
        final v = values[i];
        if (v != null) { sum += v; n++; }
      }
    }
    return n > 0 ? sum / n : null;
  }

  double? _segDelta(List<int> amins, List<double?> a, List<int> bmins, List<double?> b, int startMin, int endMin) {
    // assume same binning; align by minute index
    final meanA = _segMean(amins, a, startMin, endMin);
    final meanB = _segMean(bmins, b, startMin, endMin);
    if (meanA == null || meanB == null) return null;
    return meanB - meanA;
  }

  bool _inSeg(int minuteOfDay, int startMin, int endMin) {
    if (startMin <= endMin) return minuteOfDay >= startMin && minuteOfDay < endMin;
    // wrap
    return minuteOfDay >= startMin || minuteOfDay < endMin;
  }

  List<_Segment> _segments() {
    // Minutes since midnight; anchor handled upstream
    return const [
      _Segment('Morning', 6 * 60, 10 * 60),
      _Segment('Midday', 10 * 60, 16 * 60),
      _Segment('Evening', 16 * 60, 22 * 60),
      _Segment('Night', 22 * 60, 6 * 60), // wraps
    ];
  }
}

class _Segment {
  final String label; final int startMin; final int endMin;
  const _Segment(this.label, this.startMin, this.endMin);
}

class _CardData {
  final String title;
  final double? sbp; final double? dbp; // for single
  final double? deltaSbp; final double? deltaDbp; // for compare
  final bool isDelta;
  _CardData({required this.title, this.sbp, this.dbp, this.deltaSbp, this.deltaDbp, this.isDelta = false});
}

class _SummaryCard extends StatelessWidget {
  final _CardData data;
  const _SummaryCard({required this.data});
  @override
  Widget build(BuildContext context) {
    TextStyle h = const TextStyle(fontWeight: FontWeight.bold);
    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.title, style: h),
            const SizedBox(height: 6),
            if (!data.isDelta)
              Row(children: [
                Text('SBP: ${_f(data.sbp)} mmHg'), const SizedBox(width: 12),
                Text('DBP: ${_f(data.dbp)} mmHg'),
              ])
            else
              Row(children: [
                Text('ΔSBP: ${_fSigned(data.deltaSbp)} mmHg'), const SizedBox(width: 12),
                Text('ΔDBP: ${_fSigned(data.deltaDbp)} mmHg'),
              ]),
          ],
        ),
      ),
    );
  }

  String _f(double? v) => v == null ? '-' : v.toStringAsFixed(0);
  String _fSigned(double? v) => v == null ? '-' : (v >= 0 ? '+${v.toStringAsFixed(0)}' : v.toStringAsFixed(0));
}
