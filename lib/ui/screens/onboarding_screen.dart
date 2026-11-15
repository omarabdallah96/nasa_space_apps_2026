import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import 'auth_screen.dart';

/// First-launch intro: the question, the harmonization idea, the mobile
/// features, language + permissions, then an optional account (guest is the default).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  /// The account page only shows when the server offers accounts.
  int get _count => AppScope.read(context).accountsAvailable ? 5 : 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _count - 1) {
      widget.onDone();
    } else {
      _pages.nextPage(
          duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final last = _page == _count - 1;
    return Scaffold(
      backgroundColor: Ember.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : widget.onDone,
                  child: Text(s.t('skip'),
                      style: TextStyle(color: Ember.textMuted)),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page(
                    art: const AnimatedEmberLogo(size: 190),
                    title: s.t('ob1_title'),
                    body: s.t('ob1_body'),
                  ),
                  _Page(
                    art: const _SeamArt(),
                    title: s.t('ob2_title'),
                    body: s.t('ob2_body'),
                  ),
                  _Page(
                    art: const _FeaturesArt(),
                    title: s.t('ob3_title'),
                    body: s.t('ob3_body'),
                  ),
                  _Page(
                    art: const _SetupArt(),
                    title: s.t('ob4_title'),
                    body: s.t('ob4_body'),
                  ),
                  if (_count == 5)
                    _Page(
                      art: const _AccountArt(),
                      title: s.t('ob5_title'),
                      body: s.t('ob5_body'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsetsDirectional.only(end: 6),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? Ember.ember : Ember.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(140, 48),
                      backgroundColor: Ember.ember,
                      foregroundColor: Ember.background,
                    ),
                    child: Text(
                        s.t(!last
                            ? 'next'
                            : _count == 5 && AppScope.of(context).isGuest
                                ? 'continue_guest'
                                : 'get_started'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.body});
  final Widget art;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 240),
                child: Center(child: art),
              ),
              const SizedBox(height: 32),
              Text(title,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Text(body,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: Ember.textMuted, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bars that flip between the raw record (jump in 2012) and the fixed one.
class _SeamArt extends StatefulWidget {
  const _SeamArt();

  @override
  State<_SeamArt> createState() => _SeamArtState();
}

class _SeamArtState extends State<_SeamArt> {
  bool _fixed = false;
  Timer? _timer;

  // Harmonized yearly values (relative). Before 2012, raw MODIS ≈ ÷3.
  static const _values = [0.55, 0.7, 0.5, 0.8, 0.6, 0.65, 0.75, 0.6, 0.85, 0.7, 0.62, 0.9];
  static const _seam = 6;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) setState(() => _fixed = !_fixed);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 260,
            height: 170,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < _values.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeInOutCubic,
                            height: 160 * (i < _seam && !_fixed ? _values[i] / 3 : _values[i]),
                            decoration: BoxDecoration(
                              color: i < _seam && !_fixed ? Ember.ash : Ember.ember,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // The seam line at "2012".
                Positioned(
                  left: 260 / _values.length * _seam - 1,
                  top: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _fixed ? 0.2 : 1,
                    duration: const Duration(milliseconds: 500),
                    child: Container(width: 2, color: Ember.text),
                  ),
                ),
                Positioned(
                  left: 260 / _values.length * _seam + 6,
                  top: 0,
                  child: Text('2012', style: monoStyle(size: 10, color: Ember.text)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            s.t(_fixed ? 'ob2_fixed' : 'ob2_raw'),
            key: ValueKey(_fixed),
            style: monoStyle(size: 12, color: _fixed ? Ember.amber : Ember.textMuted),
          ),
        ),
      ],
    );
  }
}

class _FeaturesArt extends StatelessWidget {
  const _FeaturesArt();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      (Icons.near_me, s.t('ob3_near')),
      (Icons.notifications_active_outlined, s.t('ob3_alerts')),
      (Icons.photo_camera_outlined, s.t('ob3_verify')),
      (Icons.air, s.t('ob3_weather')),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, label) in items)
          Container(
            width: 280,
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Ember.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ember.outline),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Ember.ember.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: Ember.ember),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ]),
          ),
      ],
    );
  }
}

/// Sign in / create account, or the account already signed in.
class _AccountArt extends StatelessWidget {
  const _AccountArt();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final user = state.user;
    if (user != null) {
      return SizedBox(
        width: 290,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 56, color: Ember.calm),
          const SizedBox(height: 12),
          Text('${s.t('signed_in_as')} ${user.displayName}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(user.email, style: TextStyle(color: Ember.textMuted)),
        ]),
      );
    }
    return SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.account_circle_outlined, size: 72, color: Ember.ember),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => AuthScreen.open(context, register: true),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: Icon(Icons.person_add_alt, color: Ember.ember),
            label: Text(s.t('create_account'), style: TextStyle(color: Ember.text)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => AuthScreen.open(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: Icon(Icons.login, color: Ember.ember),
            label: Text(s.t('sign_in'), style: TextStyle(color: Ember.text)),
          ),
        ],
      ),
    );
  }
}

/// Language + permission buttons.
class _SetupArt extends StatefulWidget {
  const _SetupArt();

  @override
  State<_SetupArt> createState() => _SetupArtState();
}

class _SetupArtState extends State<_SetupArt> {
  bool _notificationsAllowed = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final locationAllowed = state.userPosition != null;
    return SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {state.languageCode},
            onSelectionChanged: (v) => state.setLanguage(v.first),
          ),
          const SizedBox(height: 20),
          _PermissionButton(
            icon: Icons.my_location,
            label: s.t('allow_location'),
            allowed: locationAllowed,
            busy: state.locating,
            error: state.locationError == null ? null : s.t(state.locationError!),
            onPressed: state.locateMe,
          ),
          const SizedBox(height: 10),
          _PermissionButton(
            icon: Icons.notifications_active_outlined,
            label: s.t('allow_notifications'),
            allowed: _notificationsAllowed,
            onPressed: () async {
              final ok = await state.notifications.requestPermission();
              if (mounted) setState(() => _notificationsAllowed = ok);
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  const _PermissionButton({
    required this.icon,
    required this.label,
    required this.allowed,
    required this.onPressed,
    this.busy = false,
    this.error,
  });

  final IconData icon;
  final String label;
  final bool allowed, busy;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: allowed || busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: allowed ? Ember.calm : Ember.outline),
          ),
          icon: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember))
              : Icon(allowed ? Icons.check_circle : icon,
                  color: allowed ? Ember.calm : Ember.ember),
          label: Text(allowed ? '$label · ${s.t('allowed')}' : label,
              style: TextStyle(color: allowed ? Ember.calm : Ember.text)),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ember.extreme, fontSize: 12)),
          ),
      ],
    );
  }
}
