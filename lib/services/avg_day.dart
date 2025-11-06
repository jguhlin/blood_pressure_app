import 'dart:math' as math;

class AvgDay {
  final List<int> minutes; // minutes since midnight
  final List<double?> sysMean; // smoothed means
  final List<double?> diaMean;
  // Quantiles (smoothed across bins)
  final List<double?>? sysQ50;
  final List<double?>? sysQ25;
  final List<double?>? sysQ75;
  final List<double?>? diaQ50;
  final List<double?>? diaQ25;
  final List<double?>? diaQ75;
  final List<double?>? sysLower; // optional 95% CI lower
  final List<double?>? sysUpper;
  final List<double?>? diaLower;
  final List<double?>? diaUpper;
  const AvgDay({
    required this.minutes,
    required this.sysMean,
    required this.diaMean,
    this.sysQ50,
    this.sysQ25,
    this.sysQ75,
    this.diaQ50,
    this.diaQ25,
    this.diaQ75,
    this.sysLower,
    this.sysUpper,
    this.diaLower,
    this.diaUpper,
  });
}

class AvgBpInput {
  final DateTime? t;
  final double? sbp;
  final double? dbp;
  const AvgBpInput({required this.t, required this.sbp, required this.dbp});
}

class AverageDayAggregator {
  final List<AvgBpInput> series;
  AverageDayAggregator({required this.series});

  AvgDay compute({
    int stepMinutes = 15,
    int smoothMinutes = 45,
    int? anchorMinute,
    bool withBands = false,
  }) {
    final step = stepMinutes;
    final bins = (24 * 60) ~/ step;
    final days = <DateTime, _DayBins>{};

    double clamp(double v) => v.clamp(40.0, 220.0);

    for (final e in series) {
      final t = e.t;
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

      if (e.sbp != null) {
        final v = clamp(e.sbp!);
        d.sysSum[i0] += v * (1 - frac);
        d.sysW[i0] += (1 - frac);
        d.sysSum[i1] += v * frac;
        d.sysW[i1] += frac;
      }
      if (e.dbp != null) {
        final v = clamp(e.dbp!);
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

    // Per-bin quantiles across days
    List<double?> quantileOfDays(List<List<double?>> perDay, double q) {
      final out = List<double?>.filled(bins, null);
      for (int i = 0; i < bins; i++) {
        final vals = <double>[];
        for (final day in perDay) {
          final v = day[i];
          if (v != null) vals.add(v);
        }
        if (vals.isEmpty) continue;
        vals.sort();
        final pos = (vals.length - 1) * q;
        final idx = pos.floor();
        final frac = pos - idx;
        double v;
        if (idx + 1 < vals.length) {
          v = vals[idx] * (1 - frac) + vals[idx + 1] * frac;
        } else {
          v = vals[idx];
        }
        out[i] = v;
      }
      return out;
    }

    var sysQ50 = quantileOfDays(perDaySys, 0.5);
    var sysQ25 = quantileOfDays(perDaySys, 0.25);
    var sysQ75 = quantileOfDays(perDaySys, 0.75);
    var diaQ50 = quantileOfDays(perDayDia, 0.5);
    var diaQ25 = quantileOfDays(perDayDia, 0.25);
    var diaQ75 = quantileOfDays(perDayDia, 0.75);

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
    // Smooth quantiles as well
    sysQ50 = smooth(sysQ50);
    sysQ25 = smooth(sysQ25);
    sysQ75 = smooth(sysQ75);
    diaQ50 = smooth(diaQ50);
    diaQ25 = smooth(diaQ25);
    diaQ75 = smooth(diaQ75);
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

    return AvgDay(
      minutes: minutes,
      sysMean: sysSmooth,
      diaMean: diaSmooth,
      sysQ50: sysQ50,
      sysQ25: sysQ25,
      sysQ75: sysQ75,
      diaQ50: diaQ50,
      diaQ25: diaQ25,
      diaQ75: diaQ75,
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

// No extra types exported beyond AvgBpInput/AvgDay
