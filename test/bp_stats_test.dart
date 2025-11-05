import 'package:flutter_test/flutter_test.dart';
import 'package:blood_pressure_app/services/metrics.dart' as met;
import 'package:health/health.dart' as health; // only for type presence; not used directly

void main() {
  test('dipping and day/night means compute', () async {
    final d = DateTime(2025, 1, 1);
    final points = <met.BpPoint>[
      // Daytime
      met.BpPoint(t: d.add(const Duration(hours: 10)), sbp: 130, dbp: 85),
      met.BpPoint(t: d.add(const Duration(hours: 12)), sbp: 128, dbp: 82),
      // Nighttime
      met.BpPoint(t: d.add(const Duration(hours: 2)), sbp: 115, dbp: 70),
      met.BpPoint(t: d.add(const Duration(hours: 3)), sbp: 112, dbp: 68),
    ];
    final stats = await met.computeBpStats(points: points, health: _NullHealth(), params: const met.SurgeParams());
    expect(stats.dayMeanS, closeTo(129, 1));
    expect(stats.nightMeanS, closeTo(114, 1));
    expect(stats.dipS, inInclusiveRange(10, 15));
  });
}

// Minimal fake Health that is never used in this test path
class _NullHealth implements health.Health {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

