import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/watchlist_screen.dart';
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
    if (state.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Ember.ember)),
      );
    }
    if (state.error != null || state.selected == null) {
      return Scaffold(body: ErrorView(error: state.error ?? 'No regions available'));
    }

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const HomeScreen(),
          const CalendarScreen(),
          const MapScreen(),
          WatchlistScreen(onOpen: () => setState(() => _tab = 0)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.local_fire_department_outlined),
              selectedIcon: Icon(Icons.local_fire_department),
              label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications),
              label: 'Watchlist'),
        ],
      ),
    );
  }
}
