import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/fire_record.dart';
import '../../theme/app_theme.dart';

/// One ring per year, like tree rings. The innermost ring is the first year,
/// the outermost is the latest. Each ring has 12 month segments, January at
/// the top, going clockwise. Brighter = more fire.
class FireRings extends StatelessWidget {
  const FireRings({
    super.key,
    required this.record,
    this.harmonized = true,
    this.size = 280,
    this.caption,
  });

  final FireRecord record;
  final bool harmonized;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _FireRingsPainter(record, harmonized),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${record.firstYear}', style: monoStyle(size: 11)),
                  Text('↓', style: monoStyle(size: 11)),
                  Text('${record.latestYear}', style: monoStyle(size: 11)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          caption ??
              'Inner ring ${record.firstYear} · outer ring ${record.latestYear} · '
                  'January at top, clockwise',
          style: monoStyle(size: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _FireRingsPainter extends CustomPainter {
  _FireRingsPainter(this.record, this.harmonized);

  final FireRecord record;
  final bool harmonized;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.22;
    final years = record.latestYear - record.firstYear + 1;
    final ringWidth = (outer - inner) / years;

    // Shared scale across both modes, so the raw MODIS years look dim:
    // that is exactly the 2012 seam the harmonization fixes.
    final maxValue = record.monthly
        .map((c) => math.max(c.raw, c.harmonized))
        .reduce(math.max)
        .toDouble();
    final logMax = math.log(1 + maxValue);

    const gap = 0.012; // radians between month segments
    const sweep = 2 * math.pi / 12;
    final paint = Paint()..style = PaintingStyle.stroke;

    for (final c in record.monthly) {
      final ring = c.year - record.firstYear;
      final radius = inner + ringWidth * (ring + 0.5);
      final t = math.log(1 + c.value(harmonized: harmonized)) / logMax;
      paint
        ..color = Ember.heat(t)
        ..strokeWidth = ringWidth * 0.86;
      final start = -math.pi / 2 + (c.month - 1) * sweep + gap / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep - gap,
        false,
        paint,
      );
    }

    // Mark the VIIRS start (2012) as a thin seam circle.
    const seamYear = 2012;
    if (seamYear > record.firstYear && seamYear <= record.latestYear) {
      final r = inner + ringWidth * (seamYear - record.firstYear);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Ember.text.withValues(alpha: harmonized ? 0.15 : 0.6),
      );
    }

    // Highlight the latest month.
    final latestRadius = inner + ringWidth * (years - 0.5);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: latestRadius),
      -math.pi / 2 + (record.latestMonth - 1) * sweep,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth * 1.6
        ..color = Ember.text.withValues(alpha: 0.85)
        ..blendMode = BlendMode.overlay,
    );
  }

  @override
  bool shouldRepaint(_FireRingsPainter old) =>
      old.record != record || old.harmonized != harmonized;
}
