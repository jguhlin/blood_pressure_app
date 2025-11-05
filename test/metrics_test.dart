import 'package:flutter_test/flutter_test.dart';
import 'package:blood_pressure_app/services/metrics.dart' as met;

void main() {
  test('strict surge with provided wake times', () async {
    // Build 1 day with trough 04:00 SBP 110, morning 07:00 SBP 130
    final day = DateTime(2025, 1, 1);
    final pts = <met.BpPoint>[
      met.BpPoint(t: day.add(const Duration(hours: 4)), sbp: 110, dbp: 70),
      met.BpPoint(t: day.add(const Duration(hours: 7)), sbp: 130, dbp: 80),
      met.BpPoint(t: day.add(const Duration(hours: 8)), sbp: 126, dbp: 78),
    ];
    final wakes = { DateTime(day.year, day.month, day.day): day.add(const Duration(hours: 6)) };
    final p = const met.SurgeParams(morningWindowHours: 2, troughWindowHours: 6, prewakeHours: 2);
    final strict = await met.computeStrictWithWakeTimes(pts, wakes, p);
    expect(strict.sts, closeTo(20, 1e-6)); // 130 - 110
    expect(strict.prewake, isNotNull);
  });
}

