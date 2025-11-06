import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:health/health.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/rendering.dart';
import 'services/metrics.dart' as met;
import 'services/avg_day.dart' as avg;
import 'models/chart_models.dart' as cm;
import 'models/event.dart' as mdl;
import 'widgets/advanced_settings_sheet.dart';
import 'widgets/add_bp_sheet.dart';
import 'widgets/trend_chart.dart';
import 'widgets/average_day_chart.dart';
import 'widgets/average_day_compare_chart.dart';

void main() => runApp(const BPApp());

class BPApp extends StatelessWidget {
  const BPApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Pressure',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: const LatestBPPage(),
    );
  }
}

// BP zone backgrounds now provided by widgets/chart_utils.dart

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
  bool _trendDistribution =
      false; // false: lines/points, true: distribution band
  bool _trendTooltips = true; // tooltips for trend (esp. distribution medians)
  bool _trendSmoothing = false; // smooth daily quantiles in distribution view
  int _trendSmoothDays = 7; // odd window length in days for smoothing
  String _trendSmoothMethod = 'ma'; // 'ma' or 'ema'
  bool _trendSmoothAuto = true; // tie window to range length
  String _secondMetric =
      'none'; // 'none','hr','resting_hr','hrv_sdnn','hrv_rmssd','steps','sleep','energy','workouts'
  // Surge heuristic settings (flexible)
  int _surgeMorningWindowHours = 2; // [wake, wake+X]
  int _surgeTroughWindowHours = 6; // [wake-X, wake)
  int _surgePrewakeHours = 2; // [wake-X, wake)
  int _surgeHrRiseBpm = 10; // HR baseline+X bpm
  int _surgeSteps30Min = 100; // steps in 30 min threshold
  int _surgeWakeEarliestHour = 3; // earliest wake search hour
  int _surgeWakeLatestHour = 11; // latest wake search hour
  // Add-reading defaults
  String _bpBodyPosition = 'sitting'; // sitting, standing, supine
  String _bpArm = 'left_upper_arm'; // left_upper_arm, right_upper_arm, wrist
  _BPEntry? _latest;
  List<_BPEntry> _series = const [];
  List<cm.ChartSecPoint> _secSeries = const [];
  List<cm.ChartSecSample> _secSamples = const [];
  int _listLimit = 100;
  bool _listLoadingMore = false;
  int _rangeDays = 30;
  bool _isCustomRange = false;
  late DateTime _rangeEnd;
  late DateTime _rangeStart;
  _ViewMode _mode = _ViewMode.trend;
  // PDF options
  bool _pdfIncludeBothCharts =
      true; // default to embed both Trend + Average Day
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
    _trendSmoothMethod =
        prefs.getString('trend_smooth_method') ?? _trendSmoothMethod;
    _trendSmoothAuto = prefs.getBool('trend_smooth_auto') ?? _trendSmoothAuto;
    _trendTooltips = prefs.getBool('trend_tooltips') ?? _trendTooltips;
    _trendDistribution =
        prefs.getBool('trend_distribution') ?? _trendDistribution;
    _secondMetric = prefs.getString('second_metric') ?? _secondMetric;
    _bpBodyPosition = prefs.getString('bp_body_position') ?? _bpBodyPosition;
    _bpArm = prefs.getString('bp_arm') ?? _bpArm;
    _pdfIncludeBothCharts =
        prefs.getBool('pdf_include_both_charts') ?? _pdfIncludeBothCharts;
    _surgeMorningWindowHours =
        prefs.getInt('surge_morning_window_h') ?? _surgeMorningWindowHours;
    _surgeTroughWindowHours =
        prefs.getInt('surge_trough_window_h') ?? _surgeTroughWindowHours;
    _surgePrewakeHours = prefs.getInt('surge_prewake_h') ?? _surgePrewakeHours;
    _surgeHrRiseBpm = prefs.getInt('surge_hr_rise_bpm') ?? _surgeHrRiseBpm;
    _surgeSteps30Min = prefs.getInt('surge_steps_30m') ?? _surgeSteps30Min;
    _surgeWakeEarliestHour =
        prefs.getInt('surge_wake_earliest_h') ?? _surgeWakeEarliestHour;
    _surgeWakeLatestHour =
        prefs.getInt('surge_wake_latest_h') ?? _surgeWakeLatestHour;
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
        if (aS != null && aE != null) {
          _rangeA = DateTimeRange(start: aS, end: aE);
        }
      }
      if (bStartIso != null && bEndIso != null) {
        final bS = DateTime.tryParse(bStartIso);
        final bE = DateTime.tryParse(bEndIso);
        if (bS != null && bE != null) {
          _rangeB = DateTimeRange(start: bS, end: bE);
        }
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
    await prefs.setString('bp_body_position', _bpBodyPosition);
    await prefs.setString('bp_arm', _bpArm);
    await prefs.setBool('pdf_include_both_charts', _pdfIncludeBothCharts);
    await _saveEvents(prefs);
    await prefs.setInt('surge_morning_window_h', _surgeMorningWindowHours);
    await prefs.setInt('surge_trough_window_h', _surgeTroughWindowHours);
    await prefs.setInt('surge_prewake_h', _surgePrewakeHours);
    await prefs.setInt('surge_hr_rise_bpm', _surgeHrRiseBpm);
    await prefs.setInt('surge_steps_30m', _surgeSteps30Min);
    await prefs.setInt('surge_wake_earliest_h', _surgeWakeEarliestHour);
    await prefs.setInt('surge_wake_latest_h', _surgeWakeLatestHour);
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
          final histGranted = await _health
              .requestHealthDataHistoryAuthorization();
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
      List<cm.ChartSecPoint> sec = const [];
      if (_secondMetric != 'none') {
        sec = await _fetchSecondary(_rangeStart, _rangeEnd);
        _secSamples = await _fetchSecondarySeries(_rangeStart, _rangeEnd);
      } else {
        _secSamples = const [];
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

  Future<List<cm.ChartSecPoint>> _fetchSecondary(
    DateTime start,
    DateTime end,
  ) async {
    HealthDataType? t;
    switch (_secondMetric) {
      case 'hr':
        t = HealthDataType.HEART_RATE;
        break;
      case 'resting_hr':
        t = HealthDataType.RESTING_HEART_RATE;
        break;
      case 'hrv_sdnn':
        t = HealthDataType.HEART_RATE_VARIABILITY_SDNN;
        break;
      case 'hrv_rmssd':
        t = HealthDataType.HEART_RATE_VARIABILITY_RMSSD;
        break;
      case 'steps':
        t = HealthDataType.STEPS;
        break;
      case 'sleep':
        t = HealthDataType.SLEEP_ASLEEP;
        break;
      case 'energy':
        t = HealthDataType.ACTIVE_ENERGY_BURNED;
        break;
      case 'workouts':
        t = null;
        break; // special handling below
      default:
        return const [];
    }
    try {
      if (_secondMetric == 'workouts') {
        // Prefer EXERCISE_TIME; if unavailable, fall back to WORKOUT durations.
        final byDayMin = <DateTime, double>{};
        try {
          final ex = await _health.getHealthDataFromTypes(
            types: [HealthDataType.EXERCISE_TIME],
            startTime: start,
            endTime: end,
          );
          for (final p in ex) {
            final day = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
            final v = _toDouble(p.value) ?? 0;
            byDayMin[day] = (byDayMin[day] ?? 0) + v;
          }
        } catch (_) {}
        if (byDayMin.isEmpty) {
          try {
            final ws = await _health.getHealthDataFromTypes(
              types: [HealthDataType.WORKOUT],
              startTime: start,
              endTime: end,
            );
            for (final p in ws) {
              final day = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
              final mins = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
              byDayMin[day] = (byDayMin[day] ?? 0) + mins;
            }
          } catch (_) {}
        }
        final out = <cm.ChartSecPoint>[];
        for (final e in byDayMin.entries) {
          out.add(cm.ChartSecPoint(date: e.key, value: e.value));
        }
        out.sort((a, b) => a.date.compareTo(b.date));
        return out;
      }

      final pts = await _health.getHealthDataFromTypes(
        types: [t!],
        startTime: start,
        endTime: end,
      );
      final byDay = <DateTime, List<double>>{};
      for (final p in pts) {
        final day = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
        final v = _toDouble(p.value);
        if (_secondMetric == 'sleep') {
          final dur = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
          (byDay[day] ??= []).add(dur);
          continue;
        }
        if (v == null) continue;
        (byDay[day] ??= []).add(v);
      }
      final out = <cm.ChartSecPoint>[];
      for (final e in byDay.entries) {
        final vals = e.value;
        final agg =
            (_secondMetric == 'steps' ||
                _secondMetric == 'sleep' ||
                _secondMetric == 'energy')
            ? vals.fold(0.0, (a, b) => a + b)
            : (vals.reduce((a, b) => a + b) / vals.length);
        out.add(cm.ChartSecPoint(date: e.key, value: agg));
      }
      out.sort((a, b) => a.date.compareTo(b.date));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<cm.ChartSecSample>> _fetchSecondarySeries(
    DateTime start,
    DateTime end,
  ) async {
    HealthDataType? t;
    switch (_secondMetric) {
      case 'hr':
        t = HealthDataType.HEART_RATE;
        break;
      case 'resting_hr':
        t = HealthDataType.RESTING_HEART_RATE;
        break;
      case 'hrv_sdnn':
        t = HealthDataType.HEART_RATE_VARIABILITY_SDNN;
        break;
      case 'hrv_rmssd':
        t = HealthDataType.HEART_RATE_VARIABILITY_RMSSD;
        break;
      case 'steps':
        t = HealthDataType.STEPS;
        break;
      case 'sleep':
        t = HealthDataType.SLEEP_ASLEEP;
        break;
      default:
        return const [];
    }
    try {
      final pts = await _health.getHealthDataFromTypes(
        types: [t],
        startTime: start,
        endTime: end,
      );
      final out = <cm.ChartSecSample>[];
      for (final p in pts) {
        double? v = _toDouble(p.value);
        // For sleep-asleep, treat as duration-based metric
        final durMin = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();
        if (t == HealthDataType.SLEEP_ASLEEP) {
          v ??= 1.0; // any value; we'll use duration for fraction
        }
        if (v == null) continue;
        out.add(
          cm.ChartSecSample(
            t: p.dateTo,
            v: v,
            start: p.dateFrom,
            end: p.dateTo,
            durMin: durMin,
          ),
        );
      }
      out.sort((a, b) => a.t.compareTo(b.t));
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
    final hasPerm =
        await _health.hasPermissions(types, permissions: permissions) ?? false;
    if (!hasPerm) {
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
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
          final histGranted = await _health
              .requestHealthDataHistoryAuthorization();
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
          final histGranted = await _health
              .requestHealthDataHistoryAuthorization();
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
      _rangeA = DateTimeRange(
        start: _rangeA!.start.subtract(const Duration(days: 90)),
        end: _rangeA!.end,
      );
      _rangeB = DateTimeRange(
        start: _rangeB!.start.subtract(const Duration(days: 90)),
        end: _rangeB!.end,
      );
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
        list.add(
          _Event(
            id: m['id'] as String,
            title: m['title'] as String,
            date: DateTime.parse(m['date'] as String),
          ),
        );
      } catch (_) {}
    }
    _events = list..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _saveEvents(SharedPreferences prefs) async {
    final strs = _events
        .map(
          (e) => jsonEncode({
            'id': e.id,
            'title': e.title,
            'date': e.date.toIso8601String(),
          }),
        )
        .toList();
    await prefs.setStringList('events_json', strs);
  }

  Future<void> _addEvent(String title, DateTime date) async {
    final e = _Event(
      id: 'evt_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      date: DateTime(date.year, date.month, date.day),
    );
    setState(
      () => _events = [e, ..._events]..sort((a, b) => b.date.compareTo(a.date)),
    );
    await _savePrefs();
  }

  Future<void> _renameEvent(String id, String title) async {
    setState(
      () => _events = _events
          .map((e) => e.id == id ? e.copyWith(title: title) : e)
          .toList(),
    );
    await _savePrefs();
  }

  Future<void> _deleteEvent(String id) async {
    setState(() => _events = _events.where((e) => e.id != id).toList());
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
      _rangeA = DateTimeRange(
        start: DateTime(e.date.year, e.date.month, e.date.day),
        end: DateTime(
          e.date.year,
          e.date.month,
          e.date.day,
        ).add(Duration(days: _rangeDays)),
      );
    });
    await _savePrefs();
  }

  Future<void> _setRangeBFromEvent(_Event e) async {
    setState(() {
      _rangeB = DateTimeRange(
        start: DateTime(e.date.year, e.date.month, e.date.day),
        end: DateTime(
          e.date.year,
          e.date.month,
          e.date.day,
        ).add(Duration(days: _rangeDays)),
      );
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
        if ((d.dateTo.difference(s.dateTo)).abs() <=
            const Duration(minutes: 10)) {
          usedDia.add(idx);
        } else {
          d = null;
        }
      }
      entries.add(
        _BPEntry(
          timestamp: s.dateTo,
          systolic: _toDouble(s.value),
          diastolic: _toDouble(d?.value),
          source: s.sourceId,
        ),
      );
    }
    for (int i = 0; i < diastolic.length; i++) {
      if (usedDia.contains(i)) continue;
      final d = diastolic[i];
      entries.add(
        _BPEntry(
          timestamp: d.dateTo,
          systolic: null,
          diastolic: _toDouble(d.value),
          source: d.sourceId,
        ),
      );
    }

    entries.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    return entries;
  }

  int? _closestIndex(
    List<HealthDataPoint> list,
    DateTime t, {
    Set<int>? exclude,
  }) {
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
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'Summaries',
            onPressed: _openSummaries,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddBp,
            tooltip: 'Add BP Reading',
          ),
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
                      const Text(
                        'Health permissions are required to read blood pressure.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                        ],
                      ),
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
                      final days = i == 0
                          ? 7
                          : i == 1
                          ? 30
                          : 90;
                      setState(() {
                        _isCustomRange = false;
                        _rangeDays = days;
                      });
                      _savePrefs();
                      _fetchData();
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('7d'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('30d'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('90d'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365 * 5),
                        ),
                        lastDate: DateTime.now(),
                        initialDateRange: DateTimeRange(
                          start: _rangeStart,
                          end: _rangeEnd,
                        ),
                      );
                      if (picked != null) {
                        setState(() {
                          _isCustomRange = true;
                          _rangeStart = DateTime(
                            picked.start.year,
                            picked.start.month,
                            picked.start.day,
                          );
                          _rangeEnd = DateTime(
                            picked.end.year,
                            picked.end.month,
                            picked.end.day,
                            23,
                            59,
                            59,
                          );
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
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365 * 5),
                        ),
                        lastDate: DateTime.now(),
                        initialDateRange:
                            _rangeA ??
                            DateTimeRange(
                              start: DateTime.now().subtract(
                                const Duration(days: 7),
                              ),
                              end: DateTime.now(),
                            ),
                      );
                      if (picked != null) {
                        setState(() => _rangeA = picked);
                        _savePrefs();
                      }
                    },
                    icon: const Icon(Icons.looks_one, size: 18),
                    label: Text(
                      _rangeA == null
                          ? 'Pick Range A'
                          : _labelRange('A', _rangeA!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365 * 5),
                        ),
                        lastDate: DateTime.now(),
                        initialDateRange:
                            _rangeB ??
                            DateTimeRange(
                              start: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              end: DateTime.now(),
                            ),
                      );
                      if (picked != null) {
                        setState(() => _rangeB = picked);
                        _savePrefs();
                      }
                    },
                    icon: const Icon(Icons.looks_two, size: 18),
                    label: Text(
                      _rangeB == null
                          ? 'Pick Range B'
                          : _labelRange('B', _rangeB!),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (_rangeA != null && _rangeB != null && !_loading)
                        ? _fetchCompare
                        : null,
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
                    setState(
                      () => _mode = i == 0
                          ? _ViewMode.trend
                          : i == 1
                          ? _ViewMode.averageDay
                          : _ViewMode.compare,
                    );
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Trend'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Average Day'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Compare'),
                    ),
                  ],
                ),
                if (_mode == _ViewMode.trend)
                  ToggleButtons(
                    isSelected: [!_trendDistribution, _trendDistribution],
                    onPressed: (i) {
                      setState(() => _trendDistribution = (i == 1));
                      _savePrefs();
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Lines'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Distribution'),
                      ),
                    ],
                  ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Chart help',
                  onPressed: _showHelp,
                ),
                // Secondary axis selector (Trend only)
                if (_mode == _ViewMode.trend)
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      const Text('Secondary'),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: _secondMetric,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(
                            value: 'hr',
                            child: Text('Heart Rate'),
                          ),
                          DropdownMenuItem(
                            value: 'resting_hr',
                            child: Text('Resting HR'),
                          ),
                          DropdownMenuItem(
                            value: 'hrv_sdnn',
                            child: Text('HRV SDNN'),
                          ),
                          DropdownMenuItem(
                            value: 'hrv_rmssd',
                            child: Text('HRV RMSSD'),
                          ),
                          DropdownMenuItem(
                            value: 'steps',
                            child: Text('Steps'),
                          ),
                          DropdownMenuItem(
                            value: 'sleep',
                            child: Text('Sleep (min)'),
                          ),
                          DropdownMenuItem(
                            value: 'energy',
                            child: Text('Active Energy (kcal)'),
                          ),
                          DropdownMenuItem(
                            value: 'workouts',
                            child: Text('Exercise Time (min)'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _secondMetric = v);
                          await _savePrefs();
                          await _fetchData();
                        },
                      ),
                    ],
                  ),
                if (_mode == _ViewMode.trend && _trendDistribution)
                  Row(
                    children: [
                      const Text('Tooltips'),
                      const SizedBox(width: 6),
                      Switch(
                        value: _trendTooltips,
                        onChanged: (v) {
                          setState(() => _trendTooltips = v);
                          _savePrefs();
                        },
                      ),
                      const SizedBox(width: 12),
                      const Text('Smoothing'),
                      const SizedBox(width: 6),
                      Switch(
                        value: _trendSmoothing,
                        onChanged: (v) {
                          setState(() => _trendSmoothing = v);
                          _savePrefs();
                        },
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Window: ${_trendSmoothDays}d',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Slider(
                              value: _trendSmoothDays.toDouble(),
                              min: 3,
                              max: 15,
                              divisions: 6,
                              label: '${_trendSmoothDays}d',
                              onChanged: _trendSmoothing
                                  ? (v) {
                                      int d = v.round();
                                      if (d % 2 == 0) d += 1; // force odd
                                      if (d < 3) d = 3;
                                      if (d > 15) d = 15;
                                      setState(() => _trendSmoothDays = d);
                                      _savePrefs();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    const Text('Bands'),
                    const SizedBox(width: 6),
                    Switch(
                      value: _showBands,
                      onChanged: (v) => setState(() => _showBands = v),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Anchor to dose'),
                    const SizedBox(width: 6),
                    Switch(
                      value: _anchorToDose,
                      onChanged: (v) {
                        setState(() => _anchorToDose = v);
                        _savePrefs();
                      },
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: !_anchorToDose
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _doseTime ??
                                const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (picked != null) {
                            setState(() => _doseTime = picked);
                            _savePrefs();
                          }
                        },
                  icon: const Icon(Icons.medication),
                  label: Text(
                    _doseTime == null
                        ? 'Dose time'
                        : '${_doseTime!.hour.toString().padLeft(2, '0')}:${_doseTime!.minute.toString().padLeft(2, '0')}',
                  ),
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
                  _LegendDot(color: Colors.red),
                  Text('A: Systolic'),
                  _LegendDot(color: Colors.blue),
                  Text('A: Diastolic'),
                  _LegendDot(color: Colors.orange),
                  Text('B: Systolic'),
                  _LegendDot(color: Colors.lightBlue),
                  Text('B: Diastolic'),
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
              RepaintBoundary(
                key: _compareChartKey,
                child: SizedBox(
                  height: 260,
                  child: (_seriesA != null && _seriesB != null)
                      ? AverageDayCompareChart(
                          seriesA: _seriesA!
                              .map(
                                (e) => cm.ChartBp(
                                  t: e.timestamp,
                                  sbp: e.systolic,
                                  dbp: e.diastolic,
                                ),
                              )
                              .toList(),
                          seriesB: _seriesB!
                              .map(
                                (e) => cm.ChartBp(
                                  t: e.timestamp,
                                  sbp: e.systolic,
                                  dbp: e.diastolic,
                                ),
                              )
                              .toList(),
                          anchorMinute: _anchorToDose && _doseTime != null
                              ? _doseTime!.hour * 60 + _doseTime!.minute
                              : null,
                          showBands: _showBands,
                        )
                      : const Center(
                          child: Text('Pick two ranges and tap Fetch.'),
                        ),
                ),
              )
            else if (_series.isNotEmpty)
              // Build both charts stacked so we can capture either/both for PDF.
              SizedBox(
                height: 260,
                child: Stack(
                  children: [
                    // Hidden counterpart (average day)
                    if (true)
                      IgnorePointer(
                        ignoring: true,
                        child: Opacity(
                          opacity: _mode == _ViewMode.averageDay ? 1.0 : 0.001,
                          child: RepaintBoundary(
                            key: _avgChartKeyCapture,
                            child: AverageDayChart(
                              series: _series
                                  .map(
                                    (e) => cm.ChartBp(
                                      t: e.timestamp,
                                      sbp: e.systolic,
                                      dbp: e.diastolic,
                                    ),
                                  )
                                  .toList(),
                              anchorMinute: _anchorToDose && _doseTime != null
                                  ? _doseTime!.hour * 60 + _doseTime!.minute
                                  : null,
                              showBands: _showBands,
                              showSys: _showSys,
                              showDia: _showDia,
                              // pass samples for HR/HRV/Steps/Sleep
                              secondarySamples:
                                  (_secondMetric == 'resting_hr' ||
                                      _secondMetric == 'hr' ||
                                      _secondMetric == 'hrv_sdnn' ||
                                      _secondMetric == 'hrv_rmssd' ||
                                      _secondMetric == 'steps' ||
                                      _secondMetric == 'sleep')
                                  ? _secSamples
                                  : const [],
                              secondaryLabel: _secondMetric,
                            ),
                          ),
                        ),
                      ),
                    // Hidden/visible trend chart
                    IgnorePointer(
                      ignoring: true,
                      child: Opacity(
                        opacity: _mode == _ViewMode.trend ? 1.0 : 0.001,
                        child: RepaintBoundary(
                          key: _trendChartKeyCapture,
                          child: TrendChart(
                            series: _series
                                .map(
                                  (e) => cm.ChartBp(
                                    t: e.timestamp,
                                    sbp: e.systolic,
                                    dbp: e.diastolic,
                                  ),
                                )
                                .toList(),
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
                          ),
                        ),
                      ),
                    ),
                    // Visible interactive chart on top (to allow pointer events)
                    RepaintBoundary(
                      key: _mode == _ViewMode.trend
                          ? _trendChartKey
                          : _avgChartKey,
                      child: _mode == _ViewMode.trend
                          ? TrendChart(
                              series: _series
                                  .map(
                                    (e) => cm.ChartBp(
                                      t: e.timestamp,
                                      sbp: e.systolic,
                                      dbp: e.diastolic,
                                    ),
                                  )
                                  .toList(),
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
                          : AverageDayChart(
                              series: _series
                                  .map(
                                    (e) => cm.ChartBp(
                                      t: e.timestamp,
                                      sbp: e.systolic,
                                      dbp: e.diastolic,
                                    ),
                                  )
                                  .toList(),
                              anchorMinute: _anchorToDose && _doseTime != null
                                  ? _doseTime!.hour * 60 + _doseTime!.minute
                                  : null,
                              showBands: _showBands,
                              showSys: _showSys,
                              showDia: _showDia,
                              secondarySamples:
                                  (_secondMetric == 'resting_hr' ||
                                      _secondMetric == 'hr' ||
                                      _secondMetric == 'hrv_sdnn' ||
                                      _secondMetric == 'hrv_rmssd' ||
                                      _secondMetric == 'steps' ||
                                      _secondMetric == 'sleep')
                                  ? _secSamples
                                  : const [],
                              secondaryLabel: _secondMetric,
                            ),
                    ),
                  ],
                ),
              )
            else
              const Text('No data available for selected range.'),
            const SizedBox(height: 6),
            if (_mode != _ViewMode.compare)
              Text(
                _effectiveRangeLabel(_series, _rangeStart, _rangeEnd),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            const SizedBox(height: 12),
            _SummaryCards(
              mode: _mode,
              series: _series,
              seriesA: _seriesA,
              seriesB: _seriesB,
              anchorMinute: _anchorToDose && _doseTime != null
                  ? _doseTime!.hour * 60 + _doseTime!.minute
                  : null,
            ),
            const SizedBox(height: 16),
            _ReadingsSection(
              mode: _mode,
              entries: _series,
              entriesA: _seriesA,
              entriesB: _seriesB,
              limit: _listLimit,
              loading: _listLoadingMore,
              onLoadMore: _mode == _ViewMode.compare
                  ? _loadMoreReadingsCompare
                  : _loadMoreReadings,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const Text(
              'Latest entry (if available):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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

  Future<void> _openSummaries() async {
    final st = await _bpStatsForSeries(_series);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summaries',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _summaryRow('Day mean SBP', st.dayMeanS, suffix: ' mmHg'),
                _summaryRow('Night mean SBP', st.nightMeanS, suffix: ' mmHg'),
                _summaryRow('Day mean DBP', st.dayMeanD, suffix: ' mmHg'),
                _summaryRow('Night mean DBP', st.nightMeanD, suffix: ' mmHg'),
                _summaryRow('Dipping SBP', st.dipS, suffix: ' %', digits: 1),
                _summaryRow('Dipping DBP', st.dipD, suffix: ' %', digits: 1),
                _summaryRow(
                  'Morning surge SBP',
                  st.morningSurgeS,
                  suffix: ' mmHg',
                ),
                _summaryRow(
                  'Morning surge DBP',
                  st.morningSurgeD,
                  suffix: ' mmHg',
                ),
                if (st.morningSurgeStrictSts != null)
                  _summaryRow(
                    'STS (strict)',
                    st.morningSurgeStrictSts,
                    suffix: ' mmHg',
                  ),
                if (st.morningSurgeStrictPrewake != null)
                  _summaryRow(
                    'Prewaking (strict)',
                    st.morningSurgeStrictPrewake,
                    suffix: ' mmHg',
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryRow(
    String label,
    double? v, {
    String suffix = '',
    int digits = 0,
  }) {
    final text = v == null ? '-' : v.toStringAsFixed(digits) + suffix;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openAdvancedSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return AdvancedSettingsSheet(
          trendSmoothMethod: _trendSmoothMethod,
          trendSmoothAuto: _trendSmoothAuto,
          trendSmoothDays: _trendSmoothDays,
          onTrendSmoothMethod: (v) {
            setState(() => _trendSmoothMethod = v);
            _savePrefs();
          },
          onTrendSmoothAuto: (v) {
            setState(() => _trendSmoothAuto = v);
            if (v) _applyAutoWindow();
            _savePrefs();
          },
          onTrendSmoothDays: (d) {
            setState(() => _trendSmoothDays = d);
            _savePrefs();
          },
          showBands: _showBands,
          onShowBands: (v) {
            setState(() => _showBands = v);
            _savePrefs();
          },
          anchorToDose: _anchorToDose,
          doseTime: _doseTime,
          onAnchorToDose: (v) {
            setState(() => _anchorToDose = v);
            _savePrefs();
          },
          onDoseTimeChanged: (t) {
            setState(() => _doseTime = t);
            _savePrefs();
          },
          events: _events
              .map((e) => mdl.Event(id: e.id, title: e.title, date: e.date))
              .toList(),
          onAddEvent: (title, date) async {
            await _addEvent(title, date);
          },
          onRenameEvent: (id, title) async {
            await _renameEvent(id, title);
          },
          onDeleteEvent: (id) async {
            await _deleteEvent(id);
          },
          onSetRange: (e) async {
            await _setRangeFromEvent(
              _Event(id: e.id, title: e.title, date: e.date),
            );
          },
          onSetA: (e) async {
            await _setRangeAFromEvent(
              _Event(id: e.id, title: e.title, date: e.date),
            );
          },
          onSetB: (e) async {
            await _setRangeBFromEvent(
              _Event(id: e.id, title: e.title, date: e.date),
            );
          },
          surgeMorningWindowHours: _surgeMorningWindowHours,
          surgeTroughWindowHours: _surgeTroughWindowHours,
          surgePrewakeHours: _surgePrewakeHours,
          surgeHrRiseBpm: _surgeHrRiseBpm,
          surgeSteps30Min: _surgeSteps30Min,
          surgeWakeEarliestHour: _surgeWakeEarliestHour,
          surgeWakeLatestHour: _surgeWakeLatestHour,
          onSurgeChange:
              ({
                int? morning,
                int? trough,
                int? prewake,
                int? hrRise,
                int? steps30,
                int? earliest,
                int? latest,
              }) {
                setState(() {
                  if (morning != null) _surgeMorningWindowHours = morning;
                  if (trough != null) _surgeTroughWindowHours = trough;
                  if (prewake != null) _surgePrewakeHours = prewake;
                  if (hrRise != null) _surgeHrRiseBpm = hrRise;
                  if (steps30 != null) _surgeSteps30Min = steps30;
                  if (earliest != null) _surgeWakeEarliestHour = earliest;
                  if (latest != null) _surgeWakeLatestHour = latest;
                });
                _savePrefs();
              },
        );
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
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Chart Help'),
          content: const SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trend vs Distribution'),
                  SizedBox(height: 8),
                  Text(
                    '• Lines: plots individual readings over calendar time.',
                  ),
                  Text(
                    '• Distribution: summarizes each day with median (line) and IQR (shaded band). Days with no readings are filled by interpolation.',
                  ),
                  SizedBox(height: 12),
                  Text('Smoothing'),
                  SizedBox(height: 8),
                  Text(
                    '• Applies a moving average (MA) or exponential moving average (EMA) over daily medians/IQR.',
                  ),
                  Text(
                    '• Window can be auto-tied to the date range or set manually (odd days).',
                  ),
                  SizedBox(height: 12),
                  Text('BP Zones'),
                  SizedBox(height: 8),
                  Text(
                    '• Background color bands appear when only one metric is enabled.',
                  ),
                  Text(
                    '• SBP: <120 green, 120–129 yellow, 130–139 orange, 140–179 red, 180+ dark red.',
                  ),
                  Text(
                    '• DBP: <80 green, 80–89 yellow, 90–119 red, 120+ dark red.',
                  ),
                  SizedBox(height: 12),
                  Text('Secondary Axis'),
                  SizedBox(height: 8),
                  Text(
                    '• Trend: HR, Resting HR, HRV, Steps, Sleep supported (right axis).',
                  ),
                  Text(
                    '• Average Day: HR/Resting HR/HRV/Steps/Sleep supported (right-axis overlay).',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddBp() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return AddBpSheet(
          defaultPosition: _bpBodyPosition,
          defaultArm: _bpArm,
          onSave: (s, d, when, pos, arm) async {
            // Ensure WRITE permission for BP
            final okPerm = await _ensureWritePermission();
            if (!okPerm) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Health write permission denied'),
                  ),
                );
              }
              return false;
            }
            final ok = await _health.writeBloodPressure(
              systolic: s,
              diastolic: d,
              startTime: when,
            );
            if (ok) {
              if (mounted) {
                setState(() {
                  _bpBodyPosition = pos;
                  _bpArm = arm;
                });
              }
              await _savePrefs();
              await _saveBpAnnotation(when, pos, arm);
              await _fetchData();
              return true;
            }
            return false;
          },
        );
      },
    );
  }

  Future<bool> _ensureWritePermission() async {
    await _health.configure();
    const types = <HealthDataType>[
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ];
    const permissions = <HealthDataAccess>[
      HealthDataAccess.WRITE,
      HealthDataAccess.WRITE,
    ];
    final hasPerm =
        await _health.hasPermissions(types, permissions: permissions) ?? false;
    if (!hasPerm) {
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      if (!granted) return false;
    }
    return true;
  }

  // _promptText removed (now handled in AdvancedSettingsSheet)

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
    setState(() => _trendSmoothDays = w);
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
        buf.writeln(
          'trend\t${_rangeStart.toIso8601String()}\t${_rangeEnd.toIso8601String()}',
        );
        buf.writeln('timestamp\tsystolic_mmHg\tdiastolic_mmHg\tsource');
        for (final e in _series) {
          final ts = e.timestamp?.toIso8601String() ?? '';
          buf.writeln(
            '$ts\t${e.systolic?.toStringAsFixed(1) ?? ''}\t${e.diastolic?.toStringAsFixed(1) ?? ''}\t${e.source ?? ''}',
          );
        }
      } else if (_mode == _ViewMode.averageDay) {
        final agg = avg.AverageDayAggregator(
          series: _series
              .map(
                (e) => avg.AvgBpInput(
                  t: e.timestamp,
                  sbp: e.systolic,
                  dbp: e.diastolic,
                ),
              )
              .toList(),
        ).compute(stepMinutes: 15, smoothMinutes: 45);
        buf.writeln('mode\tstart\tend');
        buf.writeln(
          'average_day\t${_rangeStart.toIso8601String()}\t${_rangeEnd.toIso8601String()}',
        );
        buf.writeln(
          'minute_of_day\ttime_label\tsystolic_mean_mmHg\tdiastolic_mean_mmHg',
        );
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
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pick two ranges and Fetch first.')),
          );
          return;
        }
        buf.writeln('mode');
        buf.writeln('compare');
        buf.writeln('rangeA_start\trangeA_end\trangeB_start\trangeB_end');
        buf.writeln(
          '${_rangeA?.start.toIso8601String() ?? ''}\t${_rangeA?.end.toIso8601String() ?? ''}\t${_rangeB?.start.toIso8601String() ?? ''}\t${_rangeB?.end.toIso8601String() ?? ''}',
        );
        buf.writeln(
          'minute_of_day\ttime_label\tA_systolic\tA_diastolic\tB_systolic\tB_diastolic\tDelta_systolic(B-A)\tDelta_diastolic(B-A)',
        );
        final anchorMin = _anchorToDose && _doseTime != null
            ? _doseTime!.hour * 60 + _doseTime!.minute
            : null;
        final aggA = avg.AverageDayAggregator(
          series: _seriesA!
              .map(
                (e) => avg.AvgBpInput(
                  t: e.timestamp,
                  sbp: e.systolic,
                  dbp: e.diastolic,
                ),
              )
              .toList(),
        ).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMin);
        final aggB = avg.AverageDayAggregator(
          series: _seriesB!
              .map(
                (e) => avg.AvgBpInput(
                  t: e.timestamp,
                  sbp: e.systolic,
                  dbp: e.diastolic,
                ),
              )
              .toList(),
        ).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMin);
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
          final dS = (bS != null && aS != null)
              ? (bS - aS).toStringAsFixed(1)
              : '';
          final dD = (bD != null && aD != null)
              ? (bD - aD).toStringAsFixed(1)
              : '';
          buf.writeln(
            '$m\t$label\t${f(aS)}\t${f(aD)}\t${f(bS)}\t${f(bD)}\t$dS\t$dD',
          );
        }
      }

      await file.writeAsString(buf.toString());
      final x = XFile(
        file.path,
        mimeType: 'text/tab-separated-values',
        name: file.uri.pathSegments.last,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [x],
        subject: 'Blood Pressure Export (TSV)',
        text: 'Attached TSV export from Blood Pressure app.',
      );
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _exportPdf() async {
    try {
      // Simple preflight dialog with include-both-charts toggle
      bool includeBoth = _pdfIncludeBothCharts;
      if (mounted) {
        includeBoth =
            await showDialog<bool>(
              context: context,
              builder: (ctx) {
                bool tmp = _pdfIncludeBothCharts;
                return StatefulBuilder(
                  builder: (context, setSt) {
                    return AlertDialog(
                      title: const Text('Export PDF'),
                      content: CheckboxListTile(
                        value: tmp,
                        onChanged: (v) => setSt(() => tmp = v ?? true),
                        title: const Text(
                          'Include both charts (Trend + Average Day)',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, tmp),
                          child: const Text('Export'),
                        ),
                      ],
                    );
                  },
                );
              },
            ) ??
            _pdfIncludeBothCharts;
        _pdfIncludeBothCharts = includeBoth;
        await _savePrefs();
      }

      await _loadAnnotations();
      final doc = pw.Document();
      final eff = _effectiveRangeLabel(_series, _rangeStart, _rangeEnd);
      final secSummary = _secondarySummaryText();
      _BpStats? aStats;
      _BpStats? bStats;
      if (_mode == _ViewMode.compare && _seriesA != null && _seriesB != null) {
        aStats = await _bpStatsForSeries(_seriesA!);
        bStats = await _bpStatsForSeries(_seriesB!);
      }

      // capture chart image(s)
      final List<pw.Widget> chartWidgets = [];
      await Future.delayed(
        const Duration(milliseconds: 60),
      ); // allow hidden charts to paint
      if (_mode == _ViewMode.compare) {
        final png = await _captureChartPng(_compareChartKey);
        if (png != null) {
          chartWidgets.add(
            pw.Center(child: pw.Image(pw.MemoryImage(png), width: 500)),
          );
        }
      } else {
        if (includeBoth) {
          final tPng = await _captureChartPng(_trendChartKeyCapture);
          final aPng = await _captureChartPng(_avgChartKeyCapture);
          if (tPng != null) {
            chartWidgets.add(
              pw.Center(child: pw.Image(pw.MemoryImage(tPng), width: 500)),
            );
          }
          if (aPng != null) {
            chartWidgets.add(pw.SizedBox(height: 8));
          }
          if (aPng != null) {
            chartWidgets.add(
              pw.Center(child: pw.Image(pw.MemoryImage(aPng), width: 500)),
            );
          }
        } else {
          final ck = _chartKeyForMode();
          if (ck != null) {
            final png = await _captureChartPng(ck);
            if (png != null) {
              chartWidgets.add(
                pw.Center(child: pw.Image(pw.MemoryImage(png), width: 500)),
              );
            }
          }
        }
      }

      // Compute BP summary stats
      final bpStats = _mode == _ViewMode.compare && _seriesA != null
          ? await _bpStatsForSeries(_seriesA!)
          : await _bpStatsForSeries(_series);
      final hrHrvHeader = _hrHrvSummaryHeader();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) {
            final rows = <pw.TableRow>[];
            rows.add(
              pw.TableRow(
                children: [
                  pw.Text('Date'),
                  pw.Text('Time'),
                  pw.Text('SBP'),
                  pw.Text('DBP'),
                  pw.Text('Pos'),
                  pw.Text('Arm'),
                  pw.Text('Source'),
                ],
              ),
            );
            final list = [..._series]
              ..sort(
                (a, b) => (b.timestamp ?? DateTime(0)).compareTo(
                  a.timestamp ?? DateTime(0),
                ),
              );
            for (final e in list.take(20)) {
              final bg = _pdfBgForBp(e);
              final ann = _annotationFor(e.timestamp);
              rows.add(
                pw.TableRow(
                  children: [
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(_fmtDate(e.timestamp)),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(_fmtTime(e.timestamp)),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(e.systolic?.toStringAsFixed(0) ?? '-'),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(e.diastolic?.toStringAsFixed(0) ?? '-'),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(ann?.$1 ?? '-'),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(ann?.$2 ?? '-'),
                    ),
                    pw.Container(
                      color: bg,
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Text(e.source ?? ''),
                    ),
                  ],
                ),
              );
            }
            return [
              pw.Text(
                'Blood Pressure Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(eff),
              if (hrHrvHeader != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  hrHrvHeader,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
              if (secSummary.isNotEmpty)
                pw.Text(
                  secSummary,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              pw.SizedBox(height: 12),
              ...chartWidgets,
              pw.SizedBox(height: 12),
              _bpStatsTable(bpStats),
              if (_mode == _ViewMode.compare &&
                  _seriesA != null &&
                  _seriesB != null &&
                  aStats != null &&
                  bStats != null) ...[
                pw.SizedBox(height: 12),
                _compareDeltaTable(aStats, bStats),
              ],
              pw.SizedBox(height: 12),
              if (_mode != _ViewMode.compare) ...[
                pw.Text('Recent Readings (last 20)'),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: rows,
                ),
              ] else ...[
                pw.Text('Recent Readings (A last 10)'),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: _rowsForSeries(_seriesA!, 10),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Recent Readings (B last 10)'),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: _rowsForSeries(_seriesB!, 10),
                ),
              ],
            ];
          },
        ),
      );
      final bytes = await doc.save();
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: 'bp_report.pdf');
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  List<pw.TableRow> _rowsForSeries(List<_BPEntry> s, int take) {
    final rows = <pw.TableRow>[];
    rows.add(
      pw.TableRow(
        children: [
          pw.Text('Date'),
          pw.Text('Time'),
          pw.Text('SBP'),
          pw.Text('DBP'),
          pw.Text('Pos'),
          pw.Text('Arm'),
          pw.Text('Source'),
        ],
      ),
    );
    final list = [...s]
      ..sort(
        (a, b) =>
            (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)),
      );
    for (final e in list.take(take)) {
      final bg = _pdfBgForBp(e);
      final ann = _annotationFor(e.timestamp);
      rows.add(
        pw.TableRow(
          children: [
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(_fmtDate(e.timestamp)),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(_fmtTime(e.timestamp)),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(e.systolic?.toStringAsFixed(0) ?? '-'),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(e.diastolic?.toStringAsFixed(0) ?? '-'),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(ann?.$1 ?? '-'),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(ann?.$2 ?? '-'),
            ),
            pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(e.source ?? ''),
            ),
          ],
        ),
      );
    }
    return rows;
  }

  pw.Widget _compareDeltaTable(_BpStats a, _BpStats b) {
    double? diff(double? x, double? y) =>
        (x != null && y != null) ? (y - x) : null; // B - A
    String f(double? v, {int d = 0, bool signed = true}) {
      if (v == null) return '-';
      final s = v.toStringAsFixed(d);
      return signed && v >= 0 ? '+$s' : s;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Compare Summaries (B - A)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Metric'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('ΔSBP'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('ΔDBP'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Day mean'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.dayMeanS, b.dayMeanS))} mmHg'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.dayMeanD, b.dayMeanD))} mmHg'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Night mean'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.nightMeanS, b.nightMeanS))} mmHg'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.nightMeanD, b.nightMeanD))} mmHg'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Dipping'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.dipS, b.dipS), d: 1)}%'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(diff(a.dipD, b.dipD), d: 1)}%'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Morning surge'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(
                    '${f(diff(a.morningSurgeS, b.morningSurgeS))} mmHg',
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(
                    '${f(diff(a.morningSurgeD, b.morningSurgeD))} mmHg',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _requestPermsManually() async {
    try {
      final ok = await _ensurePermissions();
      if (ok) {
        setState(() => _hasPermissions = true);
        _fetchData();
      } else {
        if (!mounted) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission still not granted. Open Health Connect.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Permission error: $e')));
    }
  }

  static const _hcChannel = MethodChannel('app.healthconnect');
  Future<void> _openHealthConnectSettings() async {
    try {
      await _hcChannel.invokeMethod('openSettings');
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open Health Connect: $e')),
      );
    }
  }

  // ---- PDF helpers and chart capture ----
  PdfColor _pdfBgForBp(_BPEntry e) {
    final s = e.systolic ?? 0;
    final d = e.diastolic ?? 0;
    if (s >= 180 || d >= 120) {
      return PdfColor.fromInt(0xFFFFEBEE); // dark red tint
    }
    if (s >= 140 || d >= 90) return PdfColor.fromInt(0xFFFFEBEE); // red tint
    if (s >= 130) return PdfColor.fromInt(0xFFFFF3E0); // orange tint
    if (s >= 120) return PdfColor.fromInt(0xFFFFFDE7); // yellow tint
    return PdfColor.fromInt(0xFFE8F5E9); // green tint
  }

  // ------- Local annotations (position/arm) -------
  // We store per-reading annotations when saving via Add BP flow.
  Future<void> _saveBpAnnotation(DateTime t, String pos, String arm) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('bp_annotations') ?? <String>[];
    final entry = jsonEncode({
      't': t.toIso8601String(),
      'pos': pos,
      'arm': arm,
    });
    list.add(entry);
    await prefs.setStringList('bp_annotations', list);
  }

  // (pos, arm) tuple if a locally-saved annotation matches timestamp (within 60s).
  (String, String)? _annotationFor(DateTime? t) {
    if (t == null) return null;
    // For performance we could cache, but the list is tiny (< few hundred)
    // This runs only during export (top 20 rows)
    try {
      // Synchronously read prefs isn't available; use async? Simplify by using sync cache:
      // In this code path we cannot await; instead, we read once elsewhere. As a compromise,
      // we use a cached copy stored on state during previous save, else fallback to blocking
      // style via SharedPreferences.getInstance() then getStringList.
      // Because this is rarely called, a simple synchronous-like read is acceptable.
    } catch (_) {}
    return _annotationForSync(t);
  }

  (String, String)? _annotationForSync(DateTime t) {
    // Load map from SharedPreferences (synchronously via thenable workaround)
    // We can't block here; but for PDF build it's fine to use `SharedPreferences.getInstance()` synchronously
    // since pdf build runs in async outer method and we call this only after awaiting.
    // So call getInstance synchronously by accessing then() is cumbersome; instead we cache globally.
    // For simplicity, keep a static cache on first call in this frame using a Future.
    // Implement a simple blocking-like method by using a Zone microtask—here we accept a small risk and return null if unavailable.
    return _annotations
        .firstWhere(
          (ann) => (ann.t.difference(t).inSeconds).abs() <= 60,
          orElse: () => _BpAnn.empty,
        )
        .toTuple();
  }

  List<_BpAnn> _annotations = const [];
  Future<void> _loadAnnotations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('bp_annotations') ?? <String>[];
    final out = <_BpAnn>[];
    for (final s in list) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        out.add(
          _BpAnn(
            t: DateTime.parse(m['t'] as String),
            pos: (m['pos'] as String?) ?? '',
            arm: (m['arm'] as String?) ?? '',
          ),
        );
      } catch (_) {}
    }
    _annotations = out;
  }

  // old label helpers removed; using static labels in _BpAnn

  String _secondarySummaryText() {
    if (_secondMetric == 'none') return '';
    if (_secondMetric == 'steps') {
      final sum = _secSeries.fold<double>(0, (a, b) => a + b.value);
      return 'Steps (total): ${sum.toStringAsFixed(0)}';
    }
    if (_secondMetric == 'sleep') {
      final sum = _secSeries.fold<double>(0, (a, b) => a + b.value);
      return 'Sleep (total minutes): ${sum.toStringAsFixed(0)}';
    }
    if (_secondMetric == 'energy') {
      final sum = _secSeries.fold<double>(0, (a, b) => a + b.value);
      return 'Active energy (total): ${sum.toStringAsFixed(0)} kcal';
    }
    if (_secondMetric == 'workouts') {
      final sum = _secSeries.fold<double>(0, (a, b) => a + b.value);
      return 'Exercise time (total): ${sum.toStringAsFixed(0)} min';
    }
    if (_secSeries.isNotEmpty) {
      final mean =
          _secSeries.fold<double>(0, (a, b) => a + b.value) / _secSeries.length;
      final label = (_secondMetric == 'resting_hr')
          ? 'Resting HR'
          : (_secondMetric == 'hr'
                ? 'Heart Rate'
                : (_secondMetric == 'hrv_sdnn' ? 'HRV SDNN' : 'HRV RMSSD'));
      return '$label (mean): ${mean.toStringAsFixed(0)}';
    }
    return '';
  }

  // ------- Summary stats helpers -------
  Future<_BpStats> _bpStatsForSeries(List<_BPEntry> s) async {
    final pts = s
        .map(
          (e) => met.BpPoint(t: e.timestamp, sbp: e.systolic, dbp: e.diastolic),
        )
        .toList();
    final params = met.SurgeParams(
      morningWindowHours: _surgeMorningWindowHours,
      troughWindowHours: _surgeTroughWindowHours,
      prewakeHours: _surgePrewakeHours,
      hrRiseBpm: _surgeHrRiseBpm,
      steps30Min: _surgeSteps30Min,
      wakeEarliestHour: _surgeWakeEarliestHour,
      wakeLatestHour: _surgeWakeLatestHour,
    );
    final st = await met.computeBpStats(
      points: pts,
      health: _health,
      params: params,
    );
    return _BpStats(
      dayMeanS: st.dayMeanS,
      nightMeanS: st.nightMeanS,
      dayMeanD: st.dayMeanD,
      nightMeanD: st.nightMeanD,
      dipS: st.dipS,
      dipD: st.dipD,
      morningSurgeS: st.morningSurgeS,
      morningSurgeD: st.morningSurgeD,
      morningSurgeStrictSts: st.morningSurgeStrictSts,
      morningSurgeStrictPrewake: st.morningSurgeStrictPrewake,
    );
  }

  pw.Widget _bpStatsTable(_BpStats st) {
    String f(double? v, {int d = 0}) => v == null ? '-' : v.toStringAsFixed(d);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Summary (Day vs Night; dipping; morning surge)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Metric'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('SBP'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('DBP'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Day mean'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.dayMeanS)} mmHg'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.dayMeanD)} mmHg'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Night mean'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.nightMeanS)} mmHg'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.nightMeanD)} mmHg'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Dipping'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.dipS, d: 1)}%'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.dipD, d: 1)}%'),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Morning surge'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.morningSurgeS)} mmHg'),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${f(st.morningSurgeD)} mmHg'),
                ),
              ],
            ),
            if (st.morningSurgeStrictSts != null)
              pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('STS (strict)'),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('${f(st.morningSurgeStrictSts)} mmHg'),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('-'),
                  ),
                ],
              ),
            if (st.morningSurgeStrictPrewake != null)
              pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('Prewaking (strict)'),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('${f(st.morningSurgeStrictPrewake)} mmHg'),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('-'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String? _hrHrvSummaryHeader() {
    List<double> vals = [];
    String? label;
    if (_secondMetric == 'hr' ||
        _secondMetric == 'resting_hr' ||
        _secondMetric == 'hrv_sdnn' ||
        _secondMetric == 'hrv_rmssd') {
      if (_mode == _ViewMode.averageDay && _secSamples.isNotEmpty) {
        vals = _secSamples.map((e) => e.v).toList();
      } else if (_secSeries.isNotEmpty) {
        vals = _secSeries.map((e) => e.value).toList();
      }
      if (vals.isNotEmpty) {
        label = _secondMetric == 'hr'
            ? 'HR'
            : (_secondMetric == 'resting_hr'
                  ? 'Resting HR'
                  : (_secondMetric == 'hrv_sdnn' ? 'HRV SDNN' : 'HRV RMSSD'));
      }
    }
    if (vals.isEmpty || label == null) return null;
    vals.sort();
    double q(double p) {
      final pos = (vals.length - 1) * p;
      final i = pos.floor();
      final frac = pos - i;
      if (i + 1 < vals.length) return vals[i] * (1 - frac) + vals[i + 1] * frac;
      return vals[i];
    }

    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final q25 = q(0.25), q50 = q(0.50), q75 = q(0.75);
    final iqr = q75 - q25;
    String unit = (_secondMetric == 'hr' || _secondMetric == 'resting_hr')
        ? 'bpm'
        : 'ms';
    return '$label: mean ${mean.toStringAsFixed(0)} $unit; median ${q50.toStringAsFixed(0)}; IQR ${iqr.toStringAsFixed(0)}';
  }

  // ---- Strict morning surge (heuristics) ----

  final GlobalKey _trendChartKey = GlobalKey(); // visible trend
  final GlobalKey _avgChartKey = GlobalKey(); // visible average-day
  final GlobalKey _trendChartKeyCapture = GlobalKey(); // hidden capture-only
  final GlobalKey _avgChartKeyCapture = GlobalKey(); // hidden capture-only
  final GlobalKey _compareChartKey = GlobalKey();

  GlobalKey? _chartKeyForMode() {
    if (_mode == _ViewMode.trend) return _trendChartKey;
    if (_mode == _ViewMode.averageDay) return _avgChartKey;
    if (_mode == _ViewMode.compare) return _compareChartKey;
    return null;
  }

  Future<Uint8List?> _captureChartPng(GlobalKey key) async {
    try {
      final rb =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (rb == null) return null;
      final img = await rb.toImage(pixelRatio: 3.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
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
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Systolic (mmHg)')),
          DataColumn(label: Text('Diastolic (mmHg)')),
          DataColumn(label: Text('Source')),
        ],
        rows: [
          DataRow(
            cells: [
              DataCell(Text(_formatDate(entry?.timestamp))),
              DataCell(Text(_formatTime(entry?.timestamp))),
              DataCell(Text(entry?.systolic?.toStringAsFixed(0) ?? '-')),
              DataCell(Text(entry?.diastolic?.toStringAsFixed(0) ?? '-')),
              DataCell(Text(entry?.source ?? '-')),
            ],
          ),
        ],
      ),
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

// _NumField removed (now provided within AdvancedSettingsSheet)

class _BPEntry {
  final DateTime? timestamp;
  final double? systolic;
  final double? diastolic;
  final String? source;
  const _BPEntry({this.timestamp, this.systolic, this.diastolic, this.source});
}

// old secondary DTOs removed; using models/chart_models.dart

class _BpAnn {
  final DateTime t;
  final String pos;
  final String arm;
  const _BpAnn({required this.t, required this.pos, required this.arm});
  static final empty = _BpAnn(
    t: DateTime.fromMillisecondsSinceEpoch(0),
    pos: '',
    arm: '',
  );
  (String, String)? toTuple() {
    if (pos.isEmpty && arm.isEmpty) return null;
    return (_posLabelStatic(pos), _armLabelStatic(arm));
  }

  static String _posLabelStatic(String code) {
    switch (code) {
      case 'sitting':
        return 'Sitting';
      case 'standing':
        return 'Standing';
      case 'supine':
        return 'Supine';
      default:
        return '-';
    }
  }

  static String _armLabelStatic(String code) {
    switch (code) {
      case 'left_upper_arm':
        return 'Left UA';
      case 'right_upper_arm':
        return 'Right UA';
      case 'wrist':
        return 'Wrist';
      default:
        return '-';
    }
  }
}

/* class _TrendChart extends StatelessWidget {
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
} */

class _Event {
  final String id;
  final String title;
  final DateTime date;
  const _Event({required this.id, required this.title, required this.date});
  _Event copyWith({String? title, DateTime? date}) =>
      _Event(id: id, title: title ?? this.title, date: date ?? this.date);
}

class _EventChips extends StatelessWidget {
  final List<_Event> events;
  final Future<void> Function(_Event)? onTap;
  final Future<void> Function(_Event)? onTapA;
  final Future<void> Function(_Event)? onTapB;
  final Future<void> Function() onMore;
  const _EventChips({
    required this.events,
    this.onTap,
    this.onTapA,
    this.onTapB,
    required this.onMore,
  });
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: onTap != null
                  ? ActionChip(
                      label: Text('${e.title} (${e.date.month}/${e.date.day})'),
                      onPressed: () => onTap!(e),
                    )
                  : Wrap(
                      spacing: 6,
                      children: [
                        ActionChip(
                          label: Text('A: ${e.title.split(' ').first}'),
                          onPressed: onTapA != null ? () => onTapA!(e) : null,
                        ),
                        ActionChip(
                          label: Text('B: ${e.title.split(' ').first}'),
                          onPressed: onTapB != null ? () => onTapB!(e) : null,
                        ),
                      ],
                    ),
            ),
          ActionChip(label: const Text('More…'), onPressed: onMore),
        ],
      ),
    );
  }
}

/* class _AverageDayChart extends StatelessWidget {
  final List<_BPEntry> series;
  final int? anchorMinute; // minutes since midnight
  final bool showBands;
  final bool showSys;
  final bool showDia;
  final List<_SecSample> secondarySamples;
  final String secondaryLabel;
  const _AverageDayChart({required this.series, this.anchorMinute, this.showBands = false, this.showSys = true, this.showDia = true, this.secondarySamples = const [], this.secondaryLabel = ''});

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

    // Secondary: derive per-15-min value depending on metric
    List<FlSpot> secSpots = [];
    double? secMin, secMax;
    List<double?> secSeriesVals = List<double?>.filled(agg.minutes.length, null);
    if (secondarySamples.isNotEmpty) {
      if (secondaryLabel == 'steps') {
        // Distribute steps across overlapping bins, then convert to steps/min per bin
        final sums = List<double>.filled(agg.minutes.length, 0.0);
        final mins = List<double>.filled(agg.minutes.length, 0.0);
        for (final s in secondarySamples) {
          final start = s.start ?? s.t.subtract(const Duration(minutes: 1));
          final end = s.end ?? s.t;
          double steps = s.v;
          final totalMin = (end.difference(start).inSeconds / 60.0).clamp(0.0, 1440.0);
          if (totalMin <= 0) {
            // assign to closest bin
            var m = s.t.hour * 60 + s.t.minute + s.t.second / 60.0;
            if (anchorMinute != null) { m = (m - anchorMinute!) % 1440; if (m < 0) m += 1440; }
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
              int anchored = (binStartMin - anchorMinute!) % 1440; if (anchored < 0) anchored += 1440;
              binIdx = (anchored / 15).floor();
            } else {
              binIdx = (binStartMin / 15).floor();
            }
            binIdx = binIdx.clamp(0, agg.minutes.length - 1);
            final binStart = DateTime(cur.year, cur.month, cur.day, binStartMin ~/ 60, binStartMin % 60);
            final binEnd = binStart.add(const Duration(minutes: 15));
            final segEnd = end.isBefore(binEnd) ? end : binEnd;
            final overlap = (segEnd.difference(cur).inSeconds / 60.0).clamp(0.0, 15.0);
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
          if (m > 0) secSeriesVals[i] = sums[i] / m; // steps per minute
        }
        secMin = 0;
        final ys = secSeriesVals.whereType<double>().toList();
        if (ys.isNotEmpty) secMax = ys.reduce(math.max);
      } else if (secondaryLabel == 'sleep') {
        // Compute asleep fraction in each 15-min bin using duration overlap
        final asleepMin = List<double>.filled(agg.minutes.length, 0.0);
        for (final s in secondarySamples) {
          final start = s.start ?? s.t.subtract(const Duration(minutes: 1));
          final end = s.end ?? s.t;
          DateTime cur = start;
          while (cur.isBefore(end)) {
            final binStartMin = ((cur.hour * 60 + cur.minute) ~/ 15) * 15;
            int binIdx;
            if (anchorMinute != null) {
              int anchored = (binStartMin - anchorMinute!) % 1440; if (anchored < 0) anchored += 1440;
              binIdx = (anchored / 15).floor();
            } else {
              binIdx = (binStartMin / 15).floor();
            }
            binIdx = binIdx.clamp(0, agg.minutes.length - 1);
            final binStart = DateTime(cur.year, cur.month, cur.day, binStartMin ~/ 60, binStartMin % 60);
            final binEnd = binStart.add(const Duration(minutes: 15));
            final segEnd = end.isBefore(binEnd) ? end : binEnd;
            final overlap = (segEnd.difference(cur).inSeconds / 60.0).clamp(0.0, 15.0);
            if (overlap > 0) {
              asleepMin[binIdx] += overlap;
            }
            cur = segEnd;
          }
        }
        for (int i = 0; i < agg.minutes.length; i++) {
          if (asleepMin[i] > 0) secSeriesVals[i] = (asleepMin[i] / 15.0).clamp(0.0, 1.0);
        }
        secMin = 0; secMax = 1;
      } else {
        // HR/HRV mean per bin
        final bins = List.generate(agg.minutes.length, (_) => <double>[]);
        for (final s in secondarySamples) {
          var m = s.t.hour * 60 + s.t.minute + s.t.second/60.0;
          if (anchorMinute != null) { m = (m - anchorMinute!) % 1440; if (m < 0) m += 1440; }
          final idx = (m / 15).floor().clamp(0, agg.minutes.length - 1);
          bins[idx].add(s.v);
        }
        for (int i = 0; i < bins.length; i++) {
          final b = bins[i];
          if (b.isNotEmpty) secSeriesVals[i] = b.reduce((a,b)=>a+b)/b.length;
        }
        final ys = secSeriesVals.whereType<double>().toList();
        if (ys.isNotEmpty) { secMin = ys.reduce(math.min); secMax = ys.reduce(math.max); }
      }

      // Map secondary to left-axis coordinates (so it shares the chart area)
      final leftMin = _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots]);
      final leftMax = _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots]);
      final leftRange = (leftMax - leftMin).abs() < 1e-6 ? 1.0 : (leftMax - leftMin);
      final secRange = (secMax != null && secMin != null && (secMax - secMin!).abs() >= 1e-6) ? (secMax! - secMin!) : 1.0;
      for (int i = 0; i < secSeriesVals.length; i++) {
        final v = secSeriesVals[i];
        if (v == null) continue;
        final x = agg.minutes[i] / 60.0;
        final y = leftMin + (v - (secMin ?? 0)) * leftRange / secRange;
        secSpots.add(FlSpot(x, y));
      }
    }

    final minY = _autoMinY([if (showSys) sysSpots, if (showDia) diaSpots, secSpots.isNotEmpty ? secSpots : <FlSpot>[]]) - 10;
    final maxY = _autoMaxY([if (showSys) sysSpots, if (showDia) diaSpots, secSpots.isNotEmpty ? secSpots : <FlSpot>[]]) + 10;

    // Build chart with optional right-axis overlay for secondary
    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: 24,
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
          ...bars,
          if (secSpots.isNotEmpty) LineChartBarData(spots: secSpots, isCurved: true, color: Colors.purple, barWidth: 2, dotData: const FlDotData(show: false)),
        ],
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

    if (secSpots.isEmpty) return chart;

    // Overlay right-axis labels (workaround fl_chart limitation)
    String fmtTick(double v) {
      if (secondaryLabel == 'sleep') return (v * 100).round().toString();
      return v.round().toString();
    }
    final ticks = <double>[];
    final tickVals = <String>[];
    final leftRange = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
    if (secMin != null && secMax != null) {
      for (int i = 0; i <= 4; i++) {
        final yLeft = minY + leftRange * (i / 4);
        final secVal = (secMin!) + (yLeft - minY) * (secMax! - secMin!) / leftRange;
        ticks.add(yLeft);
        tickVals.add(fmtTick(secVal));
      }
    }

    return Stack(children: [
      Positioned.fill(child: chart),
      if (ticks.isNotEmpty)
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(right: 2, top: 4, bottom: 18),
            child: Stack(children: [
              for (int i = 0; i < tickVals.length; i++)
                Align(
                  alignment: Alignment(1, 1 - 2 * (((ticks[i] - minY) / (maxY - minY)).clamp(0.0, 1.0))),
                  child: Text(
                    secondaryLabel == 'sleep' ? '${tickVals[i]}%' : tickVals[i],
                    style: const TextStyle(fontSize: 10, color: Colors.purple),
                  ),
                ),
            ]),
          ),
        ),
    ]);
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
} */

/* class _AverageDayCompareChart extends StatelessWidget {
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
} */

/* class _AverageDayAggregator {
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
} */

/* class _DayBins {
  final List<double> sysSum;
  final List<double> diaSum;
  final List<double> sysW;
  final List<double> diaW;
  _DayBins(int bins)
      : sysSum = List.filled(bins, 0),
        diaSum = List.filled(bins, 0),
        sysW = List.filled(bins, 0),
        diaW = List.filled(bins, 0);
} */

/* class _AvgDay {
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
} */

enum _ViewMode { trend, averageDay, compare }

class _BpStats {
  final double? dayMeanS;
  final double? nightMeanS;
  final double? dayMeanD;
  final double? nightMeanD;
  final double? dipS; // %
  final double? dipD; // %
  final double? morningSurgeS; // mmHg
  final double? morningSurgeD; // mmHg
  final double? morningSurgeStrictSts; // strict sleep-trough surge
  final double? morningSurgeStrictPrewake; // strict prewaking surge
  const _BpStats({
    this.dayMeanS,
    this.nightMeanS,
    this.dayMeanD,
    this.nightMeanD,
    this.dipS,
    this.dipD,
    this.morningSurgeS,
    this.morningSurgeD,
    this.morningSurgeStrictSts,
    this.morningSurgeStrictPrewake,
  });
}

// Strict surge logic moved to services/metrics.dart

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendToggle extends StatelessWidget {
  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _LegendToggle({
    required this.color,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: t)),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final _ViewMode mode;
  final List<_BPEntry> series;
  final List<_BPEntry>? seriesA;
  final List<_BPEntry>? seriesB;
  final int? anchorMinute;
  const _SummaryCards({
    required this.mode,
    required this.series,
    this.seriesA,
    this.seriesB,
    this.anchorMinute,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == _ViewMode.trend && series.isEmpty) {
      return const SizedBox.shrink();
    }
    if (mode == _ViewMode.averageDay && series.isEmpty) {
      return const SizedBox.shrink();
    }
    if (mode == _ViewMode.compare && (seriesA == null || seriesB == null)) {
      return const SizedBox.shrink();
    }

    late final List<_CardData> cards;
    if (mode == _ViewMode.compare) {
      final aggA = avg.AverageDayAggregator(
        series: seriesA!
            .map(
              (e) => avg.AvgBpInput(
                t: e.timestamp,
                sbp: e.systolic,
                dbp: e.diastolic,
              ),
            )
            .toList(),
      ).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      final aggB = avg.AverageDayAggregator(
        series: seriesB!
            .map(
              (e) => avg.AvgBpInput(
                t: e.timestamp,
                sbp: e.systolic,
                dbp: e.diastolic,
              ),
            )
            .toList(),
      ).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      cards = _buildCompareCards(aggA, aggB);
    } else {
      final agg = avg.AverageDayAggregator(
        series: series
            .map(
              (e) => avg.AvgBpInput(
                t: e.timestamp,
                sbp: e.systolic,
                dbp: e.diastolic,
              ),
            )
            .toList(),
      ).compute(stepMinutes: 15, smoothMinutes: 45, anchorMinute: anchorMinute);
      cards = _buildSingleCards(agg);
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final c in cards) _SummaryCard(data: c)],
    );
  }

  List<_CardData> _buildSingleCards(avg.AvgDay agg) {
    final segs = _segments();
    return [
      for (final s in segs)
        _CardData(
          title: s.label,
          sbp: _segMean(agg.minutes, agg.sysMean, s.startMin, s.endMin),
          dbp: _segMean(agg.minutes, agg.diaMean, s.startMin, s.endMin),
        ),
    ];
  }

  List<_CardData> _buildCompareCards(avg.AvgDay a, avg.AvgDay b) {
    final segs = _segments();
    return [
      for (final s in segs)
        _CardData(
          title: s.label,
          deltaSbp: _segDelta(
            a.minutes,
            a.sysMean,
            b.minutes,
            b.sysMean,
            s.startMin,
            s.endMin,
          ),
          deltaDbp: _segDelta(
            a.minutes,
            a.diaMean,
            b.minutes,
            b.diaMean,
            s.startMin,
            s.endMin,
          ),
          isDelta: true,
        ),
    ];
  }

  double? _segMean(
    List<int> mins,
    List<double?> values,
    int startMin,
    int endMin,
  ) {
    double sum = 0;
    int n = 0;
    for (int i = 0; i < mins.length; i++) {
      final m = mins[i];
      if (_inSeg(m, startMin, endMin)) {
        final v = values[i];
        if (v != null) {
          sum += v;
          n++;
        }
      }
    }
    return n > 0 ? sum / n : null;
  }

  double? _segDelta(
    List<int> amins,
    List<double?> a,
    List<int> bmins,
    List<double?> b,
    int startMin,
    int endMin,
  ) {
    // assume same binning; align by minute index
    final meanA = _segMean(amins, a, startMin, endMin);
    final meanB = _segMean(bmins, b, startMin, endMin);
    if (meanA == null || meanB == null) return null;
    return meanB - meanA;
  }

  bool _inSeg(int minuteOfDay, int startMin, int endMin) {
    if (startMin <= endMin) {
      return minuteOfDay >= startMin && minuteOfDay < endMin;
    }
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
  final String label;
  final int startMin;
  final int endMin;
  const _Segment(this.label, this.startMin, this.endMin);
}

class _CardData {
  final String title;
  final double? sbp;
  final double? dbp; // for single
  final double? deltaSbp;
  final double? deltaDbp; // for compare
  final bool isDelta;
  _CardData({
    required this.title,
    this.sbp,
    this.dbp,
    this.deltaSbp,
    this.deltaDbp,
    this.isDelta = false,
  });
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
              Row(
                children: [
                  Text('SBP: ${_f(data.sbp)} mmHg'),
                  const SizedBox(width: 12),
                  Text('DBP: ${_f(data.dbp)} mmHg'),
                ],
              )
            else
              Row(
                children: [
                  Text('ΔSBP: ${_fSigned(data.deltaSbp)} mmHg'),
                  const SizedBox(width: 12),
                  Text('ΔDBP: ${_fSigned(data.deltaDbp)} mmHg'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _f(double? v) => v == null ? '-' : v.toStringAsFixed(0);
  String _fSigned(double? v) => v == null
      ? '-'
      : (v >= 0 ? '+${v.toStringAsFixed(0)}' : v.toStringAsFixed(0));
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
        const Text(
          'Recent Readings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (mode != _ViewMode.compare)
          _buildList(context, entries)
        else ...[
          const Text('Range A'),
          const SizedBox(height: 6),
          if (entriesA != null)
            _buildList(context, entriesA!)
          else
            const Text('-'),
          const SizedBox(height: 12),
          const Text('Range B'),
          const SizedBox(height: 6),
          if (entriesB != null)
            _buildList(context, entriesB!)
          else
            const Text('-'),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : onLoadMore,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history),
              label: const Text('Load earlier (90 days)'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, List<_BPEntry> src) {
    final list = [...src];
    list.sort(
      (a, b) =>
          (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)),
    );
    final shown = list.take(limit).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListView.separated(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final e = shown[i];
          return ListTile(
            dense: true,
            title: Text(_fmtDate(e.timestamp)),
            subtitle: Text(_fmtTime(e.timestamp)),
            trailing: Text(
              _bpText(e),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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

String _effectiveRangeLabel(
  List<_BPEntry> entries,
  DateTime start,
  DateTime end,
) {
  final ts =
      entries
          .where((e) => e.timestamp != null)
          .map((e) => e.timestamp!)
          .toList()
        ..sort();
  if (ts.isEmpty) {
    return 'Effective: —';
  }
  final effStart = ts.first.isAfter(start) ? ts.first : start;
  final effEnd = ts.last.isBefore(end) ? ts.last : end;
  final daysWithReadings = ts
      .map((t) => DateTime(t.year, t.month, t.day))
      .toSet()
      .length;
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return 'Effective: ${fmt(effStart)} — ${fmt(effEnd)}  •  $daysWithReadings day(s) with readings';
}
