import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_sounds.dart';

export 'alert_sounds.dart' show AlertSound;

/// Local notifications. For the demo, alerts are computed on the phone and
/// shown locally; later the same alerts can come from a server via FCM.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!supported || _ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_ember'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    // Create the channels now, so push notifications (which name them) use
    // them even before the app has shown a local notification.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // The first channels used the default sound, which can't be changed.
      for (final old in const ['fire_alerts', 'fire_urgent']) {
        await android.deleteNotificationChannel(channelId: old);
      }
      for (final c in AlertSound.values) {
        await android.createNotificationChannel(_channel(c));
      }
    }
    _ready = true;
  }

  /// Whether the OS currently lets the app show notifications, without asking.
  Future<bool> isAllowed() async {
    if (!supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.areNotificationsEnabled() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return (await ios?.checkPermissions())?.isEnabled ?? false;
  }

  /// Asks the OS for permission (Android 13+, iOS). Returns false if denied.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    AlertSound sound = AlertSound.chime,
  }) async {
    if (!supported) return;
    await init();
    final c = _channel(sound);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          c.id,
          c.name,
          channelDescription: c.description,
          importance: c.importance,
          priority: switch (sound) {
            AlertSound.siren => Priority.max,
            AlertSound.chime => Priority.high,
            AlertSound.silent => Priority.low,
          },
          playSound: c.playSound,
          sound: c.sound,
          audioAttributesUsage: c.audioAttributesUsage,
          category: sound == AlertSound.siren ? AndroidNotificationCategory.alarm : null,
          styleInformation: BigTextStyleInformation(body),
          color: const Color(0xFFFF6B2C),
        ),
        iOS: DarwinNotificationDetails(
          presentSound: sound != AlertSound.silent,
          sound: switch (sound) {
            AlertSound.siren => 'fire_siren.wav',
            AlertSound.chime => 'fire_chime.wav',
            AlertSound.silent => null,
          },
          interruptionLevel: switch (sound) {
            AlertSound.siren => InterruptionLevel.timeSensitive,
            AlertSound.chime => InterruptionLevel.active,
            AlertSound.silent => InterruptionLevel.passive,
          },
        ),
      ),
    );
  }

  /// One Android channel per sound. The ids are what the server names in
  /// `android.notification.channel_id`.
  static AndroidNotificationChannel _channel(AlertSound sound) => switch (sound) {
        AlertSound.siren => const AndroidNotificationChannel(
            'fire_danger',
            'Fire danger (siren)',
            description: 'Fire close to you or extreme danger. Plays a siren, even on vibrate.',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('fire_siren'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        AlertSound.chime => const AndroidNotificationChannel(
            'fire_warning',
            'Fire warnings (chime)',
            description: 'Fire activity and danger warnings for your watched places',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('fire_chime'),
          ),
        AlertSound.silent => const AndroidNotificationChannel(
            'fire_info',
            'Fire updates (silent)',
            description: 'Season trends and updates, without a sound',
            importance: Importance.low,
            playSound: false,
          ),
      };
}
