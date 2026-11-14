import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../theme/app_theme.dart';

/// This year (line) against the normal range (band = 10th–90th percentile,
/// dashed line = median) for each month.
class SeasonChart extends StatelessWidget {
  const SeasonChart({
    super.key,
    required this.record,
    required this.monthLabels,
    this.rangeLabel = 'Normal range',
    this.medianLabel = 'Median',
    this.height = 200,
  });

  final FireRecord record;
  final List<String> monthLabels;
  final String rangeLabel, medianLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _SeasonPainter(record, monthLabels)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Legend(color: Ember.amber.withValues(alpha: 0.25), label:
                '$rangeLabel ${record.baselineFrom}–${record.baselineTo}'),
            _Legend(color: Ember.textMuted, label: medianLabel, dashed: true),
            _Legend(color: Ember.ember, label: '${record.latestYear}'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: dashed ? 2 : 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: monoStyle(size: 11)),
        ],
      );
}

class _SeasonPainter extends CustomPainter {
  _SeasonPainter(this.record, this.monthLabels);
  final FireRecord record;
  final List<String> monthLabels;

  static const leftPad = 36.0, bottomPad = 20.0, topPad = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final current = [
      for (var m = 1; m <= record.latestMonth; m++)
        record.at(record.latestYear, m)!.harmonized.toDouble(),
    ];
    final maxY = [
      ...record.season.map((s) => s.p90),
      ...current,
    ].reduce(math.max) * 1.1;

    final w = size.width - leftPad;
    final h = size.height - bottomPad - topPad;
    double x(int month) => leftPad + (month - 1) / 11 * w;
    double y(double v) => topPad + h - (v / maxY) * h;

    // Grid + y labels.
    final grid = Paint()
      ..color = Ember.outline
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = maxY * i / 3;
      canvas.drawLine(Offset(leftPad, y(v)), Offset(size.width, y(v)), grid);
      _text(canvas, _compact(v), Offset(0, y(v) - 7), width: leftPad - 4,
          align: TextAlign.right);
    }

    // X labels.
    for (var m = 1; m <= 12; m++) {
      _text(canvas, monthLabels[m - 1], Offset(x(m) - 8, size.height - 14),
          width: 16, align: TextAlign.center);
    }

    // Normal band.
    final band = Path()..moveTo(x(1), y(record.season.first.p90));
    for (final s in record.season) {
      band.lineTo(x(s.month), y(s.p90));
    }
    for (final s in record.season.reversed) {
      band.lineTo(x(s.month), y(s.p10));
    }
    band.close();
    canvas.drawPath(band, Paint()..color = Ember.amber.withValues(alpha: 0.18));

    // Median, dashed.
    final medianPaint = Paint()
      ..color = Ember.textMuted
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var m = 1; m < 12; m++) {
      final a = Offset(x(m), y(record.season[m - 1].median));
      final b = Offset(x(m + 1), y(record.season[m].median));
      for (var t = 0.0; t < 1; t += 0.2) {
        canvas.drawLine(Offset.lerp(a, b, t)!, Offset.lerp(a, b, t + 0.1)!,
            medianPaint);
      }
    }

    // Current year.
    final line = Path();
    for (var i = 0; i < current.length; i++) {
      final p = Offset(x(i + 1), y(current[i]));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = Ember.ember
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < current.length; i++) {
      final above = current[i] > record.season[i].p90;
      canvas.drawCircle(Offset(x(i + 1), y(current[i])), above ? 4.5 : 3,
          Paint()..color = above ? Ember.extreme : Ember.ember);
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {double width = 40, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: monoStyle(size: 10)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  static String _compact(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.round().toString();

  @override
  bool shouldRepaint(_SeasonPainter old) => old.record != record;
}
