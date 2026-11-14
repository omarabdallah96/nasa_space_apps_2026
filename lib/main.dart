import 'package:flutter/material.dart';

import 'data/repositories/api_fire_repository.dart';
import 'data/repositories/fire_repository.dart';
import 'data/repositories/mock_fire_repository.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

/// Flip to false once the backend serves docs/api_contract.md.
const useMockData = true;
const apiBaseUrl = 'https://example.com/ember-almanac';

void main() {
  final FireRepository repository =
      useMockData ? MockFireRepository() : ApiFireRepository(baseUrl: apiBaseUrl);
  runApp(EmberAlmanacApp(state: AppState(repository)..init()));
}

class EmberAlmanacApp extends StatelessWidget {
  const EmberAlmanacApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Ember Almanac',
        debugShowCheckedModeBanner: false,
        theme: buildEmberTheme(),
        home: const AppShell(),
      ),
    );
  }
}
