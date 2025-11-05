import 'dart:math' as math;
import 'package:health/health.dart';

class BpPoint {
  final DateTime? t;
  final double? sbp;
  final double? dbp;
  BpPoint({required this.t, required this.sbp, required this.dbp});
}

class SurgeParams {
  final int morningWindowHours;
  final int troughWindowHours;
  final int prewakeHours;
  final int hrRiseBpm;
  final int steps30Min;
  final int wakeEarliestHour;
  final int wakeLatestHour;
  const SurgeParams({
    this.morningWindowHours = 2,
    this.troughWindowHours = 6,
    this.prewakeHours = 2,
    this.hrRiseBpm = 10,
    this.steps30Min = 100,
    this.wakeEarliestHour = 3,
    this.wakeLatestHour = 11,
  });
}

class StrictSurge { final double? sts, prewake; const StrictSurge({this.sts, this.prewake}); }

class BpStats {
  final double? dayMeanS, nightMeanS, dayMeanD, nightMeanD;
  final double? dipS, dipD;
  final double? morningSurgeS, morningSurgeD;
  final double? morningSurgeStrictSts, morningSurgeStrictPrewake;
  const BpStats({
    this.dayMeanS, this.nightMeanS, this.dayMeanD, this.nightMeanD,
    this.dipS, this.dipD,
    this.morningSurgeS, this.morningSurgeD,
    this.morningSurgeStrictSts, this.morningSurgeStrictPrewake,
  });
}

Future<BpStats> computeBpStats({required List<BpPoint> points, required Health health, required SurgeParams params}) async {
  bool isDay(DateTime t) => t.hour >= 6 && t.hour < 22;
  bool isMorning(DateTime t) => t.hour >= 6 && t.hour < 10;
  bool isEarlyMorning(DateTime t) => t.hour >= 2 && t.hour < 6;
  final dayS = <double>[], nightS = <double>[], dayD = <double>[], nightD = <double>[];
  final morningS = <double>[], morningD = <double>[], earlyS = <double>[], earlyD = <double>[];
  for (final e in points) {
    final t = e.t; if (t == null) continue;
    if (e.sbp != null) {
      if (isDay(t)) dayS.add(e.sbp!); else nightS.add(e.sbp!);
      if (isMorning(t)) morningS.add(e.sbp!);
      if (isEarlyMorning(t)) earlyS.add(e.sbp!);
    }
    if (e.dbp != null) {
      if (isDay(t)) dayD.add(e.dbp!); else nightD.add(e.dbp!);
      if (isMorning(t)) morningD.add(e.dbp!);
      if (isEarlyMorning(t)) earlyD.add(e.dbp!);
    }
  }
  double? mean(List<double> a) => a.isEmpty ? null : a.reduce((x,y)=>x+y)/a.length;
  final dayMeanS = mean(dayS), nightMeanS = mean(nightS);
  final dayMeanD = mean(dayD), nightMeanD = mean(nightD);
  double? dip(double? day, double? night) => (day != null && night != null && day > 0) ? ((day - night) / day * 100.0) : null;
  final dipS = dip(dayMeanS, nightMeanS);
  final dipD = dip(dayMeanD, nightMeanD);
  final morningSurgeS = (mean(morningS) != null && mean(earlyS) != null) ? (mean(morningS)! - mean(earlyS)!) : null;
  final morningSurgeD = (mean(morningD) != null && mean(earlyD) != null) ? (mean(morningD)! - mean(earlyD)!) : null;

  final strict = await _computeMorningSurgeStrict(points, health, params);
  return BpStats(
    dayMeanS: dayMeanS, nightMeanS: nightMeanS,
    dayMeanD: dayMeanD, nightMeanD: nightMeanD,
    dipS: dipS, dipD: dipD,
    morningSurgeS: morningSurgeS, morningSurgeD: morningSurgeD,
    morningSurgeStrictSts: strict.sts,
    morningSurgeStrictPrewake: strict.prewake,
  );
}

Future<StrictSurge> computeStrictWithWakeTimes(List<BpPoint> points, Map<DateTime, DateTime> wakes, SurgeParams p) async {
  final byDay = <DateTime, List<BpPoint>>{};
  for (final e in points) {
    final t = e.t; if (t == null || e.sbp == null) continue;
    final day = DateTime(t.year, t.month, t.day);
    (byDay[day] ??= []).add(e);
  }
  double? stsSum; int stsN = 0;
  double? preSum; int preN = 0;
  byDay.forEach((day, list){
    final wake = wakes[day];
    if (wake == null) return;
    final morningStart = wake;
    final morningEnd = wake.add(Duration(hours: p.morningWindowHours));
    final preStart = wake.subtract(Duration(hours: p.prewakeHours));
    final preEnd = wake;
    final troughStart = wake.subtract(Duration(hours: p.troughWindowHours));
    final troughEnd = wake;
    double? maxMorning; double? minTrough; double sumPre = 0; int nPre = 0;
    for (final e in list) {
      final t = e.t!; final v = e.sbp!;
      if (!t.isBefore(morningStart) && !t.isAfter(morningEnd)) { maxMorning = (maxMorning == null) ? v : math.max(maxMorning, v); }
      if (!t.isBefore(troughStart) && !t.isAfter(troughEnd)) { minTrough = (minTrough == null) ? v : math.min(minTrough, v); }
      if (!t.isBefore(preStart) && !t.isAfter(preEnd)) { sumPre += v; nPre++; }
    }
    if (maxMorning != null && minTrough != null) { stsSum = (stsSum ?? 0) + (maxMorning - minTrough); stsN++; }
    if (maxMorning != null && nPre > 0) { preSum = (preSum ?? 0) + (maxMorning - (sumPre / nPre)); preN++; }
  });
  return StrictSurge(
    sts: (stsSum != null && stsN > 0) ? (stsSum! / stsN) : null,
    prewake: (preSum != null && preN > 0) ? (preSum! / preN) : null,
  );
}

Future<StrictSurge> _computeMorningSurgeStrict(List<BpPoint> s, Health health, SurgeParams params) async {
  final times = s.where((e)=>e.t!=null).map((e)=>e.t!).toList()..sort();
  if (times.isEmpty) return const StrictSurge();
  final start = times.first.subtract(const Duration(days: 1));
  final end = times.last.add(const Duration(days: 1));
  final wakes = await _inferWakeTimesStrict(health, start, end, params);
  return computeStrictWithWakeTimes(s, wakes, params);
}

Future<Map<DateTime, DateTime>> _inferWakeTimesStrict(Health health, DateTime start, DateTime end, SurgeParams p) async {
  final map = <DateTime, DateTime>{};
  try {
    final sleep = await health.getHealthDataFromTypes(types: const [HealthDataType.SLEEP_ASLEEP], startTime: start, endTime: end);
    final byDay = <DateTime, List<HealthDataPoint>>{};
    for (final pt in sleep) { final d = DateTime(pt.dateTo.year, pt.dateTo.month, pt.dateTo.day); (byDay[d] ??= []).add(pt); }
    for (final e in byDay.entries) {
      DateTime? best;
      for (final pnt in e.value) {
        final lt = pnt.dateTo.toLocal();
        if (lt.hour >= p.wakeEarliestHour && lt.hour <= p.wakeLatestHour) { if (best == null || lt.isAfter(best)) best = lt; }
      }
      if (best != null) map[e.key] = best;
    }
  } catch (_) {}

  void setIfEmpty(DateTime key, DateTime value) { map.putIfAbsent(key, () => value); }

  try {
    final steps = await health.getHealthDataFromTypes(types: const [HealthDataType.STEPS], startTime: start, endTime: end);
    final bins = <DateTime, List<double>>{};
    for (final pnt in steps) {
      final from = pnt.dateFrom.toLocal(); final to = pnt.dateTo.toLocal(); double val = _toDouble(pnt.value) ?? 0;
      DateTime cur = from;
      while (cur.isBefore(to)) {
        final day = DateTime(cur.year, cur.month, cur.day);
        final idx = ((cur.hour*60 + cur.minute) / 15).floor().clamp(0,95);
        final l = bins.putIfAbsent(day, () => List<double>.filled(96, 0));
        l[idx] += val; cur = cur.add(const Duration(minutes: 15));
      }
    }
    for (final e in bins.entries) {
      if (map.containsKey(e.key)) continue;
      final l = e.value;
      final startIdx = (p.wakeEarliestHour*60 ~/ 15).clamp(0,95);
      final endIdx = (p.wakeLatestHour*60 ~/ 15).clamp(0,95);
      for (int i = startIdx; i <= endIdx; i++) {
        final sum30 = l[i] + (i+1<l.length? l[i+1]:0);
        if (sum30 >= p.steps30Min) { setIfEmpty(e.key, DateTime(e.key.year,e.key.month,e.key.day).add(Duration(minutes: i*15))); break; }
      }
    }
  } catch (_) {}

  try {
    final hr = await health.getHealthDataFromTypes(types: const [HealthDataType.HEART_RATE], startTime: start, endTime: end);
    final byDay = <DateTime, List<_SimpleSample>>{};
    for (final pnt in hr) {
      final d = DateTime(pnt.dateTo.year, pnt.dateTo.month, pnt.dateTo.day);
      final v = _toDouble(pnt.value); if (v == null) continue;
      (byDay[d] ??= []).add(_SimpleSample(t: pnt.dateTo.toLocal(), v: v));
    }
    for (final e in byDay.entries) {
      if (map.containsKey(e.key)) continue;
      final points = e.value..sort((a,b)=>a.t.compareTo(b.t));
      final baseVals = points.where((p)=> p.t.hour>=2 && p.t.hour<5).map((p)=>p.v).toList()..sort();
      if (baseVals.isEmpty) continue;
      double baseline = baseVals[baseVals.length ~/ 2];
      for (int i = 0; i < points.length; i++) {
        final t = points[i].t; if (t.hour < p.wakeEarliestHour + 2) continue;
        double sum = 0; int n = 0;
        for (int j = i; j < points.length; j++) { if (points[j].t.difference(t).inMinutes > 20) break; sum += points[j].v; n++; }
        if (n > 0 && (sum / n) >= baseline + p.hrRiseBpm) { setIfEmpty(e.key, t); break; }
      }
    }
  } catch (_) {}

  return map;
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  try { if (value is NumericHealthValue) { return (value.numericValue).toDouble(); } } catch (_) {}
  try { final json = value.toJson(); final dyn = json['numericValue'] ?? json['value']; if (dyn is num) return dyn.toDouble(); if (dyn is String) return double.tryParse(dyn); } catch (_) {}
  try { return double.parse(value.toString()); } catch (_) { return null; }
}

class _SimpleSample { final DateTime t; final double v; _SimpleSample({required this.t, required this.v}); }
