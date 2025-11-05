import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

RangeAnnotations zoneAnnotations({required bool showSys, required bool showDia}) {
  if (showSys == showDia) return const RangeAnnotations();
  final isSys = showSys && !showDia;
  final bands = <HorizontalRangeAnnotation>[];
  if (isSys) {
    bands.addAll([
      HorizontalRangeAnnotation(y1: 0, y2: 120, color: const Color(0x1128A745)),
      HorizontalRangeAnnotation(y1: 120, y2: 130, color: const Color(0x11FFC107)),
      HorizontalRangeAnnotation(y1: 130, y2: 140, color: const Color(0x11FF9800)),
      HorizontalRangeAnnotation(y1: 140, y2: 180, color: const Color(0x11F44336)),
      HorizontalRangeAnnotation(y1: 180, y2: 300, color: const Color(0x11B71C1C)),
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

