import 'package:flutter/material.dart';
import 'package:health/health.dart';

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
  const LatestBPPage({super.key});
  @override
  State<LatestBPPage> createState() => _LatestBPPageState();
}

class _LatestBPPageState extends State<LatestBPPage> {
  final Health _health = Health();
  bool _loading = false;
  String? _error;
  _BPEntry? _latest;

  @override
  void initState() {
    super.initState();
    _fetchLatest();
  }

  Future<void> _fetchLatest() async {
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

      DateTime end = DateTime.now();
      DateTime start = end.subtract(const Duration(days: 30));
      var points = await _health.getHealthDataFromTypes(start, end, types);

      // If nothing in last 30 days, try requesting history permission and extend window
      if (points.isEmpty) {
        try {
          final histGranted = await _health.requestHealthDataHistoryAuthorization();
          if (histGranted) {
            start = end.subtract(const Duration(days: 365));
            points = await _health.getHealthDataFromTypes(start, end, types);
          }
        } catch (_) {
          // Ignore; not all platforms/versions support this call
        }
      }

      final latest = _combineLatestBP(points);
      setState(() {
        _latest = latest;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  _BPEntry? _combineLatestBP(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    points.sort((a, b) => (b.dateTo).compareTo(a.dateTo));

    final systolic = <HealthDataPoint>[];
    final diastolic = <HealthDataPoint>[];
    for (final p in points) {
      if (p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC) systolic.add(p);
      if (p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC) diastolic.add(p);
    }
    if (systolic.isEmpty && diastolic.isEmpty) return null;

    HealthDataPoint? bestSys = systolic.isNotEmpty ? systolic.first : null;
    HealthDataPoint? matchDia;
    if (bestSys != null) {
      matchDia = _findClosest(diastolic, bestSys.dateTo);
    }
    // Fallback: if no systolic or no close match, pick independent latest values
    bestSys ??= systolic.isNotEmpty ? systolic.first : null;
    matchDia ??= diastolic.isNotEmpty ? diastolic.first : null;

    final ts = _mostRecentTime([bestSys?.dateTo, matchDia?.dateTo]);
    return _BPEntry(
      timestamp: ts,
      systolic: _toDouble(bestSys?.value),
      diastolic: _toDouble(matchDia?.value),
      source: bestSys?.sourceId ?? matchDia?.sourceId,
    );
  }

  HealthDataPoint? _findClosest(List<HealthDataPoint> list, DateTime t) {
    if (list.isEmpty) return null;
    HealthDataPoint? best;
    var bestDelta = const Duration(days: 365);
    for (final p in list) {
      final d = (p.dateTo.difference(t)).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = p;
      }
      if (bestDelta <= const Duration(minutes: 10)) break; // close enough
    }
    return best;
  }

  DateTime? _mostRecentTime(List<DateTime?> times) {
    DateTime? r;
    for (final t in times) {
      if (t == null) continue;
      if (r == null || t.isAfter(r)) r = t;
    }
    return r;
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest Blood Pressure'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchLatest,
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
              'Note: Health Connect access may initially show recent data only. '\
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
    return DataTable(columns: const [
      DataColumn(label: Text('Date')),
      DataColumn(label: Text('Time')),
      DataColumn(label: Text('Systolic')),
      DataColumn(label: Text('Diastolic')),
      DataColumn(label: Text('Source')),
    ], rows: [
      DataRow(cells: [
        DataCell(Text(_formatDate(entry?.timestamp))),
        DataCell(Text(_formatTime(entry?.timestamp))),
        DataCell(Text(entry?.systolic?.toStringAsFixed(0) ?? '-')),
        DataCell(Text(entry?.diastolic?.toStringAsFixed(0) ?? '-')),
        DataCell(Text(entry?.source ?? '-')),
      ])
    ]);
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
