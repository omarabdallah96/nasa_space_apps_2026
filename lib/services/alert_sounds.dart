import 'alert_engine.dart';

/// What a notification sounds like. Each one is its own Android channel,
/// because Android fixes a channel's sound when the channel is created.
enum AlertSound {
  /// Loud siren on the alarm stream: fire close by, extreme danger.
  siren,

  /// Short two-note chime.
  chime,

  /// Shown in the tray without a sound.
  silent,
}

/// Alert types grouped the way the Settings screen offers them.
enum SoundGroup {
  /// Hotspots near a watched place, fire inside a zone, smoke reports.
  nearMe(defaultOn: true),

  /// High, very high or extreme fire danger in the coming days.
  forecast(defaultOn: true),

  /// Alerts sent by the Firesight team or Civil Defence.
  official(defaultOn: true),

  /// Season trends: above normal, season starting, detection counts.
  trends(defaultOn: false);

  const SoundGroup({required this.defaultOn});
  final bool defaultOn;

  static SoundGroup of(AlertType type) => switch (type) {
        AlertType.nearbyHotspot || AlertType.zoneFire || AlertType.groundSmoke => nearMe,
        AlertType.dangerForecast => forecast,
        AlertType.official => official,
        AlertType.anomaly || AlertType.seasonSoon || AlertType.inSeason || AlertType.detections => trends,
      };
}

/// Danger plays the siren, warning the chime, info stays silent. A group the
/// person turned off in Settings is always silent.
AlertSound soundFor(AlertLevel level, {required bool groupOn}) {
  if (!groupOn) return AlertSound.silent;
  return switch (level) {
    AlertLevel.danger => AlertSound.siren,
    AlertLevel.warning => AlertSound.chime,
    AlertLevel.info => AlertSound.silent,
  };
}
