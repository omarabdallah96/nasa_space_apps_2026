import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../data/repositories/fire_repository.dart';
import '../state/app_state.dart';
import 'notification_service.dart';

const _taskName = 'ember_alert_check';
const _uniqueName = 'ember-alert-check';

/// Entry point for the background isolate. Must be top-level.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await runBackgroundCheck();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Loads the watched places, evaluates alerts and notifies new ones.
/// Runs without any UI, so the app can be closed.
Future<void> runBackgroundCheck({
  FireRepository? repository,
  NotificationService? notifications,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // pick up changes made by the foreground app
  final state = AppState(
    repository ?? createRepository(),
    prefs: prefs,
    notifications: notifications,
    reportApi: repository == null ? createReportApi() : null,
    // Knows the signed-in user's plan, so Pro zones are checked too.
    authApi: repository == null ? createAuthApi() : null,
  );
  await state.init(checkOnStart: false);
  await state.checkAlerts(notify: true, onlyNew: true);
}

/// Periodic background checks (Android WorkManager).
///
/// iOS decides by itself when background fetch runs, and needs extra
/// setup in Xcode (BGTaskScheduler), so it's Android-only for now.
abstract final class BackgroundChecks {
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const every = Duration(hours: 3);

  static Future<void> init() async {
    if (!supported) return;
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_uniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: every,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: useMockData ? NetworkType.notRequired : NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }
}
