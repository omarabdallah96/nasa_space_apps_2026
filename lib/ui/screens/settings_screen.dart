import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/strings.dart';
import '../../services/background_checks.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import 'onboarding_screen.dart';

/// Everything the user can change, in one place. Every row is a single tap:
/// switches for on/off things, chips for places, and a two-way picker for
/// language. Alerts come first because that is what people come here for.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _notificationsAllowed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may change permission in system settings and come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    if (!mounted) return;
    final ok = await AppScope.read(context).notifications.isAllowed();
    if (mounted && ok != _notificationsAllowed) {
      setState(() => _notificationsAllowed = ok);
    }
  }

  Future<void> _toggleNotifications(bool on) async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      // Apps cannot revoke their own permission; point the user to the OS.
      messenger.showSnackBar(SnackBar(content: Text(s.t('notifications_on_hint'))));
      return;
    }
    final ok = await state.notifications.requestPermission();
    if (!mounted) return;
    setState(() => _notificationsAllowed = ok);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('notifications_denied'))));
    }
  }

  void _replayIntro() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (route) => OnboardingScreen(onDone: () => Navigator.pop(route)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);

    final located = state.userPosition != null;
    final locationSub = state.locationError != null
        ? s.t(state.locationError!)
        : located
            ? (state.userRegion == null
                ? s.t('located')
                : '${s.t('located')} · ${s.region(state.userRegion!.region)}')
            : s.t('location_sub');

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // ── Alerts ──
          _Header(s.t('alerts')),
          _Group(children: [
            _SwitchRow(
              icon: Icons.notifications_active_outlined,
              title: s.t('notifications'),
              subtitle: s.t('notifications_sub'),
              value: _notificationsAllowed,
              onChanged: state.notifications.supported ? _toggleNotifications : null,
            ),
            if (BackgroundChecks.supported)
              _SwitchRow(
                icon: Icons.schedule,
                title: s.t('background_checks'),
                subtitle: s.t('background_checks_sub'),
                value: state.backgroundChecks,
                onChanged: state.setBackgroundChecks,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RowTitle(
                    icon: Icons.place_outlined,
                    title: s.t('watched_places'),
                    subtitle: s.t('watched_places_sub'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in state.regions)
                        FilterChip(
                          label: Text(s.region(r)),
                          selected: state.watchlist.contains(r.id),
                          onSelected: (_) => state.toggleWatch(r.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]),

          // ── Location ──
          _Header(s.t('location')),
          _Group(children: [
            ListTile(
              onTap: state.locating ? null : state.locateMe,
              contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
              leading: _IconBox(
                located ? Icons.my_location : Icons.location_searching,
                color: located ? Ember.calm : null,
              ),
              title: Text(s.t('use_location'), style: _titleStyle),
              subtitle: Text(
                locationSub,
                style: TextStyle(
                  color: state.locationError != null ? Ember.extreme : Ember.textMuted,
                ),
              ),
              trailing: state.locating
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember),
                    )
                  : located
                      ? Icon(Icons.refresh, color: Ember.textMuted)
                      : FilledButton.tonal(
                          onPressed: state.locateMe,
                          child: Text(s.t('allow')),
                        ),
            ),
          ]),

          // ── Appearance ──
          _Header(s.t('appearance')),
          _Group(children: [
            _SwitchRow(
              icon: state.darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              title: s.t('dark_mode'),
              value: state.darkMode,
              onChanged: state.setDarkMode,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RowTitle(icon: Icons.translate, title: s.t('language_label')),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English')),
                      ButtonSegment(value: 'ar', label: Text('العربية')),
                    ],
                    selected: {state.languageCode},
                    onSelectionChanged: (v) => state.setLanguage(v.first),
                  ),
                ],
              ),
            ),
          ]),

          // ── About ──
          _Header(s.t('about')),
          _Group(children: [
            ListTile(
              onTap: _replayIntro,
              contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
              leading: const _IconBox(Icons.slideshow_outlined),
              title: Text(s.t('replay_intro'), style: _titleStyle),
              trailing: Icon(Icons.chevron_right, color: Ember.textMuted),
            ),
            ListTile(
              contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
              leading: const _IconBox(Icons.satellite_alt_outlined),
              title: Text(s.t('data_source'), style: _titleStyle),
              subtitle: Text(
                s.t(useMockData ? 'data_source_demo' : 'data_source_sub'),
                style: TextStyle(color: Ember.textMuted),
              ),
            ),
          ]),

          const SizedBox(height: 28),
          Center(
            child: Column(children: [
              const EmberLogo(size: 36),
              const SizedBox(height: 8),
              Text(s.t('app_name'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text('${s.t('version')} 1.0.0', style: monoStyle(size: 11)),
            ]),
          ),
        ],
      ),
    );
  }
}

const _titleStyle = TextStyle(fontWeight: FontWeight.w600);

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 24, 4, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Ember.textMuted,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

/// A card holding rows separated by thin dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 68, color: Ember.outline),
            children[i],
          ],
        ]),
      );
}

/// A whole-row switch: tapping anywhere on the row flips it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
        secondary: _IconBox(icon),
        title: Text(title, style: _titleStyle),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: TextStyle(color: Ember.textMuted)),
      );
}

/// Icon + title (+ optional subtitle) for rows whose control sits below.
class _RowTitle extends StatelessWidget {
  const _RowTitle({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
        _IconBox(icon),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _titleStyle),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Ember.textMuted),
                ),
            ],
          ),
        ),
      ]);
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Ember.ember;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: c),
    );
  }
}
