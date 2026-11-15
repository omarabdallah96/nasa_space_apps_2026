import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/alert_engine.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'screens/alerts_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/common.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  bool _askedInstant = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askInstantAlerts());
  }

  /// Once: offer instant (push) alerts, saying what the server keeps.
  Future<void> _askInstantAlerts() async {
    final state = AppScope.read(context);
    if (_askedInstant || !state.instantAlertsAvailable || state.instantAlerts != null) return;
    _askedInstant = true;
    final s = S.of(context);
    final on = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.bolt, color: Ember.ember, size: 32),
        title: Text(s.t('instant_alerts_ask')),
        content: Text(s.t('instant_alerts_ask_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('not_now'))),
          FilledButton(
            key: const ValueKey('instant_on'),
            onPressed: () => Navigator.pop(d, true),
            child: Text(s.t('turn_on')),
          ),
        ],
      ),
    );
    if (on != null) await state.setInstantAlerts(on);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    if (state.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Ember.ember)),
      );
    }
    if (state.error != null || state.selected == null) {
      return Scaffold(body: ErrorView(error: state.error ?? 'No regions available'));
    }

    final urgent = state.alerts.where((a) => a.level != AlertLevel.info).length;

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onOpenMap: () => setState(() => _tab = 2)),
          const CalendarScreen(),
          const MapScreen(),
          AlertsScreen(onOpen: () => setState(() => _tab = 0)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.local_fire_department_outlined),
              selectedIcon: const Icon(Icons.local_fire_department),
              label: s.t('tab_today')),
          NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: s.t('tab_history')),
          NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: s.t('tab_map')),
          NavigationDestination(
              icon: Badge(
                isLabelVisible: urgent > 0,
                label: Text('$urgent'),
                child: const Icon(Icons.notifications_none),
              ),
              selectedIcon: const Icon(Icons.notifications),
              label: s.t('tab_alerts')),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: s.t('settings')),
        ],
      ),
    );
  }
}
