import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';

/// Live compass: point the top of the phone at the smoke and lock the
/// direction. The locked bearing is what triangulation uses.
class CompassAim extends StatefulWidget {
  const CompassAim({super.key, required this.locked, required this.onChanged});

  /// The locked bearing, or null while aiming.
  final double? locked;
  final ValueChanged<double?> onChanged;

  @override
  State<CompassAim> createState() => _CompassAimState();
}

class _CompassAimState extends State<CompassAim> {
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;
  bool _available = true;

  @override
  void initState() {
    super.initState();
    final events = kIsWeb ? null : FlutterCompass.events;
    if (events == null) {
      _available = false;
    } else {
      _sub = events.listen(
        (e) {
          if (e.heading == null) return;
          setState(() => _heading = (e.heading! + 360) % 360);
        },
        onError: (_) => setState(() => _available = false),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final locked = widget.locked;
    final shown = locked ?? _heading;

    if (!_available) {
      return Text(s.t('no_compass'), style: monoStyle());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('compass_hint'),
            style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox.square(
              dimension: 96,
              child: CustomPaint(
                painter: _DialPainter(heading: shown, locked: locked != null),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('direction'), style: monoStyle(size: 11)),
                  Text(
                    shown == null
                        ? '—'
                        : '${shown.round()}° ${s.compass(((shown + 22.5) ~/ 45) % 8)}',
                    style: monoStyle(
                        size: 18, color: locked != null ? Ember.calm : Ember.text),
                  ),
                  if (locked != null)
                    Text('✓ ${s.t('locked')}',
                        style: monoStyle(size: 11, color: Ember.calm)),
                  const SizedBox(height: 8),
                  locked == null
                      ? FilledButton.tonalIcon(
                          onPressed:
                              _heading == null ? null : () => widget.onChanged(_heading),
                          icon: const Icon(Icons.gps_fixed, size: 18),
                          label: Text(s.t('lock_direction')),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => widget.onChanged(null),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(s.t('re_aim')),
                        ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compass card: the dial turns so the arrow (top of phone) shows the
/// direction being pointed at.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.locked});
  final double? heading;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = Ember.surfaceHigh);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = locked ? Ember.calm : Ember.outline);

    // Dial rotates opposite to the heading, so N stays pointing north.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-(heading ?? 0) * math.pi / 180);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final major = i.isEven;
      final p1 = Offset(math.sin(a), -math.cos(a)) * (r - (major ? 10 : 6));
      final p2 = Offset(math.sin(a), -math.cos(a)) * (r - 2);
      canvas.drawLine(p1, p2,
          Paint()
            ..color = i == 0 ? Ember.extreme : Ember.textMuted
            ..strokeWidth = major ? 2 : 1);
    }
    final tp = TextPainter(
      text: const TextSpan(
          text: 'N',
          style: TextStyle(color: Ember.extreme, fontSize: 11, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -r + 12));
    canvas.restore();

    // Arrow = where the top of the phone points.
    final arrow = Path()
      ..moveTo(c.dx, c.dy - r + 18)
      ..lineTo(c.dx + 9, c.dy + 10)
      ..lineTo(c.dx, c.dy + 4)
      ..lineTo(c.dx - 9, c.dy + 10)
      ..close();
    canvas.drawPath(arrow, Paint()..color = locked ? Ember.calm : Ember.ember);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.heading != heading || old.locked != locked;
}
