import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'services/background_checks.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(createRepository(), prefs: prefs);
  await state.notifications.init();
  // Periodic alert checks while the app is closed (Android).
  try {
    await BackgroundChecks.init();
    await BackgroundChecks.setEnabled(prefs.getBool('background_checks') ?? true);
  } catch (_) {
    // Never block app start on background scheduling.
  }
  runApp(EmberAlmanacApp(state: state..init()));
}

class EmberAlmanacApp extends StatelessWidget {
  const EmberAlmanacApp({
    super.key,
    required this.state,
    this.minSplash = const Duration(milliseconds: 2200),
  });

  final AppState state;

  /// How long the animated splash stays up at least.
  final Duration minSplash;

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
          home: AppGate(minSplash: minSplash),
        ),
      ),
    );
  }
}
