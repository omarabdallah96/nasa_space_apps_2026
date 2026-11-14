import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/region.dart';
import '../data/repositories/fire_repository.dart';
import '../l10n/strings.dart';
import '../services/alert_engine.dart';
import '../services/background_checks.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/report_api.dart';
import '../services/report_store.dart';
import '../services/triangulation.dart';
import '../services/weather_service.dart';

/// App-wide state. Kept dependency-free on purpose (ChangeNotifier only).
class AppState extends ChangeNotifier {
  AppState(
    this.repository, {
    required SharedPreferences prefs,
    this.location = const LocationService(),
    NotificationService? notifications,
    WeatherService? weather,
    this.alertEngine = const AlertEngine(),
    this.reportApi,
  })  : _prefs = prefs,
        notifications = notifications ?? NotificationService(),
        weather = weather ?? WeatherService(),
        reportStore = ReportStore(prefs);

  final FireRepository repository;
  final SharedPreferences _prefs;
  final LocationService location;
  final NotificationService notifications;
  final WeatherService weather;
  final AlertEngine alertEngine;
  final ReportStore reportStore;

  /// Shares reports through the backend; null keeps them on this phone only.
  final ReportApi? reportApi;

  List<Region> regions = const [];
  Region? selected;
  Set<String> watchlist = {'lebanon'};
  Object? error;
  bool loading = true;

  /// 'en' or 'ar'.
  String languageCode = 'en';

  /// Dark (default) or light colors.
  bool darkMode = true;

  /// False until the user finishes the intro once.
  bool onboarded = false;

  // Near me.
  LatLng? userPosition;

  /// Last GPS fix, saved so background checks know where the user is.
  LatLng? lastKnownPosition;
  RegionMatch? userRegion;
  bool locating = false;
  String? locationError; // l10n key

  // Alerts.
  List<FireAlert> alerts = const [];
  bool checkingAlerts = false;

  // Field reports.
  List<FieldReport> reports = const [];

  /// Recent reports other people sent, from the backend.
  List<FieldReport> sharedReports = const [];

  /// Fires located by crossing the compass lines of smoke reports.
  List<SmokeEstimate> smokeEstimates = const [];

  /// Periodic checks while the app is closed (Android).
  bool backgroundChecks = true;

  static const _kWatch = 'watchlist',
      _kLang = 'language',
      _kDark = 'dark_mode',
      _kNotified = 'notified_alerts',
      _kOnboarded = 'onboarded',
      _kBackground = 'background_checks',
      _kLastLat = 'last_lat',
      _kLastLon = 'last_lon',
      _kDeviceId = 'device_id';

  /// Random id for this install, so the backend can tell a retry from a new
  /// report. Not tied to the person or the hardware.
  String get _deviceId {
    var id = _prefs.getString(_kDeviceId);
    if (id == null) {
      final r = math.Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  /// Everything triangulation can use: this phone's reports and everyone else's.
  List<FieldReport> get _allReports {
    final mine = reports.map((r) => r.remoteId).whereType<String>().toSet();
    return [...reports, ...sharedReports.where((r) => !mine.contains(r.remoteId))];
  }

  /// Sends reports not uploaded yet, then downloads recent ones from others.
  /// Failures are ignored: the next check tries again.
  Future<void> syncReports() async {
    final api = reportApi;
    if (api == null) return;
    final sent = <String, FieldReport>{};
    for (final r in reports.where((r) => !r.uploaded).toList()) {
      try {
        final res = await api.upload(r, _deviceId);
        sent[r.id] = r.withRemote(res.id, res.deleteToken);
      } catch (_) {
        // Offline or rejected: stays queued.
      }
    }
    if (sent.isNotEmpty) {
      // Map over the current list: reports may have been added or deleted meanwhile.
      reports = [for (final r in reports) sent[r.id] ?? r];
      await reportStore.save(reports);
    }
    final ids = {...watchlist, ?userRegion?.region.id};
    if (ids.isEmpty) return;
    try {
      sharedReports = await api.nearby(
          ids, DateTime.now().subtract(const Duration(hours: 24)));
    } catch (_) {
      return;
    }
    smokeEstimates = triangulate(_allReports);
    notifyListeners();
  }

  Future<void> init({bool checkOnStart = true}) async {
    watchlist = (_prefs.getStringList(_kWatch) ?? ['lebanon']).toSet();
    languageCode = _prefs.getString(_kLang) ?? 'en';
    darkMode = _prefs.getBool(_kDark) ?? true;
    onboarded = _prefs.getBool(_kOnboarded) ?? false;
    reports = reportStore.load();
    smokeEstimates = triangulate(reports);
    backgroundChecks = _prefs.getBool(_kBackground) ?? true;
    final lat = _prefs.getDouble(_kLastLat), lon = _prefs.getDouble(_kLastLon);
    if (lat != null && lon != null) lastKnownPosition = LatLng(lat, lon);
    try {
      regions = await repository.getRegions();
      selected = regions.firstWhere(
        (r) => r.id == 'lebanon',
        orElse: () => regions.first,
      );
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
    if (error == null && checkOnStart) {
      // Background check on launch: notify only alerts not seen before.
      checkAlerts(notify: true, onlyNew: true);
    }
  }

  void select(Region region) {
    if (selected?.id == region.id) return;
    selected = region;
    notifyListeners();
  }

  void toggleWatch(String regionId) {
    watchlist.contains(regionId)
        ? watchlist.remove(regionId)
        : watchlist.add(regionId);
    _prefs.setStringList(_kWatch, watchlist.toList());
    notifyListeners();
    checkAlerts();
  }

  void completeOnboarding() {
    onboarded = true;
    _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  void setLanguage(String code) {
    languageCode = code;
    _prefs.setString(_kLang, code);
    notifyListeners();
  }

  void setDarkMode(bool dark) {
    if (darkMode == dark) return;
    darkMode = dark;
    _prefs.setBool(_kDark, dark);
    notifyListeners();
  }

  /// Finds the user, switches to their region and refreshes alerts.
  Future<void> locateMe() async {
    locating = true;
    locationError = null;
    notifyListeners();
    try {
      userPosition = await location.currentPosition();
      lastKnownPosition = userPosition;
      _prefs.setDouble(_kLastLat, userPosition!.latitude);
      _prefs.setDouble(_kLastLon, userPosition!.longitude);
      userRegion = matchRegion(regions, userPosition!);
      if (userRegion != null) selected = userRegion!.region;
    } on LocationException catch (e) {
      locationError = e.messageKey;
    } catch (_) {
      locationError = 'loc_failed';
    }
    locating = false;
    notifyListeners();
    if (userPosition != null) checkAlerts();
  }

  /// Evaluates alerts for every watched region (plus the user's region).
  Future<void> checkAlerts({bool notify = false, bool onlyNew = false}) async {
    checkingAlerts = true;
    notifyListeners();
    await syncReports();
    final ids = {...watchlist, ?userRegion?.region.id};
    final found = <FireAlert>[];
    for (final r in regions.where((r) => ids.contains(r.id))) {
      try {
        final record = await repository.getRecord(r.id);
        final spots = await repository.getRecentHotspots(r.id);
        found.addAll(alertEngine.evaluate(
          region: r,
          record: record,
          hotspots: spots,
          now: DateTime.now(),
          user: userPosition ?? lastKnownPosition,
        ));
      } catch (_) {
        // One region failing should not hide the others.
      }
    }
    found.addAll(_smokeAlerts(ids));
    found.sort((a, b) => b.level.index.compareTo(a.level.index));
    alerts = found;
    checkingAlerts = false;
    notifyListeners();
    if (notify) await _notify(found, onlyNew: onlyNew);
  }

  /// Fires located from ground reports, near the user or in a watched place.
  List<FireAlert> _smokeAlerts(Set<String> watchedIds) {
    final me = userPosition ?? lastKnownPosition;
    final out = <FireAlert>[];
    for (final e in smokeEstimates) {
      final match = matchRegion(regions, e.center);
      if (match == null) continue;
      final d = me == null ? null : distanceKm(me, e.center);
      final near = d != null && d <= alertEngine.nearbyKm;
      if (!near && !(match.inside && watchedIds.contains(match.region.id))) continue;
      out.add(FireAlert(
        type: AlertType.groundSmoke,
        level: near ? AlertLevel.danger : AlertLevel.warning,
        region: match.region,
        count: e.reports.length,
        distanceKm: d,
        compass: me == null ? null : compassIndex(me, e.center),
        estimateKey: '${e.center.latitude.toStringAsFixed(2)},${e.center.longitude.toStringAsFixed(2)}',
      ));
    }
    return out;
  }

  Future<void> setBackgroundChecks(bool enabled) async {
    backgroundChecks = enabled;
    notifyListeners();
    await _prefs.setBool(_kBackground, enabled);
    await BackgroundChecks.setEnabled(enabled);
  }

  Future<void> _notify(List<FireAlert> list, {required bool onlyNew}) async {
    final seen = (_prefs.getStringList(_kNotified) ?? const []).toSet();
    final toSend = onlyNew ? list.where((a) => !seen.contains(a.id)).toList() : list;
    if (toSend.isEmpty) return;
    final s = S(languageCode == 'ar');
    for (final a in toSend.where((a) => a.level != AlertLevel.info || !onlyNew)) {
      await notifications.show(
        id: a.id.hashCode & 0x7fffffff,
        title: s.alertTitle(a),
        body: s.alertBody(a),
        urgent: a.level == AlertLevel.danger,
      );
    }
    if (toSend.any((a) => a.level == AlertLevel.danger)) {
      HapticFeedback.heavyImpact();
    }
    await _prefs.setStringList(_kNotified, {...seen, ...toSend.map((a) => a.id)}.toList());
  }

  Future<void> addReport(FieldReport report) => addReports([report]);

  Future<void> addReports(List<FieldReport> added) async {
    reports = [...added, ...reports];
    await _reportsChanged();
  }

  Future<void> deleteReport(String id) async {
    final gone = reports.where((r) => r.id == id).toList();
    reports = reports.where((r) => r.id != id).toList();
    await _reportsChanged(checkNow: false);
    for (final r in gone) {
      if (r.remoteId != null && r.deleteToken != null) {
        try {
          await reportApi?.delete(r.remoteId!, r.deleteToken!);
        } catch (_) {
          // Gone from this phone; the backend drops it after 90 days anyway.
        }
      }
    }
  }

  Future<void> _reportsChanged({bool checkNow = true}) async {
    smokeEstimates = triangulate(_allReports);
    await reportStore.save(reports);
    notifyListeners();
    if (!checkNow) return;
    // Upload right away; a new crossing may be close to the user, so check
    // and notify too.
    if (reportApi != null || smokeEstimates.isNotEmpty) {
      await checkAlerts(notify: true, onlyNew: true);
    }
  }
}

/// Makes [AppState] available to the widget tree and rebuilds on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
