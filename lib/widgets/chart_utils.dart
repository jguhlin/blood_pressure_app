import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// scheme: 'acc_aha' (US) or 'esc_esh' (EU)
RangeAnnotations zoneAnnotations({
  required bool showSys,
  required bool showDia,
  required bool enabled,
  String scheme = 'acc_aha',
}) {
  if (!enabled) return const RangeAnnotations();
  // Only when exactly one metric is visible
  if (showSys == showDia) return const RangeAnnotations();
  final isSys = showSys && !showDia;
  final bands = <HorizontalRangeAnnotation>[];

  if (isSys) {
    if (scheme == 'esc_esh') {
      // ESC/ESH 2018: <130 normal; 130–139 high-normal; 140–159 grade1; 160–179 grade2; 180+ grade3
      bands.addAll([
        HorizontalRangeAnnotation(
          y1: 0,
          y2: 130,
          color: const Color(0x1128A745),
        ),
        HorizontalRangeAnnotation(
          y1: 130,
          y2: 140,
          color: const Color(0x11FFC107),
        ),
        HorizontalRangeAnnotation(
          y1: 140,
          y2: 160,
          color: const Color(0x11FF9800),
        ),
        HorizontalRangeAnnotation(
          y1: 160,
          y2: 180,
          color: const Color(0x11F44336),
        ),
        HorizontalRangeAnnotation(
          y1: 180,
          y2: 300,
          color: const Color(0x11B71C1C),
        ),
      ]);
    } else {
      // ACC/AHA 2017: <120 normal; 120–129 elevated; 130–139 stage1; 140–179 stage2; 180+ crisis
      bands.addAll([
        HorizontalRangeAnnotation(
          y1: 0,
          y2: 120,
          color: const Color(0x1128A745),
        ),
        HorizontalRangeAnnotation(
          y1: 120,
          y2: 130,
          color: const Color(0x11FFC107),
        ),
        HorizontalRangeAnnotation(
          y1: 130,
          y2: 140,
          color: const Color(0x11FF9800),
        ),
        HorizontalRangeAnnotation(
          y1: 140,
          y2: 180,
          color: const Color(0x11F44336),
        ),
        HorizontalRangeAnnotation(
          y1: 180,
          y2: 300,
          color: const Color(0x11B71C1C),
        ),
      ]);
    }
  } else {
    if (scheme == 'esc_esh') {
      // ESC/ESH 2018: DBP <85 normal; 85–89 high-normal; 90–99 grade1; 100–109 grade2; 110+ grade3
      bands.addAll([
        HorizontalRangeAnnotation(
          y1: 0,
          y2: 85,
          color: const Color(0x1128A745),
        ),
        HorizontalRangeAnnotation(
          y1: 85,
          y2: 90,
          color: const Color(0x11FFC107),
        ),
        HorizontalRangeAnnotation(
          y1: 90,
          y2: 100,
          color: const Color(0x11FF9800),
        ),
        HorizontalRangeAnnotation(
          y1: 100,
          y2: 110,
          color: const Color(0x11F44336),
        ),
        HorizontalRangeAnnotation(
          y1: 110,
          y2: 300,
          color: const Color(0x11B71C1C),
        ),
      ]);
    } else {
      // ACC/AHA 2017: <80 normal; 80–89 stage1; 90–119 stage2; 120+ crisis
      bands.addAll([
        HorizontalRangeAnnotation(
          y1: 0,
          y2: 80,
          color: const Color(0x1128A745),
        ),
        HorizontalRangeAnnotation(
          y1: 80,
          y2: 90,
          color: const Color(0x11FF9800),
        ),
        HorizontalRangeAnnotation(
          y1: 90,
          y2: 120,
          color: const Color(0x11F44336),
        ),
        HorizontalRangeAnnotation(
          y1: 120,
          y2: 300,
          color: const Color(0x11B71C1C),
        ),
      ]);
    }
  }
  return RangeAnnotations(horizontalRangeAnnotations: bands);
}

Color colorForSbp(num? sbp, {String scheme = 'acc_aha'}) {
  if (sbp == null) return Colors.black87;
  final v = sbp.toDouble();
  if (scheme == 'esc_esh') {
    if (v >= 180) return const Color(0xFFB71C1C);
    if (v >= 160) return const Color(0xFFF44336);
    if (v >= 140) return const Color(0xFFFF9800);
    if (v >= 130) return const Color(0xFFFFC107);
    return const Color(0xFF28A745);
  } else {
    if (v >= 180) return const Color(0xFFB71C1C);
    if (v >= 140) return const Color(0xFFF44336);
    if (v >= 130) return const Color(0xFFFF9800);
    if (v >= 120) return const Color(0xFFFFC107);
    return const Color(0xFF28A745);
  }
}

Color colorForDbp(num? dbp, {String scheme = 'acc_aha'}) {
  if (dbp == null) return Colors.black87;
  final v = dbp.toDouble();
  if (scheme == 'esc_esh') {
    if (v >= 110) return const Color(0xFFB71C1C);
    if (v >= 100) return const Color(0xFFF44336);
    if (v >= 90) return const Color(0xFFFF9800);
    if (v >= 85) return const Color(0xFFFFC107);
    return const Color(0xFF28A745);
  } else {
    if (v >= 120) return const Color(0xFFB71C1C);
    if (v >= 90) return const Color(0xFFF44336);
    if (v >= 80) return const Color(0xFFFF9800);
    return const Color(0xFF28A745);
  }
}
