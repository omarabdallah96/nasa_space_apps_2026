import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/alert_engine.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'screens/alerts_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'widgets/common.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

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
          const HomeScreen(),
          const CalendarScreen(),
          const MapScreen(),
          AlertsScreen(onOpen: () => setState(() => _tab = 0)),
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
              label: s.t('tab_calendar')),
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
        ],
      ),
    );
  }
}
