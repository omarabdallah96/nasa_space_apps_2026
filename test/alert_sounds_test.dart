import 'package:flutter_test/flutter_test.dart';
import 'package:nasa_space_apps_2026/services/alert_engine.dart';
import 'package:nasa_space_apps_2026/services/alert_sounds.dart';

void main() {
  test('danger plays the siren, warning the chime, info is silent', () {
    expect(soundFor(AlertLevel.danger, groupOn: true), AlertSound.siren);
    expect(soundFor(AlertLevel.warning, groupOn: true), AlertSound.chime);
    expect(soundFor(AlertLevel.info, groupOn: true), AlertSound.silent);
  });

  test('a group turned off is silent at every level', () {
    for (final l in AlertLevel.values) {
      expect(soundFor(l, groupOn: false), AlertSound.silent);
    }
  });

  test('every alert type has a group; trends are off by default', () {
    expect(SoundGroup.of(AlertType.zoneFire), SoundGroup.nearMe);
    expect(SoundGroup.of(AlertType.nearbyHotspot), SoundGroup.nearMe);
    expect(SoundGroup.of(AlertType.groundSmoke), SoundGroup.nearMe);
    expect(SoundGroup.of(AlertType.dangerForecast), SoundGroup.forecast);
    expect(SoundGroup.of(AlertType.official), SoundGroup.official);
    expect(SoundGroup.of(AlertType.anomaly), SoundGroup.trends);
    expect(SoundGroup.trends.defaultOn, isFalse);
    expect(SoundGroup.nearMe.defaultOn, isTrue);
  });
}
