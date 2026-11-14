import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/strings.dart';
import '../../services/background_checks.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../brand/ember_logo.dart';
import '../widgets/common.dart';
import 'onboarding_screen.dart';

/// Everything the user can change, in one place: look, language,
/// notifications, location, and about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _notificationsAllowed;

  Future<void> _askNotifications() async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Appearance ──
          _GroupLabel(s.t('appearance')),
          _Group(children: [
            _ChoiceRow(
              icon: Icons.contrast,
              title: s.t('theme'),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text(s.t('dark')),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.light_mode_outlined, size: 18),
                    label: Text(s.t('light')),
                  ),
                ],
                selected: {state.darkMode},
                onSelectionChanged: (v) => state.setDarkMode(v.first),
              ),
            ),
            _ChoiceRow(
              icon: Icons.translate,
              title: s.t('language_label'),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                ],
                selected: {state.languageCode},
                onSelectionChanged: (v) => state.setLanguage(v.first),
              ),
            ),
          ]),

          // ── Alerts ──
          _GroupLabel(s.t('alerts')),
          _Group(children: [
            _Tile(
              icon: Icons.notifications_active_outlined,
              title: s.t('notifications'),
              subtitle: s.t('notifications_sub'),
              trailing: _notificationsAllowed == true
                  ? _AllowedBadge(s.t('allowed'))
                  : TextButton(
                      onPressed: state.notifications.supported ? _askNotifications : null,
                      child: Text(s.t('allow')),
                    ),
            ),
            if (BackgroundChecks.supported)
              _Tile(
                icon: Icons.schedule,
                title: s.t('background_checks'),
                subtitle: s.t('background_checks_sub'),
                trailing: Switch(
                  value: state.backgroundChecks,
                  onChanged: state.setBackgroundChecks,
                ),
                onTap: () => state.setBackgroundChecks(!state.backgroundChecks),
              ),
            _Tile(
              icon: Icons.place_outlined,
              title: s.t('watched_places'),
              subtitle: state.regions
                  .where((r) => state.watchlist.contains(r.id))
                  .map(s.region)
                  .join(' · '),
              trailing: Text('${state.watchlist.length}', style: monoStyle(size: 14)),
            ),
          ]),

          // ── Location ──
          _GroupLabel(s.t('location')),
          _Group(children: [
            _Tile(
              icon: located ? Icons.my_location : Icons.location_searching,
              iconColor: located ? Ember.calm : null,
              title: s.t('use_location'),
              subtitle: locationSub,
              subtitleColor: state.locationError != null ? Ember.extreme : null,
              trailing: state.locating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Ember.ember),
                    )
                  : TextButton(
                      onPressed: state.locateMe,
                      child: Text(s.t(located ? 'refresh' : 'allow')),
                    ),
            ),
          ]),

          // ── About ──
          _GroupLabel(s.t('about')),
          _Group(children: [
            _Tile(
              icon: Icons.slideshow_outlined,
              title: s.t('replay_intro'),
              trailing: Icon(Icons.chevron_right, color: Ember.textMuted),
              onTap: _replayIntro,
            ),
            _Tile(
              icon: Icons.satellite_alt_outlined,
              title: s.t('data_source'),
              subtitle: s.t(useMockData ? 'data_source_demo' : 'data_source_sub'),
            ),
          ]),

          const SizedBox(height: 28),
          Center(
            child: Column(children: [
              const EmberLogo(size: 40),
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Ember.amber,
                letterSpacing: 1.1,
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
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: Ember.outline),
            children[i],
          ],
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.subtitleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor, subtitleColor;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
        leading: _IconBox(icon, color: iconColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: subtitleColor ?? Ember.textMuted)),
        trailing: trailing,
      );
}

/// A row with a title on top and a full-width control below it.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _IconBox(icon),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
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

class _AllowedBadge extends StatelessWidget {
  const _AllowedBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: StatusPill(label: label, color: Ember.calm),
      );
}
