import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repositories/api_fire_repository.dart';
import 'data/repositories/fire_repository.dart';
import 'data/repositories/mock_fire_repository.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

/// Flip to false once the backend serves docs/api_contract.md.
const useMockData = true;
const apiBaseUrl = 'https://example.com/ember-almanac';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final FireRepository repository =
      useMockData ? MockFireRepository() : ApiFireRepository(baseUrl: apiBaseUrl);
  final state = AppState(repository, prefs: prefs);
  await state.notifications.init();
  runApp(EmberAlmanacApp(state: state..init()));
}

class EmberAlmanacApp extends StatelessWidget {
  const EmberAlmanacApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Ember Almanac',
          debugShowCheckedModeBanner: false,
          theme: buildEmberTheme(),
          // Arabic switches the whole layout to right-to-left.
          locale: Locale(state.languageCode),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const AppShell(),
        ),
      ),
    );
  }
}
