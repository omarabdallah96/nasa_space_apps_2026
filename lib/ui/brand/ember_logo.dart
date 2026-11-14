import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The Firesight mark: Fire Rings (one ring per year, 12 month segments,
/// glowing in fire season) around a flame.
///
/// [progress] animates the mark in: rings draw segment by segment from the
/// inside out, then the flame grows. 1.0 = the finished logo.
class EmberLogoPainter extends CustomPainter {
  const EmberLogoPainter({
    this.progress = 1,
    this.background = false,
    this.scale = 1,
    this.cornerRadius = 0.22,
    this.monochrome = false,
  });

  final double progress;

  /// Paint the dark rounded background (for the launcher icon).
  final bool background;

  /// Logo diameter as a fraction of the canvas (for adaptive icon safe zones).
  final double scale;

  /// Background corner radius as a fraction of the size (0 = square).
  final double cornerRadius;

  /// White silhouette (Android notification icon).
  final bool monochrome;

  /// Fire intensity per ring (inner → outer) per month (Jan → Dec).
  /// Hand-tuned to look like a real fire season: quiet winter, small spring
  /// burns, a big late-summer/autumn peak, varying by year.
  static const _intensity = [
    [0.05, 0.05, 0.25, 0.30, 0.10, 0.20, 0.45, 0.60, 0.55, 0.40, 0.10, 0.05],
    [0.05, 0.10, 0.30, 0.25, 0.15, 0.30, 0.60, 0.80, 0.70, 0.50, 0.15, 0.05],
    [0.05, 0.05, 0.20, 0.35, 0.15, 0.35, 0.70, 0.75, 0.90, 1.00, 0.20, 0.05],
    [0.10, 0.05, 0.30, 0.30, 0.20, 0.40, 0.80, 0.95, 0.85, 0.60, 0.15, 0.10],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);

    if (background) {
      final bg = RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(s * cornerRadius),
      );
      canvas.drawRRect(
        bg,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF2A1A12), Ember.night],
            radius: 0.75,
          ).createShader(Offset.zero & size),
      );
    }

    if (monochrome) canvas.saveLayer(Offset.zero & size, Paint());
    final u = s * scale / 100; // logo units: the mark spans 100u
    final rings = _intensity.length;
    const sweep = 2 * math.pi / 12;
    const gap = 0.10;

    // Rings: 48 segments drawn in order, inside out.
    final ringProgress = (progress / 0.75).clamp(0.0, 1.0);
    final total = rings * 12;
    final shown = ringProgress * total;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    for (var r = 0; r < rings; r++) {
      final radius = (24 + r * 7.5) * u;
      paint.strokeWidth = 5.6 * u;
      for (var m = 0; m < 12; m++) {
        final index = r * 12 + m;
        final local = (shown - index).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final t = _intensity[r][m];
        paint.color = monochrome
            ? Colors.white.withValues(alpha: (0.35 + t * 0.65) * local)
            : Ember.heat(0.12 + t * 0.88).withValues(alpha: local);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          -math.pi / 2 + m * sweep + gap / 2,
          (sweep - gap) * local,
          false,
          paint,
        );
      }
    }

    // Flame: grows in during the last quarter of the animation.
    final flame = Curves.easeOutBack.transform(
      ((progress - 0.6) / 0.4).clamp(0.0, 1.0),
    );
    if (flame <= 0) {
      if (monochrome) canvas.restore();
      return;
    }
    canvas.save();
    canvas.translate(c.dx, c.dy + 1.5 * u);
    canvas.scale(u * flame);

    // Glow.
    if (!monochrome) {
      canvas.drawCircle(
        const Offset(0, 2),
        15,
        Paint()
          ..color = Ember.ember.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    final outer = Path()
      ..moveTo(0, -17)
      ..cubicTo(3, -10, 11, -6, 11, 4)
      ..cubicTo(11, 11, 6, 15, 0, 15)
      ..cubicTo(-6, 15, -11, 11, -11, 4)
      ..cubicTo(-11, -2, -7, -4, -5, -10)
      ..cubicTo(-3, -6, -1, -5, -0.5, -7)
      ..cubicTo(-1, -11, -1, -14, 0, -17)
      ..close();
    canvas.drawPath(
      outer,
      monochrome
          ? (Paint()..color = Colors.white)
          : (Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ember.amber, Ember.ember, Color(0xFFC2410C)],
              ).createShader(const Rect.fromLTRB(-11, -17, 11, 15))),
    );

    final inner = Path()
      ..moveTo(0, -3)
      ..cubicTo(2, 1, 5.5, 3, 5.5, 8)
      ..cubicTo(5.5, 11.5, 3, 13, 0, 13)
      ..cubicTo(-3, 13, -5.5, 11.5, -5.5, 8)
      ..cubicTo(-5.5, 4, -1.5, 2, 0, -3)
      ..close();
    canvas.drawPath(
      inner,
      monochrome
          ? (Paint()..blendMode = BlendMode.clear)
          : (Paint()..color = const Color(0xFFFFE8A8)),
    );
    canvas.restore();
    if (monochrome) canvas.restore();
  }

  @override
  bool shouldRepaint(EmberLogoPainter old) =>
      old.progress != progress ||
      old.background != background ||
      old.scale != scale ||
      old.cornerRadius != cornerRadius ||
      old.monochrome != monochrome;
}

/// The static logo as a widget.
class EmberLogo extends StatelessWidget {
  const EmberLogo({super.key, this.size = 96, this.background = false});

  final double size;
  final bool background;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: EmberLogoPainter(background: background)),
  );
}

/// The logo drawing itself in: rings segment by segment, then the flame.
class AnimatedEmberLogo extends StatefulWidget {
  const AnimatedEmberLogo({
    super.key,
    this.size = 160,
    this.duration = const Duration(milliseconds: 1400),
  });

  final double size;
  final Duration duration;

  @override
  State<AnimatedEmberLogo> createState() => _AnimatedEmberLogoState();
}

class _AnimatedEmberLogoState extends State<AnimatedEmberLogo>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration)
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: EmberLogoPainter(
          progress: Curves.easeInOut.transform(_c.value),
        ),
      ),
    ),
  );
}
