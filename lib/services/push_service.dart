import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key of the zone alerts already shown by push, so the alert check on the
/// phone does not notify them a second time.
const pushedBroadcastsKey = 'pushed_broadcasts';

Future<void> rememberPushed(SharedPreferences prefs, String? broadcastId) async {
  if (broadcastId == null) return;
  final seen = (prefs.getStringList(pushedBroadcastsKey) ?? const []).toList();
  if (seen.contains(broadcastId)) return;
  seen.add(broadcastId);
  // Keep the newest 200.
  await prefs.setStringList(pushedBroadcastsKey, seen.length > 200 ? seen.sublist(seen.length - 200) : seen);
}

/// Push while the app is in the background or closed: the system already
/// shows the notification; only remember it.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await rememberPushed(await SharedPreferences.getInstance(), message.data['broadcastId']);
  } catch (_) {}
}

/// Firebase Cloud Messaging. Off (and harmless) until the Firebase config
/// files are in the app: android/app/google-services.json and
/// ios/Runner/GoogleService-Info.plist.
class PushService {
  bool _available = false;
  bool get available => _available;

  /// Starts Firebase. Returns false when it is not set up on this build.
  Future<bool> init() async {
    if (kIsWeb || _available) return _available;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      _available = true;
    } catch (e) {
      debugPrint('push: Firebase is not configured ($e)');
    }
    return _available;
  }

  /// The FCM token, asking for notification permission first. Null when push
  /// is unavailable or not allowed.
  Future<String?> token() async {
    if (!_available) return null;
    try {
      final m = FirebaseMessaging.instance;
      final settings = await m.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      // The registration token the server sends to (FCM HTTP v1 `message.token`).
      // ignore: deprecated_member_use
      return await m.getToken();
    } catch (e) {
      debugPrint('push: no token ($e)');
      return null;
    }
  }

  Stream<String> get onTokenRefresh =>
      // ignore: deprecated_member_use
      _available ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  /// Messages that arrive while the app is open (the system does not show them).
  Stream<RemoteMessage> get onForeground =>
      _available ? FirebaseMessaging.onMessage : const Stream.empty();

  Future<void> deleteToken() async {
    if (!_available) return;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
