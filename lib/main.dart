import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:health/health.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

// Build blood pressure category background when only one metric is visible
RangeAnnotations _zoneAnnotations({required bool showSys, required bool showDia}) {
  if (showSys == showDia) return const RangeAnnotations();
  final isSys = showSys && !showDia;
  final bands = <HorizontalRangeAnnotation>[];
  if (isSys) {
    bands.addAll([
      HorizontalRangeAnnotation(y1: 0, y2: 120, color: const Color(0x1128A745)), // green
      HorizontalRangeAnnotation(y1: 120, y2: 130, color: const Color(0x11FFC107)), // yellow
      HorizontalRangeAnnotation(y1: 130, y2: 140, color: const Color(0x11FF9800)), // orange
      HorizontalRangeAnnotation(y1: 140, y2: 180, color: const Color(0x11F44336)), // red
      HorizontalRangeAnnotation(y1: 180, y2: 300, color: const Color(0x11B71C1C)), // dark red
    ]);
  } else {
    bands.addAll([
      HorizontalRangeAnnotation(y1: 0, y2: 80, color: const Color(0x1128A745)),
      HorizontalRangeAnnotation(y1: 80, y2: 90, color: const Color(0x11FFC107)),
      HorizontalRangeAnnotation(y1: 90, y2: 120, color: const Color(0x11F44336)),
      HorizontalRangeAnnotation(y1: 120, y2: 300, color: const Color(0x11B71C1C)),
    ]);
  }
  return RangeAnnotations(horizontalRangeAnnotations: bands);
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
  // Series visibility and trend style
  bool _showSys = true;
  bool _showDia = true;
  bool _trendDistribution = false; // false: lines/points, true: distribution band
  bool _trendTooltips = true; // tooltips for trend (esp. distribution medians)
  bool _trendSmoothing = false; // smooth daily quantiles in distribution view
  int _trendSmoothDays = 7; // odd window length in days for smoothing
  String _trendSmoothMethod = 'ma'; // 'ma' or 'ema'
  bool _trendSmoothAuto = true; // tie window to range length
  String _secondMetric = 'none'; // 'none','resting_hr','steps','sleep'
  _BPEntry? _latest;
  List<_BPEntry> _series = const [];
  List<_SecPoint> _secSeries = const [];
  int _listLimit = 100;
  bool _listLoadingMore = false;
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
    _trendSmoothing = prefs.getBool('trend_smoothing') ?? _trendSmoothing;
    _trendSmoothDays = prefs.getInt('trend_smooth_days') ?? _trendSmoothDays;
    _trendSmoothMethod = prefs.getString('trend_smooth_method') ?? _trendSmoothMethod;
    _trendSmoothAuto = prefs.getBool('trend_smooth_auto') ?? _trendSmoothAuto;
    _trendTooltips = prefs.getBool('trend_tooltips') ?? _trendTooltips;
    _trendDistribution = prefs.getBool('trend_distribution') ?? _trendDistribution;
    _secondMetric = prefs.getString('second_metric') ?? _secondMetric;
    await _loadEvents(prefs);
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
    await prefs.setBool('trend_smoothing', _trendSmoothing);
    await prefs.setInt('trend_smooth_days', _trendSmoothDays);
    await prefs.setString('trend_smooth_method', _trendSmoothMethod);
    await prefs.setBool('trend_smooth_auto', _trendSmoothAuto);
    await prefs.setBool('trend_tooltips', _trendTooltips);
    await prefs.setBool('trend_distribution', _trendDistribution);
    await prefs.setString('second_metric', _secondMetric);
    await _saveEvents(prefs);
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
      // Secondary metric
      List<_SecPoint> sec = const [];
      if (_secondMetric != 'none') {
        sec = await _fetchSecondary(_rangeStart, _rangeEnd);
      }
      final latest = series.isNotEmpty ? series.last : null;
      setState(() {
        _latest = latest;
        _series = series;
        _secSeries = sec;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<_SecPoint>> _fetchSecondary(DateTime start, DateTime end) async {
    HealthDataType? t;
    switch (_secondMetric) {
      case 'resting_hr': t = HealthDataType.RESTING_HEART_RATE; break;
      case 'steps': t = HealthDataType.STEPS; break;
      case 'sleep': t = HealthDataType.SLEEP_ASLEEP; break;
      default: return const [];
    }
    try {
      final pts = await _health.getHealthDataFromTypes(types: [t], startTime: start, endTime: end);
      final byDay = <DateTime, List<double>>{};
      for (final p in pts) {
        final day = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
        final v = _toDouble(p.value);
        if (v == null) continue;
        (byDay[day] ??= []).add(v);
      }
      final out = <_SecPoint>[];
      for (final e in byDay.entries) {
        final vals = e.value;
        final agg = (_secondMetric == 'steps' || _secondMetric == 'sleep') ? vals.fold(0.0, (a,b)=>a+b) : (vals.reduce((a,b)=>a+b)/vals.length);
        out.add(_SecPoint(date: e.key, value: agg));
      }
      out.sort((a,b)=>a.date.compareTo(b.date));
      return out;
    } catch (_) {
      return const [];
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

  Future<void> _loadMoreReadings() async {
    if (_listLoadingMore) return;
    setState(() => _listLoadingMore = true);
    try {
      // Extend window 90 days earlier and refetch
      _rangeStart = _rangeStart.subtract(const Duration(days: 90));
      _isCustomRange = true;
      await _fetchData();
      setState(() => _listLimit += 100);
      await _savePrefs();
    } finally {
      if (mounted) setState(() => _listLoadingMore = false);
    }
  }

  Future<void> _loadMoreReadingsCompare() async {
    if (_listLoadingMore || _rangeA == null || _rangeB == null) return;
    setState(() => _listLoadingMore = true);
    try {
      _rangeA = DateTimeRange(start: _rangeA!.start.subtract(const Duration(days: 90)), end: _rangeA!.end);
      _rangeB = DateTimeRange(start: _rangeB!.start.subtract(const Duration(days: 90)), end: _rangeB!.end);
      await _savePrefs();
      await _fetchCompare();
      setState(() => _listLimit += 100);
    } finally {
      if (mounted) setState(() => _listLoadingMore = false);
    }
  }

  // ---------- Events (bookmarks) ----------
  List<_Event> _events = const [];
  Future<void> _loadEvents(SharedPreferences prefs) async {
    final json = prefs.getStringList('events_json') ?? [];
    final list = <_Event>[];
    for (final s in json) {
      try {
        final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
        list.add(_Event(
          id: m['id'] as String,
          title: m['title'] as String,
          date: DateTime.parse(m['date'] as String),
        ));
      } catch (_) {}
    }
    _events = list..sort((a,b)=>b.date.compareTo(a.date));
  }

  Future<void> _saveEvents(SharedPreferences prefs) async {
    final strs = _events.map((e) => jsonEncode({'id': e.id, 'title': e.title, 'date': e.date.toIso8601String()})).toList();
    await prefs.setStringList('events_json', strs);
  }

  Future<void> _addEvent(String title, DateTime date) async {
    final e = _Event(id: 'evt_${DateTime.now().microsecondsSinceEpoch}', title: title, date: DateTime(date.year, date.month, date.day));
    setState(() => _events = [e, ..._events]..sort((a,b)=>b.date.compareTo(a.date)));
    await _savePrefs();
  }
  Future<void> _renameEvent(String id, String title) async {
    setState(() => _events = _events.map((e)=> e.id==id? e.copyWith(title: title): e).toList());
    await _savePrefs();
  }
  Future<void> _deleteEvent(String id) async {
    setState(() => _events = _events.where((e)=>e.id!=id).toList());
    await _savePrefs();
  }
  Future<void> _setRangeFromEvent(_Event e) async {
    setState(() {
      _isCustomRange = true;
      _rangeStart = DateTime(e.date.year, e.date.month, e.date.day);
      _rangeEnd = _rangeStart.add(Duration(days: _rangeDays));
    });
    await _savePrefs();
    await _fetchData();
  }
  Future<void> _setRangeAFromEvent(_Event e) async {
    setState(() {
      _rangeA = DateTimeRange(start: DateTime(e.date.year,e.date.month,e.date.day), end: DateTime(e.date.year,e.date.month,e.date.day).add(Duration(days: _rangeDays)));
    });
    await _savePrefs();
  }
  Future<void> _setRangeBFromEvent(_Event e) async {
    setState(() {
      _rangeB = DateTimeRange(start: DateTime(e.date.year,e.date.month,e.date.day), end: DateTime(e.date.year,e.date.month,e.date.day).add(Duration(days: _rangeDays)));
    });
    await _savePrefs();
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
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _loading ? null : _exportPdf,
            tooltip: 'Export PDF',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _openAdvancedSettings,
            tooltip: 'Advanced Settings',
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                if (_mode == _ViewMode.trend)
                  ToggleButtons(
                    isSelected: [!_trendDistribution, _trendDistribution],
                    onPressed: (i) { setState(() => _trendDistribution = (i == 1)); _savePrefs(); },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Lines')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Distribution')),
                    ],
                  ),
                IconButton(icon: const Icon(Icons.info_outline), tooltip: 'Chart help', onPressed: _showHelp),
                // Secondary axis selector (Trend only)
                if (_mode == _ViewMode.trend)
                  Row(children: [
                    const SizedBox(width: 12),
                    const Text('Secondary'),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: _secondMetric,
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None')),
                        DropdownMenuItem(value: 'resting_hr', child: Text('Resting HR')),
                        DropdownMenuItem(value: 'steps', child: Text('Steps')),
                        DropdownMenuItem(value: 'sleep', child: Text('Sleep (min)')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(()=> _secondMetric = v);
                        await _savePrefs();
                        await _fetchData();
                      },
                    ),
                  ]),
                if (_mode == _ViewMode.trend && _trendDistribution)
                  Row(children: [
                    const Text('Tooltips'),
                    const SizedBox(width: 6),
                    Switch(value: _trendTooltips, onChanged: (v){ setState(()=> _trendTooltips = v); _savePrefs(); }),
                    const SizedBox(width: 12),
                    const Text('Smoothing'),
                    const SizedBox(width: 6),
                    Switch(value: _trendSmoothing, onChanged: (v){ setState(()=> _trendSmoothing = v); _savePrefs(); }),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Window: ${_trendSmoothDays}d', style: const TextStyle(fontSize: 12)),
                          Slider(
                            value: _trendSmoothDays.toDouble(),
                            min: 3,
                            max: 15,
                            divisions: 6,
                            label: '${_trendSmoothDays}d',
                            onChanged: _trendSmoothing ? (v) {
                              int d = v.round();
                              if (d % 2 == 0) d += 1; // force odd
                              if (d < 3) d = 3; if (d > 15) d = 15;
                              setState(() => _trendSmoothDays = d);
                              _savePrefs();
                            } : null,
                          ),
                        ],
                      ),
                    ),
                  ]),
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
            // Legend with toggles (tap to enable/disable)
            if (_mode != _ViewMode.compare)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegendToggle(
                    color: Colors.red,
                    label: 'Systolic (mmHg)',
                    enabled: _showSys,
                    onTap: () => setState(() => _showSys = !_showSys),
                  ),
                  _LegendToggle(
                    color: Colors.blue,
                    label: 'Diastolic (mmHg)',
                    enabled: _showDia,
                    onTap: () => setState(() => _showDia = !_showDia),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: const [
                  _LegendDot(color: Colors.red), Text('A: Systolic'),
                  _LegendDot(color: Colors.blue), Text('A: Diastolic'),
                  _LegendDot(color: Colors.orange), Text('B: Systolic'),
                  _LegendDot(color: Colors.lightBlue), Text('B: Diastolic'),
                ],
              ),
            const SizedBox(height: 8),
            // Event chips (quick bookmarks)
            if (_mode != _ViewMode.compare)
              _EventChips(
                events: _events.take(5).toList(),
                onTap: _setRangeFromEvent,
                onMore: _openAdvancedSettings,
              )
            else
              _EventChips(
                events: _events.take(5).toList(),
                onTapA: _setRangeAFromEvent,
                onTapB: _setRangeBFromEvent,
                onMore: _openAdvancedSettings,
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
                    ? _TrendChart(
                        series: _series,
                        start: _rangeStart,
                        end: _rangeEnd,
                        showSys: _showSys,
                        showDia: _showDia,
                        distribution: _trendDistribution,
                        tooltipsEnabled: _trendTooltips,
                        smoothingEnabled: _trendSmoothing,
                        smoothingWindowDays: _trendSmoothDays,
                        smoothingMethod: _trendSmoothMethod,
                        secondary: _secSeries,
                        secondaryLabel: _secondMetric,
                      )
                    : _AverageDayChart(
                        series: _series,
                        anchorMinute: _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null,
                        showBands: _showBands,
                        showSys: _showSys,
                        showDia: _showDia,
                      ),
              )
            else
              const Text('No data available for selected range.'),
            const SizedBox(height: 6),
            if (_mode != _ViewMode.compare) Text(_effectiveRangeLabel(_series, _rangeStart, _rangeEnd), style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            _SummaryCards(
              mode: _mode,
              series: _series,
              seriesA: _seriesA,
              seriesB: _seriesB,
              anchorMinute: _anchorToDose && _doseTime != null ? _doseTime!.hour * 60 + _doseTime!.minute : null,
            ),
            const SizedBox(height: 16),
            _ReadingsSection(
              mode: _mode,
              entries: _series,
              entriesA: _seriesA,
              entriesB: _seriesB,
              limit: _listLimit,
              loading: _listLoadingMore,
              onLoadMore: _mode == _ViewMode.compare ? _loadMoreReadingsCompare : _loadMoreReadings,
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

  Future<void> _openAdvancedSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final titleCtl = TextEditingController();
        DateTime newEventDate = DateTime.now();
        return StatefulBuilder(builder: (context, setSt) {
          Future<void> pickDate() async {
            final picked = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: newEventDate);
            if (picked != null) setSt(()=> newEventDate = picked);
          }
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Advanced Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Trend Smoother'),
                  Row(children: [
                    Expanded(child: RadioListTile<String>(title: const Text('Moving Average'), value: 'ma', groupValue: _trendSmoothMethod, onChanged: (v){ setState(()=> _trendSmoothMethod = v!); _savePrefs();})),
                    Expanded(child: RadioListTile<String>(title: const Text('EMA'), value: 'ema', groupValue: _trendSmoothMethod, onChanged: (v){ setState(()=> _trendSmoothMethod = v!); _savePrefs();})),
                  ]),
                  Row(children: [
                    const Text('Auto window'),
                    const SizedBox(width: 6),
                    Switch(value: _trendSmoothAuto, onChanged: (v){ setState(()=> _trendSmoothAuto = v); if(v){ _applyAutoWindow(); } _savePrefs();}),
                    const SizedBox(width: 12),
                    if(!_trendSmoothAuto)
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Window: ${_trendSmoothDays}d', style: const TextStyle(fontSize: 12)),
                        Slider(value: _trendSmoothDays.toDouble(), min: 3, max: 15, divisions: 6, label: '${_trendSmoothDays}d', onChanged: (v){ int d = v.round(); if(d%2==0) d+=1; setState(()=> _trendSmoothDays = d); _savePrefs();}),
                      ])),
                  ]),
                  const Divider(),
                  const Text('Events (Bookmarks)'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.date_range), label: Text('${newEventDate.month}/${newEventDate.day}/${newEventDate.year}')),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(onPressed: () async { if(titleCtl.text.trim().isEmpty) return; await _addEvent(titleCtl.text.trim(), newEventDate); titleCtl.clear(); setSt((){}); }, icon: const Icon(Icons.add), label: const Text('Add')),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: ListView.separated(itemBuilder: (_,i){ final e = _events[i]; return ListTile(
                    title: Text('${e.title} — ${e.date.year}-${e.date.month.toString().padLeft(2,'0')}-${e.date.day.toString().padLeft(2,'0')}'),
                    trailing: Wrap(spacing:6, children: [
                      OutlinedButton(onPressed: (){ _setRangeFromEvent(e); }, child: const Text('Set Range')),
                      OutlinedButton(onPressed: (){ _setRangeAFromEvent(e); }, child: const Text('Set A')),
                      OutlinedButton(onPressed: (){ _setRangeBFromEvent(e); }, child: const Text('Set B')),
                      IconButton(onPressed: () async {
                        final t = await _promptText(context, 'Rename Event', e.title);
                        if (t!=null && t.trim().isNotEmpty) { await _renameEvent(e.id, t.trim()); setSt((){}); }
                      }, icon: const Icon(Icons.edit)),
                      IconButton(onPressed: (){ _deleteEvent(e.id); setSt((){}); }, icon: const Icon(Icons.delete)),
                    ]),
                  ); }, separatorBuilder: (_, __)=> const Divider(height:1), itemCount: _events.length)),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
          );
        });
      },
    );
  }

  String _fmtDate(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
  String _fmtTime(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  void _showHelp() {
    showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Chart Help'),
        content: const SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trend vs Distribution'),
              SizedBox(height: 8),
              Text('• Lines: plots individual readings over calendar time.'),
              Text('• Distribution: summarizes each day with median (line) and IQR (shaded band). Days with no readings are filled by interpolation.'),
              SizedBox(height: 12),
              Text('Smoothing'),
              SizedBox(height: 8),
              Text('• Applies a moving average (MA) or exponential moving average (EMA) over daily medians/IQR.'),
              Text('• Window can be auto-tied to the date range or set manually (odd days).'),
              SizedBox(height: 12),
              Text('BP Zones'),
              SizedBox(height: 8),
              Text('• Background color bands appear when only one metric is enabled.'),
              Text('• SBP: <120 green, 120–129 yellow, 130–139 orange, 140–179 red, 180+ dark red.'),
              Text('• DBP: <80 green, 80–89 yellow, 90–119 red, 120+ dark red.'),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Close'))],
      );
    });
  }

  Future<String?> _promptText(BuildContext context, String title, String initial) async {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(context: context, builder: (ctx){
      return AlertDialog(title: Text(title), content: TextField(controller: ctl), actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: ()=> Navigator.pop(ctx, ctl.text), child: const Text('Save')),
      ]);
    });
  }

  void _applyAutoWindow() {
    final days = _rangeEnd.difference(_rangeStart).inDays.abs();
    int w;
    if (days <= 14) {
      w = 3;
    } else if (days <= 45) {
      w = 7;
    } else if (days <= 120) {
      w = 14;
    } else {
      w = 21;
    }
    if (w % 2 == 0) w += 1;
    setState(()=> _trendSmoothDays = w);
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

  Future<void> _exportPdf() async {
    try {
      final doc = pw.Document();
      final eff = _effectiveRangeLabel(_series, _rangeStart, _rangeEnd);
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) {
            final rows = <pw.TableRow>[];
            rows.add(pw.TableRow(children: [pw.Text('Date'), pw.Text('Time'), pw.Text('SBP'), pw.Text('DBP'), pw.Text('Source')]));
            final list = [..._series]..sort((a,b)=> (b.timestamp??DateTime(0)).compareTo(a.timestamp??DateTime(0)));
            for (final e in list.take(50)) {
              rows.add(pw.TableRow(children: [
                pw.Text(_fmtDate(e.timestamp)),
                pw.Text(_fmtTime(e.timestamp)),
                pw.Text(e.systolic?.toStringAsFixed(0) ?? '-'),
                pw.Text(e.diastolic?.toStringAsFixed(0) ?? '-'),
                pw.Text(e.source ?? ''),
              ]));
            }
            return [
              pw.Text('Blood Pressure Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text(eff),
              pw.SizedBox(height: 12),
              pw.Text('Recent Readings (up to 50)'),
              pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: rows),
            ];
          },
        ),
      );
      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'bp_report.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
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

class _SecPoint {
  final DateTime date;
  final double value;
  const _SecPoint({required this.date, required this.value});
}

class _TrendChart extends StatelessWidget {
  final List<_BPEntry> series;
  final DateTime start;
  final DateTime end;
  final bool showSys;
  final bool showDia;
  final bool distribution; // if true, show daily quantile bands
  final bool tooltipsEnabled;
  final String smoothingMethod; // 'ma' or 'ema'
  final bool smoothingEnabled;
  const _TrendChart({
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
  });
  final int smoothingWindowDays;
  final List<_SecPoint> secondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    // Effective range based on data
    DateTime effStart = start, effEnd = end;
    final times = series.where((e) => e.timestamp != null).map((e) => e.timestamp!).toList()..sort();
    if (times.isNotEmpty) {
      if (times.first.isAfter(effStart)) effStart = times.first;
      if (times.last.isBefore(effEnd)) effEnd = times.last;
      if (!effEnd.isAfter(effStart)) effEnd = effStart.add(const Duration(days: 1));
    }
    double toX(DateTime t) => t.difference(effStart).inMinutes / 1440.0;

    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (final e in series) {
      final t = e.timestamp; if (t == null) continue;
      final x = toX(t);
      if (showSys && e.systolic != null) sysSpots.add(FlSpot(x, e.systolic!));
      if (showDia && e.diastolic != null) diaSpots.add(FlSpot(x, e.diastolic!));
    }
    final maxX = effEnd.difference(effStart).inDays.toDouble().clamp(1.0, 365.0);

    // Distribution mode: per-day quantiles (with gap filling by linear interpolation)
    List<FlSpot> q50Sys = [], q25Sys = [], q75Sys = [];
    List<FlSpot> q50Dia = [], q25Dia = [], q75Dia = [];
    if (distribution) {
      final byDay = <DateTime, List<_BPEntry>>{};
      for (final e in series) {
        if (e.timestamp == null) continue;
        final day = DateTime(e.timestamp!.year, e.timestamp!.month, e.timestamp!.day);
        (byDay[day] ??= []).add(e);
      }
      // Build continuous day list from effStart..effEnd
      final days = <DateTime>[];
      DateTime cur = DateTime(effStart.year, effStart.month, effStart.day);
      final last = DateTime(effEnd.year, effEnd.month, effEnd.day);
      while (!cur.isAfter(last)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
      List<double?> mSys = List.filled(days.length, null), p25Sys = List.filled(days.length, null), p75SysL = List.filled(days.length, null);
      List<double?> mDia = List.filled(days.length, null), p25Dia = List.filled(days.length, null), p75DiaL = List.filled(days.length, null);
      for (int i = 0; i < days.length; i++) {
        final d = days[i];
        final list = byDay[d];
        if (list != null && showSys) {
          final vals = list.where((e) => e.systolic != null).map((e) => e.systolic!).toList()..sort();
          if (vals.isNotEmpty) { mSys[i] = _q(vals,0.5); p25Sys[i] = _q(vals,0.25); p75SysL[i] = _q(vals,0.75); }
        }
        if (list != null && showDia) {
          final vals = list.where((e) => e.diastolic != null).map((e) => e.diastolic!).toList()..sort();
          if (vals.isNotEmpty) { mDia[i] = _q(vals,0.5); p25Dia[i] = _q(vals,0.25); p75DiaL[i] = _q(vals,0.75); }
        }
      }
      // Linear interpolate gaps
      void interp(List<double?> a) {
        int n = a.length;
        int i = 0;
        while (i < n) {
          if (a[i] != null) { i++; continue; }
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
      if (showSys) { interp(mSys); interp(p25Sys); interp(p75SysL); }
      if (showDia) { interp(mDia); interp(p25Dia); interp(p75DiaL); }

      // Optional smoothing (moving average with half-window=2 -> 5-day window)
      List<double?> smoothMA(List<double?> a, int halfWin) {
        final n = a.length;
        final out = List<double?>.filled(n, null);
        for (int i = 0; i < n; i++) {
          int s = (i - halfWin).clamp(0, n - 1);
          int e = (i + halfWin).clamp(0, n - 1);
          double sum = 0; int c = 0;
          for (int k = s; k <= e; k++) { final v = a[k]; if (v != null) { sum += v; c++; } }
          out[i] = c > 0 ? sum / c : a[i];
        }
        return out;
      }
      List<double?> smoothEMA(List<double?> a, int windowDays) {
        final n = a.length;
        final alpha = 2 / (windowDays + 1);
        // forward pass
        final f = List<double?>.filled(n, null);
        double? prev;
        for (int i = 0; i < n; i++) {
          final v = a[i];
          if (v == null) { f[i] = prev; continue; }
          prev = (prev == null) ? v : (alpha * v + (1 - alpha) * prev);
          f[i] = prev;
        }
        // backward pass
        final b = List<double?>.filled(n, null);
        prev = null;
        for (int i = n - 1; i >= 0; i--) {
          final v = a[i];
          if (v == null) { b[i] = prev; continue; }
          prev = (prev == null) ? v : (alpha * v + (1 - alpha) * prev);
          b[i] = prev;
        }
        // average for zero-phase
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
          if (showSys) { mSys = smoothMA(mSys, half); p25Sys = smoothMA(p25Sys, half); p75SysL = smoothMA(p75SysL, half); }
          if (showDia) { mDia = smoothMA(mDia, half); p25Dia = smoothMA(p25Dia, half); p75DiaL = smoothMA(p75DiaL, half); }
        }
      }
      for (int i = 0; i < days.length; i++) {
        final x = toX(days[i]);
        if (showSys) {
          if (p25Sys[i] != null) q25Sys.add(FlSpot(x, p25Sys[i]!));
          if (p75SysL[i] != null) q75Sys.add(FlSpot(x, p75SysL[i]!));
          if (mSys[i] != null) q50Sys.add(FlSpot(x, mSys[i]!));
        }
        if (showDia) {
          if (p25Dia[i] != null) q25Dia.add(FlSpot(x, p25Dia[i]!));
          if (p75DiaL[i] != null) q75Dia.add(FlSpot(x, p75DiaL[i]!));
          if (mDia[i] != null) q50Dia.add(FlSpot(x, mDia[i]!));
        }
      }
    }

    double minY = 200, maxY = 40;
    void acc(List<FlSpot> s) { for (final p in s) { if (p.y < minY) minY = p.y; if (p.y > maxY) maxY = p.y; } }
    if (!distribution) { acc(sysSpots); acc(diaSpots); } else { acc(q25Sys); acc(q75Sys); acc(q25Dia); acc(q75Dia); acc(q50Sys); acc(q50Dia); }
    if (minY > maxY) { minY = 40; maxY = 200; }
    const pad = 10.0;
    minY = (minY - pad).clamp(40.0, 300.0);
    maxY = (maxY + pad).clamp(60.0, 300.0);

    final bars = <LineChartBarData>[];
    final between = <BetweenBarsData>[];
    if (!distribution) {
      if (showSys) bars.add(LineChartBarData(spots: sysSpots, isCurved: true, curveSmoothness: 0.15, color: Colors.red, barWidth: 2, dotData: const FlDotData(show: false)));
      if (showDia) bars.add(LineChartBarData(spots: diaSpots, isCurved: true, curveSmoothness: 0.15, color: Colors.blue, barWidth: 2, dotData: const FlDotData(show: false)));
    } else {
      if (showSys) {
        final base = bars.length;
        bars.add(LineChartBarData(spots: q25Sys, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        bars.add(LineChartBarData(spots: q75Sys, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        between.add(BetweenBarsData(fromIndex: base, toIndex: base + 1, color: const Color(0x26F44336)));
        bars.add(LineChartBarData(spots: q50Sys, isCurved: true, color: Colors.red, barWidth: 2, dotData: FlDotData(show: tooltipsEnabled)));
      }
      if (showDia) {
        final base = bars.length;
        bars.add(LineChartBarData(spots: q25Dia, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        bars.add(LineChartBarData(spots: q75Dia, isCurved: true, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        between.add(BetweenBarsData(fromIndex: base, toIndex: base + 1, color: const Color(0x1F2196F3)));
        bars.add(LineChartBarData(spots: q50Dia, isCurved: true, color: Colors.blue, barWidth: 2, dotData: FlDotData(show: tooltipsEnabled)));
      }
    }

    // Secondary axis mapping if provided
    double? secMin, secMax;
    List<FlSpot> secSpots = [];
    if (secondary.isNotEmpty) {
      secMin = secondary.map((e)=>e.value).reduce(math.min);
      secMax = secondary.map((e)=>e.value).reduce(math.max);
      final leftRange = maxY - minY;
      final secRange = (secMax - secMin).abs() < 1e-6 ? 1.0 : (secMax - secMin);
      for (final s in secondary) {
        final x = toX(s.date);
        final y = minY + (s.value - secMin) * leftRange / secRange;
        secSpots.add(FlSpot(x, y));
      }
      if (secSpots.isNotEmpty) {
        bars.add(LineChartBarData(spots: secSpots, isCurved: true, color: Colors.purple, barWidth: 2, dotData: const FlDotData(show: false)));
      }
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
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
                final d = effStart.add(Duration(days: value.round()));
                return SideTitleWidget(meta: meta, child: Text('${d.month}/${d.day}'));
              },
            ),
            axisNameWidget: const Text('Date'),
            axisNameSize: 16,
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: secondary.isEmpty
                ? const SideTitles(showTitles: false)
                : SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: (secMax != null && secMin != null) ? ((secMax - secMin) / 4).clamp(1, 1000) : 1,
                    getTitlesWidget: (value, meta) {
                      if (secMin == null || secMax == null) return const SizedBox.shrink();
                      final leftRange = maxY - minY;
                      final secRange = (secMax - secMin).abs() < 1e-6 ? 1.0 : (secMax - secMin);
                      final secVal = secMin + (value - minY) * secRange / leftRange;
                      return SideTitleWidget(meta: meta, child: Text(secVal.toStringAsFixed(0)));
                    },
                  ),
          ),
        ),
        lineBarsData: bars,
        betweenBarsData: between,
        lineTouchData: LineTouchData(enabled: tooltipsEnabled),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black12),
            bottom: BorderSide(color: Colors.black12),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
          ),
        ),
        rangeAnnotations: _zoneAnnotations(showSys: showSys, showDia: showDia),
      ),
    );
  }

  static double _q(List<double> sorted, double q) {
    if (sorted.isEmpty) return double.nan;
    final pos = (sorted.length - 1) * q;
    final i = pos.floor();
    final frac = pos - i;
    if (i + 1 < sorted.length) return sorted[i] * (1 - frac) + sorted[i + 1] * frac;
    return sorted[i];
  }
}

class _Event {
  final String id; final String title; final DateTime date;
  const _Event({required this.id, required this.title, required this.date});
  _Event copyWith({String? title, DateTime? date}) => _Event(id: id, title: title ?? this.title, date: date ?? this.date);
}

class _EventChips extends StatelessWidget {
  final List<_Event> events;
  final Future<void> Function(_Event)? onTap;
  final Future<void> Function(_Event)? onTapA;
  final Future<void> Function(_Event)? onTapB;
  final Future<void> Function() onMore;
  const _EventChips({required this.events, this.onTap, this.onTapA, this.onTapB, required this.onMore});
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: onTap != null
                ? ActionChip(
                    label: Text('${e.title} (${e.date.month}/${e.date.day})'),
                    onPressed: () => onTap!(e),
                  )
                : Wrap(spacing: 6, children: [
                    ActionChip(label: Text('A: ${e.title.split(' ').first}'), onPressed: onTapA!=null? ()=> onTapA!(e): null),
                    ActionChip(label: Text('B: ${e.title.split(' ').first}'), onPressed: onTapB!=null? ()=> onTapB!(e): null),
                  ]),
          ),
        ActionChip(label: const Text('More…'), onPressed: onMore),
      ]),
    );
  }
}

class _AverageDayChart extends StatelessWidget {
  final List<_BPEntry> series;
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  final bool showSys;
  final bool showDia;
  const _AverageDayChart({required this.series, this.anchorMinute, this.showBands = false, this.showSys = true, this.showDia = true});

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
    if (showSys) {
      bars.add(LineChartBarData(
        spots: sysSpots,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.red,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ));
    }
    if (showDia) {
      bars.add(LineChartBarData(
        spots: diaSpots,
        isCurved: true,
        curveSmoothness: 0.25,
        color: Colors.blue,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
        minY: _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots]) - 10,
        maxY: _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots]) + 10,
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
        rangeAnnotations: _zoneAnnotations(showSys: showSys, showDia: showDia),
      ),
    );
  }

  double _autoMinY(List<List<FlSpot>> lists) {
    double m = 300;
    for (final l in lists) {
      for (final p in l) { if (p.y < m) m = p.y; }
    }
    if (m == 300) m = 40;
    return m.clamp(40.0, 300.0);
  }
  double _autoMaxY(List<List<FlSpot>> lists) {
    double m = 0;
    for (final l in lists) {
      for (final p in l) { if (p.y > m) m = p.y; }
    }
    if (m == 0) m = 200;
    return m.clamp(60.0, 300.0);
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

class _LegendToggle extends StatelessWidget {
  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _LegendToggle({required this.color, required this.label, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    int to255(double v) => (v * 255.0).round().clamp(0, 255);
    final c = enabled
        ? color
        : Color.fromARGB(
            to255(0.3),
            to255(color.r),
            to255(color.g),
            to255(color.b),
          );
    final t = enabled ? null : Colors.black45;
    return InkWell(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: t)),
      ]),
    );
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

class _ReadingsSection extends StatelessWidget {
  final _ViewMode mode;
  final List<_BPEntry> entries;
  final List<_BPEntry>? entriesA;
  final List<_BPEntry>? entriesB;
  final int limit;
  final bool loading;
  final Future<void> Function() onLoadMore;

  const _ReadingsSection({
    required this.mode,
    required this.entries,
    required this.limit,
    required this.loading,
    required this.onLoadMore,
    this.entriesA,
    this.entriesB,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Readings', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (mode != _ViewMode.compare)
          _buildList(context, entries)
        else ...[
          const Text('Range A'),
          const SizedBox(height: 6),
          if (entriesA != null) _buildList(context, entriesA!) else const Text('-'),
          const SizedBox(height: 12),
          const Text('Range B'),
          const SizedBox(height: 6),
          if (entriesB != null) _buildList(context, entriesB!) else const Text('-'),
        ],
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton.icon(
            onPressed: loading ? null : onLoadMore,
            icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.history),
            label: const Text('Load earlier (90 days)'),
          ),
        ]),
      ],
    );
  }

  Widget _buildList(BuildContext context, List<_BPEntry> src) {
    final list = [...src];
    list.sort((a, b) => (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)));
    final shown = list.take(limit).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(6)),
      child: ListView.separated(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final e = shown[i];
          return ListTile(
            dense: true,
            title: Text(_fmtDate(e.timestamp)),
            subtitle: Text(_fmtTime(e.timestamp)),
            trailing: Text(_bpText(e), style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
      ),
    );
  }

  String _bpText(_BPEntry e) {
    final s = e.systolic != null ? e.systolic!.toStringAsFixed(0) : '-';
    final d = e.diastolic != null ? e.diastolic!.toStringAsFixed(0) : '-';
    return '$s / $d mmHg';
  }

  String _fmtDate(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '-';
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}

String _effectiveRangeLabel(List<_BPEntry> entries, DateTime start, DateTime end) {
  final ts = entries.where((e) => e.timestamp != null).map((e) => e.timestamp!).toList()..sort();
  if (ts.isEmpty) {
    return 'Effective: —';
  }
  final effStart = ts.first.isAfter(start) ? ts.first : start;
  final effEnd = ts.last.isBefore(end) ? ts.last : end;
  final daysWithReadings = ts.map((t) => DateTime(t.year, t.month, t.day)).toSet().length;
  String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  return 'Effective: ${fmt(effStart)} — ${fmt(effEnd)}  •  $daysWithReadings day(s) with readings';
}
