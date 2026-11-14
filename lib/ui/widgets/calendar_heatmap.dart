import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../domain/anomaly.dart';
import '../../theme/app_theme.dart';

/// The burning calendar: one row per year, one column per month.
/// Tap a cell to see its numbers.
class CalendarHeatmap extends StatelessWidget {
  const CalendarHeatmap({
    super.key,
    required this.record,
    required this.harmonized,
    required this.monthLabels,
    this.onCellTap,
  });

  final FireRecord record;
  final bool harmonized;
  final List<String> monthLabels;
  final void Function(MonthlyCount cell)? onCellTap;

  static const labelWidth = 40.0;
  static const headerHeight = 18.0;
  static const rowHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    final years = record.latestYear - record.firstYear + 1;
    return LayoutBuilder(builder: (context, constraints) {
      final cellWidth = (constraints.maxWidth - labelWidth) / 12;
      return GestureDetector(
        onTapUp: (d) {
          final col = ((d.localPosition.dx - labelWidth) / cellWidth).floor();
          final row = ((d.localPosition.dy - headerHeight) / rowHeight).floor();
          if (col < 0 || col > 11 || row < 0 || row >= years) return;
          final cell = record.at(record.firstYear + row, col + 1);
          if (cell != null) onCellTap?.call(cell);
        },
        child: CustomPaint(
          size: Size(constraints.maxWidth, headerHeight + rowHeight * years),
          painter: _HeatmapPainter(record, harmonized, monthLabels),
        ),
      );
    });
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(this.record, this.harmonized, this.monthLabels);

  final FireRecord record;
  final bool harmonized;
  final List<String> monthLabels;

  @override
  void paint(Canvas canvas, Size size) {
    const lw = CalendarHeatmap.labelWidth;
    const hh = CalendarHeatmap.headerHeight;
    const rh = CalendarHeatmap.rowHeight;
    final cw = (size.width - lw) / 12;

    // Same scale for raw and harmonized so the seam is visible.
    final maxValue = record.monthly
        .map((c) => math.max(c.raw, c.harmonized))
        .reduce(math.max)
        .toDouble();
    final logMax = math.log(1 + maxValue);

    for (var m = 1; m <= 12; m++) {
      _label(canvas, monthLabels[m - 1], Offset(lw + (m - 1) * cw, 0), cw,
          TextAlign.center);
    }

    final cellPaint = Paint();
    for (final c in record.monthly) {
      final row = c.year - record.firstYear;
      if (c.month == 1 && (c.year % 2 == 0 || c.year == record.latestYear)) {
        _label(canvas, '${c.year}', Offset(0, hh + row * rh + 2), lw - 6,
            TextAlign.right);
      }
      final t = math.log(1 + c.value(harmonized: harmonized)) / logMax;
      cellPaint.color = Ember.heat(t);
      final rect = Rect.fromLTWH(
          lw + (c.month - 1) * cw + 1, hh + row * rh + 1, cw - 2, rh - 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), cellPaint);
    }

    // The seam: where VIIRS starts.
    const seamYear = 2012;
    final seamY = hh + (seamYear - record.firstYear) * rh;
    canvas.drawLine(
      Offset(lw - 4, seamY),
      Offset(size.width, seamY),
      Paint()
        ..color = harmonized ? Ember.textMuted.withValues(alpha: 0.4) : Ember.text
        ..strokeWidth = harmonized ? 1 : 2,
    );

    // Outline the latest month.
    final latestRow = record.latestYear - record.firstYear;
    canvas.drawRect(
      Rect.fromLTWH(lw + (record.latestMonth - 1) * cw, hh + latestRow * rh,
          cw, rh),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Ember.text,
    );
  }

  void _label(Canvas canvas, String s, Offset at, double width, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: monoStyle(size: 10)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.record != record || old.harmonized != harmonized;
}

/// Yearly totals as bars: shows the 2012 jump in raw data and its removal.
class YearlyBars extends StatelessWidget {
  const YearlyBars({
    super.key,
    required this.record,
    required this.harmonized,
    this.height = 120,
  });

  final FireRecord record;
  final bool harmonized;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _BarsPainter(record, harmonized)),
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.record, this.harmonized);
  final FireRecord record;
  final bool harmonized;

  @override
  void paint(Canvas canvas, Size size) {
    // Only full years, so the partial latest year doesn't look like a dip.
    final raw = yearlyTotals(record, harmonized: false)
      ..remove(record.latestMonth < 12 ? record.latestYear : null);
    final fixed = yearlyTotals(record, harmonized: true)
      ..remove(record.latestMonth < 12 ? record.latestYear : null);
    final shown = harmonized ? fixed : raw;
    final maxV = fixed.values.followedBy(raw.values).reduce(math.max).toDouble();
    final years = shown.keys.toList()..sort();
    final bw = size.width / years.length;
    const bottom = 14.0;
    final h = size.height - bottom;

    for (var i = 0; i < years.length; i++) {
      final y = years[i];
      final v = shown[y]!.toDouble();
      final bh = v / maxV * h;
      final isModis = y < 2012;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw + 1, h - bh, bw - 2, bh),
          const Radius.circular(2),
        ),
        Paint()
          ..color = isModis && !harmonized ? Ember.ash : Ember.ember,
      );
      if (y % 5 == 0) {
        final tp = TextPainter(
          text: TextSpan(text: '$y', style: monoStyle(size: 9)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * bw, h + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.record != record || old.harmonized != harmonized;
}
