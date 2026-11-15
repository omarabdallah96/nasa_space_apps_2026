import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/hotspot.dart';
import '../data/models/region.dart';
import '../data/models/zone.dart';
import '../data/repositories/fire_repository.dart';
import '../l10n/strings.dart';
import '../services/alert_engine.dart';
import '../services/auth_api.dart';
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
    this.authApi,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secure = secureStorage ?? const FlutterSecureStorage(),
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

  /// Optional accounts; null (demo mode) means everyone is a guest.
  final AuthApi? authApi;

  /// Keeps the sign-in token out of plain preferences.
  final FlutterSecureStorage _secure;

  /// The signed-in person, or null for a guest. Every feature works as a guest.
  AccountUser? user;
  String? _token;
  bool get isGuest => user == null;
  bool get accountsAvailable => authApi != null;

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
      _kDeviceId = 'device_id',
      _kUser = 'account_user',
      _kToken = 'auth_token',
      _kZones = 'zones',
      _kProTest = 'pro_test';

  // ── Pro and zones ──

  /// Zones a free user can have; Pro raises it to [proZoneLimit].
  static const freeZoneLimit = 1, proZoneLimit = 20;

  /// Debug builds can switch Pro on to try the paid features before payments
  /// are wired up. Ignored in release builds.
  bool proTest = false;

  bool get isPro => (user?.isPro ?? false) || (kDebugMode && proTest);
  int get zoneLimit => isPro ? proZoneLimit : freeZoneLimit;

  /// Circles drawn on the map; alerts cover the first [zoneLimit] of them.
  List<AlertZone> zones = const [];

  /// Zones that get alerts. Zones beyond the limit (after Pro ends) are kept, paused.
  List<AlertZone> get activeZones => zones.take(zoneLimit).toList();
  bool get canAddZone => zones.length < zoneLimit;

  void setProTest(bool on) {
    proTest = on;
    _prefs.setBool(_kProTest, on);
    notifyListeners();
    checkAlerts();
  }

  /// Returns false when the limit is reached (the UI then shows the paywall).
  Future<bool> addZone(String name, LatLng center, double radiusKm) async {
    if (!canAddZone) return false;
    zones = [
      ...zones,
      AlertZone(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        name: name.trim(),
        center: center,
        radiusKm: radiusKm.clamp(AlertZone.minRadiusKm, AlertZone.maxRadiusKm),
        createdAt: DateTime.now(),
      ),
    ];
    await _saveZones();
    checkAlerts();
    return true;
  }

  Future<void> updateZone(String id, {String? name, double? radiusKm}) async {
    zones = [
      for (final z in zones)
        z.id == id ? z.copyWith(name: name?.trim(), radiusKm: radiusKm) : z,
    ];
    await _saveZones();
    checkAlerts();
  }

  Future<void> deleteZone(String id) async {
    zones = zones.where((z) => z.id != id).toList();
    await _saveZones();
    checkAlerts();
  }

  Future<void> _saveZones() async {
    notifyListeners();
    await _prefs.setString(_kZones, jsonEncode([for (final z in zones) z.toJson()]));
  }

  List<AlertZone> _loadZones() {
    final text = _prefs.getString(_kZones);
    if (text == null) return const [];
    try {
      return [
        for (final j in jsonDecode(text) as List) AlertZone.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

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
    await _restoreAccount();
    zones = _loadZones();
    proTest = _prefs.getBool(_kProTest) ?? false;
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

  // ── Account ──

  /// The last known user comes from preferences, so the app opens signed in
  /// even offline; the server is asked afterwards whether the token still works.
  Future<void> _restoreAccount() async {
    if (authApi == null) return;
    try {
      _token = await _secure.read(key: _kToken);
    } catch (_) {
      _token = null; // Keystore trouble: start as a guest.
    }
    final saved = _prefs.getString(_kUser);
    if (_token == null || saved == null) {
      user = null;
      return;
    }
    try {
      user = AccountUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      user = null;
      return;
    }
    unawaited(refreshAccount());
  }

  /// Signs out on this phone when the server says the session is over;
  /// keeps the saved user when the server cannot be reached.
  Future<void> refreshAccount() async {
    final api = authApi, token = _token;
    if (api == null || token == null) return;
    try {
      await _setUser(await api.me(token), token);
    } on AuthException catch (e) {
      if (e.code == 'signed_out') await _clearAccount();
    }
  }

  /// Throws [AuthException] on failure.
  Future<void> signIn(String email, String password) async {
    final r = await authApi!.login(email: email.trim(), password: password);
    await _setUser(r.user, r.token);
  }

  /// Creates an account and signs in. Throws [AuthException] on failure.
  Future<void> register(String email, String password, {String name = ''}) async {
    final r = await authApi!.register(email: email.trim(), password: password, name: name.trim());
    await _setUser(r.user, r.token);
  }

  Future<void> updateName(String name) async {
    final token = _token;
    if (token == null) return;
    await _setUser(await authApi!.updateName(token, name.trim()), token);
  }

  /// Back to guest. The server session is ended when it can be reached.
  Future<void> signOut() async {
    final token = _token;
    await _clearAccount();
    if (token != null) {
      try {
        await authApi?.logout(token);
      } catch (_) {
        // Offline: the session expires on its own.
      }
    }
  }

  /// Deletes the account on the server, then signs out. Throws [AuthException].
  Future<void> deleteAccount(String password) async {
    final token = _token;
    if (token == null) return;
    await authApi!.deleteAccount(token, password);
    await _clearAccount();
  }

  Future<void> _setUser(AccountUser u, String token) async {
    user = u;
    _token = token;
    await _secure.write(key: _kToken, value: token);
    await _prefs.setString(_kUser, jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> _clearAccount() async {
    user = null;
    _token = null;
    notifyListeners();
    await _prefs.remove(_kUser);
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {
      // Nothing more to do: the token is already forgotten in memory.
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
    // Zones reuse the hotspots fetched for their region.
    final spotCache = <String, Future<List<Hotspot>>>{};
    Future<List<Hotspot>> spotsOf(String id) =>
        spotCache[id] ??= repository.getRecentHotspots(id);
    for (final r in regions.where((r) => ids.contains(r.id))) {
      try {
        final record = await repository.getRecord(r.id);
        final spots = await spotsOf(r.id);
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
    found.addAll(await _dangerAlerts(ids));
    found.addAll(_smokeAlerts(ids));
    found.addAll(await _zoneAlerts(spotsOf));
    found.sort((a, b) => b.level.index.compareTo(a.level.index));
    alerts = found;
    checkingAlerts = false;
    notifyListeners();
    if (notify) await _notify(found, onlyNew: onlyNew);
  }

  /// Per active zone: satellite fires inside it, a fire located by smoke
  /// reports inside it, and very high danger forecast at its center.
  Future<List<FireAlert>> _zoneAlerts(Future<List<Hotspot>> Function(String) spotsOf) async {
    final out = <FireAlert>[];
    for (final z in activeZones) {
      final region = matchRegion(regions, z.center)?.region;
      if (region == null) continue;
      try {
        final a = alertEngine.zoneFire(zone: z, region: region, hotspots: await spotsOf(region.id));
        if (a != null) out.add(a);
      } catch (_) {
        // No hotspots now; the forecast below still counts.
      }
      try {
        final f = await repository.getDangerForecast(z.center);
        final a = alertEngine.dangerAlert(region: region, days: f.days, now: DateTime.now(), zone: z);
        if (a != null) out.add(a);
      } catch (_) {
        // Outside forecast coverage, or offline.
      }
      for (final e in smokeEstimates.where((e) => z.contains(e.center))) {
        out.add(FireAlert(
          type: AlertType.groundSmoke,
          level: AlertLevel.danger,
          region: region,
          zone: z,
          count: e.reports.length,
          distanceKm: distanceKm(z.center, e.center),
          compass: compassIndex(z.center, e.center),
          estimateKey: '${e.center.latitude.toStringAsFixed(2)},${e.center.longitude.toStringAsFixed(2)}',
        ));
      }
    }
    return out;
  }

  /// Very high or extreme fire danger forecast: near the user when their
  /// position is known, otherwise over each watched place.
  Future<List<FireAlert>> _dangerAlerts(Set<String> ids) async {
    final out = <FireAlert>[];
    final me = userPosition ?? lastKnownPosition;
    String? mine;
    if (me != null) {
      final match = matchRegion(regions, me);
      if (match != null && match.inside) {
        try {
          final f = await repository.getDangerForecast(me);
          final a = alertEngine.dangerAlert(
              region: match.region, days: f.days, now: DateTime.now(), nearUser: true);
          mine = match.region.id;
          if (a != null) out.add(a);
        } catch (_) {
          // No forecast here; the watched places below still count.
        }
      }
    }
    for (final r in regions.where((r) => ids.contains(r.id) && r.id != mine)) {
      try {
        final f = await repository.getRegionDanger(r.id);
        final a = alertEngine.dangerAlert(region: r, days: f.days, now: DateTime.now());
        if (a != null) out.add(a);
      } catch (_) {
        // One region failing should not hide the others.
      }
    }
    return out;
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
