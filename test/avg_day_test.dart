import 'package:flutter_test/flutter_test.dart';
import 'package:blood_pressure_app/services/avg_day.dart' as avg;

void main() {
  test('average day binning with anchor shifts correctly', () {
    final day = DateTime(2025, 1, 1);
    final series = <avg.AvgBpInput>[
      avg.AvgBpInput(t: day.add(const Duration(hours: 8)), sbp: 120, dbp: 80),
      avg.AvgBpInput(t: day.add(const Duration(hours: 20)), sbp: 130, dbp: 85),
    ];
    final aggNoAnchor = avg.AverageDayAggregator(
      series: series,
    ).compute(stepMinutes: 60, smoothMinutes: 1, anchorMinute: null);
    final aggAnchor = avg.AverageDayAggregator(
      series: series,
    ).compute(stepMinutes: 60, smoothMinutes: 1, anchorMinute: 8 * 60);
    // Expect same values present but shifted to 0 (since anchor at 08:00)
    final i8 = aggNoAnchor.minutes.indexOf(8 * 60);
    expect(aggAnchor.sysMean.first, aggNoAnchor.sysMean[i8]);
  });
}
