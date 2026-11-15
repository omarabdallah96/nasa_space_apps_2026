import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/safety.dart';
import '../../data/models/zone.dart';
import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Opens the water-and-escape screen, or says it needs the server.
Future<void> openSafety(
  BuildContext context, {
  required LatLng target,
  List<LatLng> fires = const [],
  AlertZone? zone,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => SafetyScreen(target: target, fires: fires, zone: zone)),
  );
}

/// Where the routes start.
enum _From { me, target }

/// Nearby water, fire stations, hospitals and assembly points around a fire
/// or zone, and the fastest roads out that avoid the fire and its downwind side.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key, required this.target, this.fires = const [], this.zone});

  /// The fire, smoke estimate or zone centre.
  final LatLng target;

  /// Fires to get away from. Empty with a [zone]: the screen looks for live
  /// hotspots near it, and without any it shows ways out in every direction.
  final List<LatLng> fires;
  final AlertZone? zone;

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  final _map = MapController();

  /// People more than this far from the fire get routes from the fire instead.
  static const _nearKm = 40.0;

  _From _from = _From.target;
  LatLng? _me;
  bool _far = false;
  List<LatLng> _fires = const [];

  Future<Saved<List<SafetyResource>>>? _resources;
  Future<Saved<EscapePlan>>? _plan;
  int _selected = 0;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final state = AppScope.read(context);
    _me = state.userPosition ?? state.lastKnownPosition;
    _fires = widget.fires;
    if (widget.zone == null) {
      // A fire: people near it leave from where they are.
      if (_me != null && distanceKm(_me!, widget.target) <= _nearKm) {
        _from = _From.me;
      } else {
        _far = _me != null;
      }
    } else if (_fires.isEmpty) {
      _fires = await _firesNearZone(widget.zone!);
    }
    if (mounted) _load();
  }

  /// Live hotspots within reach of the zone, from the region it lies in.
  Future<List<LatLng>> _firesNearZone(AlertZone z) async {
    final state = AppScope.read(context);
    final region = matchRegion(state.regions, z.center)?.region ?? state.selected;
    if (region == null) return const [];
    try {
      final spots = await state.repository.getRecentHotspots(region.id);
      return [
        for (final h in spots)
          if (distanceKm(z.center, h.position) <= z.radiusKm + 20) h.position,
      ];
    } catch (_) {
      return const [];
    }
  }

  LatLng get _origin => _from == _From.me && _me != null ? _me! : widget.target;

  void _load() {
    final api = AppScope.read(context).safetyApi;
    if (api == null) return;
    final radius = (widget.zone?.radiusKm ?? 10).clamp(5, 25).toDouble();
    setState(() {
      _selected = 0;
      _fitted = false;
      _resources = api.resources(widget.target, radiusKm: radius);
      _plan = api.escape(_origin, _fires);
    });
  }

  void _fit(EscapePlan plan) {
    if (_fitted) return;
    _fitted = true;
    final pts = <LatLng>[
      plan.from,
      widget.target,
      if (plan.routes.isNotEmpty) ...plan.routes[_selected.clamp(0, plan.routes.length - 1)].points,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(36), maxZoom: 15));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = AppScope.of(context);
    final title = widget.zone == null ? s.t('safety_title') : '${s.t('safety_zone')} · ${widget.zone!.name}';

    if (state.safetyApi == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ErrorView(error: s.t('safety_failed')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<Saved<EscapePlan>>(
        future: _plan,
        builder: (context, planSnap) {
          final plan = planSnap.data?.value;
          if (plan != null) _fit(plan);
          return FutureBuilder<Saved<List<SafetyResource>>>(
            future: _resources,
            builder: (context, resSnap) {
              final resources = resSnap.data?.value ?? const <SafetyResource>[];
              return Column(
                children: [
                  Expanded(flex: 5, child: _buildMap(plan, resources)),
                  if (planSnap.connectionState == ConnectionState.waiting ||
                      resSnap.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(color: Ember.ember, minHeight: 3),
                  Expanded(
                    flex: 6,
                    child: _buildList(context, planSnap, resSnap),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMap(EscapePlan? plan, List<SafetyResource> resources) {
    final routes = plan?.routes ?? const <EscapeRoute>[];
    final sel = routes.isEmpty ? -1 : _selected.clamp(0, routes.length - 1);
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: widget.target,
          initialZoom: 12,
          backgroundColor: Ember.background,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'online.codingnow.firesight',
            maxZoom: 18,
          ),
          if (widget.zone != null)
            CircleLayer(circles: [
              CircleMarker(
                point: widget.zone!.center,
                radius: widget.zone!.radiusKm * 1000,
                useRadiusInMeter: true,
                color: Ember.amber.withValues(alpha: 0.08),
                borderColor: Ember.amber,
                borderStrokeWidth: 2,
              ),
            ]),
          if (plan != null)
            PolygonLayer(polygons: [
              for (final ring in plan.danger)
                Polygon(
                  points: ring,
                  color: Ember.extreme.withValues(alpha: 0.22),
                  borderColor: Ember.extreme,
                  borderStrokeWidth: 1.5,
                ),
            ]),
          PolylineLayer(polylines: [
            for (final (i, r) in routes.indexed)
              if (i != sel)
                Polyline(
                  points: r.points,
                  strokeWidth: 4,
                  color: Colors.blueGrey.withValues(alpha: 0.7),
                  pattern: StrokePattern.dashed(segments: const [10, 6]),
                ),
            if (sel >= 0) ...[
              Polyline(points: routes[sel].points, strokeWidth: 9, color: Colors.white),
              Polyline(
                points: routes[sel].points,
                strokeWidth: 6,
                color: routes[sel].safe ? _safe : Ember.amber,
              ),
            ],
          ]),
          MarkerLayer(markers: [
            for (final r in resources)
              Marker(
                point: r.position,
                width: 28,
                height: 28,
                child: GestureDetector(
                  onTap: () => _showResource(r),
                  child: _ResourcePin(r.kind),
                ),
              ),
            for (final f in _fires.take(300))
              Marker(
                point: f,
                width: 34,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Ember.extreme,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
                  ),
                  child: const Icon(Icons.local_fire_department, color: Colors.white, size: 22),
                ),
              ),
            for (final (i, r) in routes.indexed)
              Marker(
                point: r.destination,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: Icon(Icons.flag_circle,
                      size: 30, color: i == sel ? _safe : Colors.blueGrey,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.white)]),
                ),
              ),
            Marker(
              point: _origin,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.lightBlueAccent,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(blurRadius: 6)],
                ),
              ),
            ),
          ]),
        ],
      ),
      PositionedDirectional(
        start: 8,
        bottom: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black87)),
        ),
      ),
    ]);
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<Saved<EscapePlan>> planSnap,
    AsyncSnapshot<Saved<List<SafetyResource>>> resSnap,
  ) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final plan = planSnap.data?.value;
    final savedAt = planSnap.data?.savedAt ?? resSnap.data?.savedAt;
    final noFires = _fires.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_me != null)
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: Text(s.t('safety_from_me')),
              selected: _from == _From.me,
              onSelected: (_) {
                _from = _From.me;
                _load();
              },
            ),
            ChoiceChip(
              label: Text(s.t(widget.zone == null ? 'safety_from_fire' : 'safety_from_zone')),
              selected: _from == _From.target,
              onSelected: (_) {
                _from = _From.target;
                _load();
              },
            ),
          ]),
        if (_far && _from == _From.target) ...[
          const SizedBox(height: 6),
          Text(s.t('safety_far'), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        ],
        if (savedAt != null) ...[
          const SizedBox(height: 8),
          _Banner(
            icon: Icons.cloud_off,
            color: Ember.amber,
            text: '${s.t('safety_offline')} ${DateFormat.MMMd(s.ar ? 'ar' : 'en').add_Hm().format(savedAt)}',
          ),
        ],
        if (plan?.startInDanger ?? false) ...[
          const SizedBox(height: 8),
          _Banner(icon: Icons.warning_amber_rounded, color: Ember.extreme, text: s.t('safety_in_danger')),
        ],
        if (plan != null && !noFires) ...[
          const SizedBox(height: 10),
          _windLine(s, plan.wind),
        ],
        const SizedBox(height: 14),
        Text(s.t(noFires ? 'safety_exits' : 'safety_routes'), style: text.titleLarge?.copyWith(fontSize: 18)),
        const SizedBox(height: 8),
        if (planSnap.connectionState == ConnectionState.waiting || _plan == null)
          Text(s.t('safety_loading'), style: text.bodyMedium?.copyWith(color: Ember.textMuted))
        else if (planSnap.hasError)
          _Retry(onRetry: _load)
        else if (plan!.routes.isEmpty)
          Text(s.t('safety_no_routes'), style: text.bodyMedium)
        else
          for (final (i, r) in plan.routes.indexed) ...[
            _RouteCard(
              route: r,
              selected: i == _selected,
              onTap: () {
                setState(() => _selected = i);
                _map.fitCamera(CameraFit.coordinates(
                    coordinates: [plan.from, ...r.points], padding: const EdgeInsets.all(36), maxZoom: 15));
              },
              onNavigate: () => _navigate(plan.from, r),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 14),
        Text(s.t('safety_nearby'), style: text.titleLarge?.copyWith(fontSize: 18)),
        const SizedBox(height: 4),
        if (resSnap.connectionState == ConnectionState.waiting || _resources == null)
          Text(s.t('safety_loading'), style: text.bodyMedium?.copyWith(color: Ember.textMuted))
        else if (resSnap.hasError)
          _Retry(onRetry: _load)
        else if (resSnap.data!.value.isEmpty)
          Text(s.t('safety_none'), style: text.bodyMedium)
        else
          ..._resourceGroups(context, resSnap.data!.value),
        const SizedBox(height: 16),
        Text(s.t('safety_disclaimer'), style: text.bodySmall?.copyWith(color: Ember.textMuted)),
        const SizedBox(height: 4),
        Text(s.t('safety_sources'), style: monoStyle(size: 10)),
      ],
    );
  }

  Widget _windLine(S s, Wind? w) {
    final label = w == null || w.speedKmh < 5
        ? s.t('safety_calm')
        : '${s.t('safety_wind')} ${w.speedKmh.round()} km/h · ${s.t('safety_spreads')} ${s.compass(_compass(w.towardDeg))}';
    return Row(children: [
      Transform.rotate(
        angle: (w?.towardDeg ?? 0) * 3.14159265 / 180,
        child: Icon(w == null || w.speedKmh < 5 ? Icons.air : Icons.navigation, size: 18, color: Ember.extreme),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Container(width: 14, height: 14, decoration: BoxDecoration(
        color: Ember.extreme.withValues(alpha: 0.25), border: Border.all(color: Ember.extreme))),
      const SizedBox(width: 4),
      Flexible(child: Text(s.t('safety_danger'), style: TextStyle(fontSize: 11, color: Ember.textMuted))),
    ]);
  }

  List<Widget> _resourceGroups(BuildContext context, List<SafetyResource> all) {
    final s = S.of(context);
    const groups = [
      (ResourceKind.water, 'safety_water'),
      (ResourceKind.fireStation, 'safety_fire_station'),
      (ResourceKind.hospital, 'safety_hospital'),
      (ResourceKind.assemblyPoint, 'safety_assembly'),
    ];
    return [
      for (final (kind, key) in groups)
        if (all.any((r) => r.kind == kind)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Row(children: [
              _ResourcePin(kind, size: 20),
              const SizedBox(width: 8),
              Text(s.t(key), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
          for (final r in all.where((r) => r.kind == kind).take(kind == ResourceKind.water ? 8 : 4))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: () => _showResource(r),
              title: Text(r.displayName(s.ar) ?? _detail(s, r.detail),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: r.displayName(s.ar) == null ? null : Text(_detail(s, r.detail)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_km(r.distanceKm)} · ${s.compass(_compass(r.bearingDeg))}',
                    style: monoStyle(size: 12)),
                IconButton(
                  tooltip: s.t('safety_navigate'),
                  icon: const Icon(Icons.directions, color: Ember.ember),
                  onPressed: () => _launch(_mapsUrl(_origin, r.position, const [])),
                ),
              ]),
            ),
        ],
    ];
  }

  void _showResource(SafetyResource r) {
    _map.move(r.position, 15);
  }

  Future<void> _navigate(LatLng from, EscapeRoute r) {
    // A few points along the safe road keep Google Maps on it.
    final via = <LatLng>[];
    if (r.points.length > 4) {
      for (final f in const [0.25, 0.5, 0.75]) {
        via.add(r.points[(r.points.length * f).floor()]);
      }
    }
    return _launch(_mapsUrl(from, r.destination, via));
  }

  Uri _mapsUrl(LatLng from, LatLng to, List<LatLng> via) {
    String p(LatLng x) => '${x.latitude.toStringAsFixed(5)},${x.longitude.toStringAsFixed(5)}';
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': p(from),
      'destination': p(to),
      'travelmode': 'driving',
      if (via.isNotEmpty) 'waypoints': via.map(p).join('|'),
    });
  }

  Future<void> _launch(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uri.toString())));
    }
  }
}

const _safe = Color(0xFF2E9A72);

int _compass(int bearing) => ((bearing + 22.5) ~/ 45) % 8;

String _km(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

String _detail(S s, String detail) {
  final key = switch (detail) {
    'hydrant' || 'water_tank' || 'suction_point' || 'pond' || 'lake' || 'reservoir' || 'river' || 'canal' ||
    'fire_station' || 'hospital' || 'clinic' || 'assembly_point' => 'res_$detail',
    'city' || 'town' || 'village' => 'res_town',
    _ => 'res_water',
  };
  return s.t(key);
}

IconData _kindIcon(ResourceKind? k) => switch (k) {
      ResourceKind.water => Icons.water_drop,
      ResourceKind.fireStation => Icons.fire_truck,
      ResourceKind.hospital => Icons.local_hospital,
      ResourceKind.assemblyPoint => Icons.groups,
      ResourceKind.town => Icons.location_city,
      null => Icons.explore,
    };

Color _kindColor(ResourceKind k) => switch (k) {
      ResourceKind.water => const Color(0xFF2F8FD8),
      ResourceKind.fireStation => Ember.extreme,
      ResourceKind.hospital => const Color(0xFFB0246E),
      ResourceKind.assemblyPoint => _safe,
      ResourceKind.town => Ember.ash,
    };

class _ResourcePin extends StatelessWidget {
  const _ResourcePin(this.kind, {this.size = 28});
  final ResourceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kindColor(kind),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
        child: Icon(_kindIcon(kind), color: Colors.white, size: size * 0.55),
      );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.selected, required this.onTap, required this.onNavigate});
  final EscapeRoute route;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final name = route.displayName(s.ar);
    final where = route.destinationKind == null
        ? s.t('safety_away')
        : '${s.t('safety_to')} ${name ?? _detail(s, switch (route.destinationKind!) {
              ResourceKind.fireStation => 'fire_station',
              ResourceKind.hospital => 'hospital',
              ResourceKind.assemblyPoint => 'assembly_point',
              ResourceKind.water => 'water',
              ResourceKind.town => 'town',
            })}';
    final color = route.safe ? _safe : Ember.amber;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? color : Ember.outline, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Icon(_kindIcon(route.destinationKind), color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(where, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${_km(route.distanceKm)} · ${route.durationMin} ${s.t('safety_min')} · '
                  '${s.t('safety_heading')} ${s.compass(_compass(route.headingDeg))}',
                  style: monoStyle(size: 12),
                ),
                const SizedBox(height: 6),
                StatusPill(
                  label: route.safe ? s.t('safety_avoids') : s.t('safety_crosses'),
                  color: color,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onNavigate,
              style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.navigation, size: 18),
              label: Text(s.t('safety_navigate')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(children: [
      Expanded(child: Text(s.t('safety_failed'))),
      TextButton(onPressed: onRetry, child: Text(s.t('retry'))),
    ]);
  }
}
