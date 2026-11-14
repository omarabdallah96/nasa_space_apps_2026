import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import '../shell.dart';
import 'onboarding_screen.dart';

/// The animated splash. It picks up where the native splash (same logo on the
/// same background) leaves off, so the hand-over is seamless.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Ember.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedEmberLogo(size: 168),
            const SizedBox(height: 28),
            _FadeUp(
              delay: const Duration(milliseconds: 700),
              child: Text(s.t('app_name'),
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            _FadeUp(
              delay: const Duration(milliseconds: 950),
              child: Text(s.t('tagline'),
                  style: text.titleMedium?.copyWith(color: Ember.amber)),
            ),
            const SizedBox(height: 6),
            _FadeUp(
              delay: const Duration(milliseconds: 1150),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(s.t('splash_sub'),
                    textAlign: TextAlign.center,
                    style: monoStyle(size: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadeUp extends StatefulWidget {
  const _FadeUp({required this.child, required this.delay});
  final Widget child;
  final Duration delay;

  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
              .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
          child: widget.child,
        ),
      );
}

/// Splash → onboarding (first launch) → app.
///
/// The splash stays up for at least [minSplash] so the logo animation can
/// finish, and until the data has loaded.
class AppGate extends StatefulWidget {
  const AppGate({super.key, this.minSplash = const Duration(milliseconds: 2200)});

  final Duration minSplash;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.minSplash, () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final Widget child;
    if (!_minElapsed || state.loading) {
      child = const SplashScreen(key: ValueKey('splash'));
    } else if (!state.onboarded) {
      child = OnboardingScreen(
        key: const ValueKey('onboarding'),
        onDone: state.completeOnboarding,
      );
    } else {
      child = const AppShell(key: ValueKey('app'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      child: child,
    );
  }
}
