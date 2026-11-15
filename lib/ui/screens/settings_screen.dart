import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/strings.dart';
import '../../services/alert_sounds.dart';
import '../../services/background_checks.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_api.dart';
import '../brand/ember_logo.dart';
import 'auth_screen.dart';
import 'paywall.dart';
import 'onboarding_screen.dart';

/// Short and calm: account on top, only the alert switches people actually
/// use, and everything else (sounds, background checks, watched places,
/// sign out / delete) one tap away.
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

  Future<void> _signOut() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.t('sign_out')),
        content: Text(s.t('sign_out_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('sign_out'))),
        ],
      ),
    );
    if (ok == true && mounted) await AppScope.read(context).signOut();
  }

  Future<void> _editName() async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => _TextDialog(
        title: s.t('edit_name'),
        label: s.t('name_optional'),
        initial: state.user?.name ?? '',
        action: s.t('save'),
      ),
    );
    if (name == null) return;
    try {
      await state.updateName(name);
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_authError(s, e))));
    }
  }

  Future<void> _deleteAccount() async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final password = await showDialog<String>(
      context: context,
      builder: (d) => _TextDialog(
        title: s.t('delete_account'),
        message: s.t('delete_account_body'),
        label: s.t('password'),
        action: s.t('delete'),
        obscure: true,
        danger: true,
      ),
    );
    if (password == null || password.isEmpty) return;
    try {
      await state.deleteAccount(password);
      messenger.showSnackBar(SnackBar(content: Text(s.t('account_deleted'))));
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_authError(s, e))));
    }
  }

  static String _authError(S s, AuthException e) {
    final key = 'auth_err_${e.code}';
    final text = s.t(key);
    return text == key ? s.t('auth_err_unknown') : text;
  }

  void _replayIntro() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (route) => OnboardingScreen(onDone: () => Navigator.pop(route)),
        ),
      );

  /// Name, sign out and delete live in a sheet so they never sit next to
  /// everyday switches.
  void _openAccount() {
    final state = AppScope.read(context);
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: _Avatar(state.user!.displayName),
            title: Text(state.user!.displayName, style: _titleStyle),
            subtitle: Text(state.user!.email, style: TextStyle(color: Ember.textMuted)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const _IconBox(Icons.edit_outlined),
            title: Text(s.t('edit_name'), style: _titleStyle),
            onTap: () {
              Navigator.pop(sheet);
              _editName();
            },
          ),
          ListTile(
            leading: const _IconBox(Icons.logout),
            title: Text(s.t('sign_out'), style: _titleStyle),
            onTap: () {
              Navigator.pop(sheet);
              _signOut();
            },
          ),
          ListTile(
            leading: const _IconBox(Icons.delete_outline, color: Ember.extreme),
            title: Text(s.t('delete_account'),
                style: _titleStyle.copyWith(color: Ember.extreme)),
            onTap: () {
              Navigator.pop(sheet);
              _deleteAccount();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _openWatchedPlaces() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const _WatchedPlacesSheet(),
      );

  void _openMoreAlerts() => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const _MoreAlertsScreen()),
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

    final watched = [
      for (final r in state.regions)
        if (state.watchlist.contains(r.id)) s.region(r),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── You: account + Pro ──
          _Group(children: [
            if (state.accountsAvailable)
              if (state.isGuest)
                _NavRow(
                  key: const ValueKey('account_guest'),
                  icon: Icons.person_outline,
                  title: s.t('guest'),
                  subtitle: s.t('guest_sub'),
                  onTap: () => AuthScreen.open(context),
                  trailing: FilledButton.tonal(
                    onPressed: () => AuthScreen.open(context),
                    child: Text(s.t('sign_in')),
                  ),
                )
              else
                ListTile(
                  key: const ValueKey('account_user'),
                  onTap: _openAccount,
                  contentPadding: _rowPadding,
                  leading: _Avatar(state.user!.displayName),
                  title: Text(state.user!.displayName, style: _titleStyle),
                  subtitle: Text(state.user!.email, style: TextStyle(color: Ember.textMuted)),
                  trailing: Icon(Icons.chevron_right, color: Ember.textMuted),
                ),
            _NavRow(
              key: const ValueKey('settings_pro'),
              icon: Icons.workspace_premium,
              color: Ember.amber,
              title: s.t('pro_title'),
              subtitle: s.t(state.isPro ? 'pro_active' : 'pro_settings_sub'),
              subtitleColor: state.isPro ? Ember.calm : null,
              onTap: () => showPaywall(context),
            ),
          ]),

          // ── Alerts: the few things that matter, the rest one tap away ──
          _Header(s.t('alerts')),
          _Group(children: [
            _SwitchRow(
              icon: Icons.notifications_active_outlined,
              title: s.t('notifications'),
              subtitle: s.t('notifications_sub'),
              value: _notificationsAllowed,
              onChanged: state.notifications.supported ? _toggleNotifications : null,
            ),
            if (state.instantAlertsAvailable)
              _SwitchRow(
                key: const ValueKey('instant_alerts'),
                icon: Icons.bolt,
                title: s.t('instant_alerts'),
                subtitle: s.t('instant_alerts_short'),
                value: state.instantAlerts ?? false,
                onChanged: state.setInstantAlerts,
              ),
            _NavRow(
              key: const ValueKey('watched_places'),
              icon: Icons.place_outlined,
              title: s.t('watched_places'),
              subtitle: watched.isEmpty ? s.t('none_yet') : watched.join(', '),
              onTap: _openWatchedPlaces,
            ),
            ListTile(
              onTap: state.locating ? null : state.locateMe,
              contentPadding: _rowPadding,
              leading: _IconBox(
                located ? Icons.my_location : Icons.location_searching,
                color: located ? Ember.calm : null,
              ),
              title: Text(s.t('location'), style: _titleStyle),
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
            if (state.notifications.supported || BackgroundChecks.supported)
              _NavRow(
                key: const ValueKey('more_alerts'),
                icon: Icons.tune,
                title: s.t('more_alert_options'),
                subtitle: s.t('more_alert_options_sub'),
                onTap: _openMoreAlerts,
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
                    showSelectedIcon: false,
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
            _NavRow(
              icon: Icons.slideshow_outlined,
              title: s.t('replay_intro'),
              onTap: _replayIntro,
            ),
            ListTile(
              contentPadding: _rowPadding,
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

/// Sounds and background checks: useful, but rarely changed, so they live
/// one level down.
class _MoreAlertsScreen extends StatelessWidget {
  const _MoreAlertsScreen();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('more_alert_options'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (BackgroundChecks.supported)
            _Group(children: [
              _SwitchRow(
                icon: Icons.schedule,
                title: s.t('background_checks'),
                subtitle: s.t('background_checks_sub'),
                value: state.backgroundChecks,
                onChanged: state.setBackgroundChecks,
              ),
            ]),
          if (state.notifications.supported) ...[
            _Header(s.t('sounds')),
            _Group(children: [
              for (final g in SoundGroup.values)
                _SwitchRow(
                  key: ValueKey('sound_${g.name}'),
                  icon: switch (g) {
                    SoundGroup.nearMe => Icons.local_fire_department_outlined,
                    SoundGroup.forecast => Icons.thermostat,
                    SoundGroup.official => Icons.campaign_outlined,
                    SoundGroup.trends => Icons.show_chart,
                  },
                  title: s.t('sound_${g.name}'),
                  subtitle: s.t('sound_${g.name}_sub'),
                  value: state.soundOn(g),
                  onChanged: (on) => state.setSoundOn(g, on),
                ),
            ]),
          ],
          if (state.instantAlertsAvailable)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 0),
              child: Text(
                '${s.t('instant_alerts')}: ${s.t('instant_alerts_sub')}',
                style: TextStyle(color: Ember.textMuted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pick watched places with chips, in a sheet instead of inline.
class _WatchedPlacesSheet extends StatelessWidget {
  const _WatchedPlacesSheet();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.t('watched_places'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(s.t('watched_places_sub'), style: TextStyle(color: Ember.textMuted)),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
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
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('done')),
            ),
          ],
        ),
      ),
    );
  }
}

const _rowPadding = EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6);

/// A row that opens something: icon, title, optional subtitle, chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.subtitleColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color, subtitleColor;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: _rowPadding,
        leading: _IconBox(icon, color: color),
        title: Text(title, style: _titleStyle),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtitleColor ?? Ember.textMuted),
              ),
        trailing: trailing ?? Icon(Icons.chevron_right, color: Ember.textMuted),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 18,
        backgroundColor: Ember.ember.withValues(alpha: 0.18),
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: const TextStyle(color: Ember.ember, fontWeight: FontWeight.w700),
        ),
      );
}

const _titleStyle = TextStyle(fontWeight: FontWeight.w600);

/// A dialog with one text field; pops with the text, or null when cancelled.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.action,
    this.message,
    this.initial = '',
    this.obscure = false,
    this.danger = false,
  });

  final String title, label, action, initial;
  final String? message;
  final bool obscure, danger;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _text,
            autofocus: true,
            obscureText: widget.obscure,
            maxLength: widget.obscure ? null : 60,
            decoration: InputDecoration(labelText: widget.label),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
        FilledButton(
          style: widget.danger
              ? FilledButton.styleFrom(backgroundColor: Ember.extreme, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

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
    super.key,
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

/// Icon + title for rows whose control sits below.
class _RowTitle extends StatelessWidget {
  const _RowTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        _IconBox(icon),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: _titleStyle)),
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
