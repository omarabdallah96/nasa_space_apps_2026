import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/danger_forecast.dart';
import '../../data/models/hotspot.dart';
import '../../data/models/region.dart';
import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../services/report_store.dart';
import '../../services/triangulation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/danger_forecast_card.dart';
import '../widgets/zones_section.dart';
import 'report_screen.dart';
import 'safety_screen.dart';
import 'zone_editor_screen.dart';

/// Recent hotspots (last 48 h) on NASA GIBS VIIRS true-colour imagery, plus
/// the user's position and their field reports.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  String? _regionId;
  Future<List<Hotspot>>? _future;

  /// Fire danger layer: off by default, the hotspots stay the main story.
  bool _showDanger = false;
  int _dangerDay = 1;
  Future<RegionDanger>? _danger;

  /// GIBS daily imagery: use yesterday so the tile set is complete.
  String get _gibsDate {
    final d = DateTime.now().toUtc().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  LatLngBounds _bounds(Region r) =>
      LatLngBounds(LatLng(r.south, r.west), LatLng(r.north, r.east));

  Future<void> _goToMe() async {
    final state = AppScope.read(context);
    await state.locateMe();
    final p = state.userPosition;
    if (p != null && mounted) _map.move(p, 11);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    final region = state.selected!;
    if (region.id != _regionId) {
      final first = _regionId == null;
      _regionId = region.id;
      _future = state.repository.getRecentHotspots(region.id);
      _danger = null;
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _map.fitCamera(
            CameraFit.bounds(bounds: _bounds(region), padding: const EdgeInsets.all(24))));
      }
    }

    if (_showDanger) _danger ??= state.repository.getRegionDanger(region.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('hotspots_48h')),
        actions: [
          IconButton(
            tooltip: s.t('my_reports'),
            icon: Badge(
              isLabelVisible: state.reports.isNotEmpty,
              label: Text('${state.reports.length}'),
              child: const Icon(Icons.fact_check_outlined),
            ),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const ReportsListScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'report',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const ReportScreen())),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(s.t('report_fire')),
      ),
      body: Column(
        children: [
          const RegionChips(),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Hotspot>>(
              future: _future,
              builder: (context, snap) {
                final spots = snap.data ?? const <Hotspot>[];
                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCameraFit: CameraFit.bounds(
                          bounds: _bounds(region),
                          padding: const EdgeInsets.all(24),
                        ),
                        backgroundColor: Ember.background,
                        // Long-press anywhere to put an alert zone there.
                        onLongPress: (_, point) => addZone(context, center: point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
                              // SNPP has had no imagery since early Nov 2026 (404s);
                              // NOAA-20 carries the same VIIRS instrument.
                              'VIIRS_NOAA20_CorrectedReflectance_TrueColor/default/'
                              '$_gibsDate/GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg',
                          maxNativeZoom: 9,
                          userAgentPackageName: 'online.codingnow.firesight',
                        ),
                        // Fire danger forecast, under everything else.
                        if (_showDanger) _DangerLayer(future: _danger, day: _dangerDay),
                        // Compass lines from smoke reports.
                        PolylineLayer(
                          polylines: [
                            for (final r in state.reports)
                              if (r.bearing != null)
                                Polyline(
                                  points: [r.position, project(r.position, r.bearing!, 30)],
                                  strokeWidth: 2,
                                  color: Ember.amber.withValues(alpha: 0.85),
                                  pattern: StrokePattern.dashed(segments: const [8, 6]),
                                ),
                          ],
                        ),
                        // The user's alert zones (paused ones greyed).
                        CircleLayer(
                          circles: [
                            for (final (i, z) in state.zones.indexed)
                              CircleMarker(
                                point: z.center,
                                radius: z.radiusKm * 1000,
                                useRadiusInMeter: true,
                                color: (i < state.zoneLimit ? Ember.amber : Ember.textMuted)
                                    .withValues(alpha: 0.10),
                                borderColor: i < state.zoneLimit ? Ember.amber : Ember.textMuted,
                                borderStrokeWidth: 2,
                              ),
                          ],
                        ),
                        // Estimated fire: uncertainty circle.
                        CircleLayer(
                          circles: [
                            for (final e in state.smokeEstimates)
                              CircleMarker(
                                point: e.center,
                                radius: e.radiusKm * 1000,
                                useRadiusInMeter: true,
                                color: Ember.extreme.withValues(alpha: 0.18),
                                borderColor: Ember.extreme,
                                borderStrokeWidth: 2,
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            for (final z in state.zones)
                              Marker(
                                point: z.center,
                                width: 120,
                                height: 30,
                                child: GestureDetector(
                                  onTap: () => showZoneActions(context, z),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Ember.surface.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: Ember.amber),
                                      ),
                                      child: Text(z.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ),
                            for (final e in state.smokeEstimates)
                              Marker(
                                point: e.center,
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () => _showEstimate(context, e, spots),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Ember.extreme,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [BoxShadow(blurRadius: 8)],
                                    ),
                                    child: const Icon(Icons.local_fire_department,
                                        color: Colors.white, size: 22),
                                  ),
                                ),
                              ),
                            for (final h in spots)
                              Marker(
                                point: h.position,
                                width: 38,
                                height: 38,
                                child: GestureDetector(
                                  onTap: () => _showHotspot(context, h, spots),
                                  child: _HotspotDot(h.frp),
                                ),
                              ),
                            for (final r in state.reports)
                              Marker(
                                point: r.position,
                                width: 26,
                                height: 26,
                                child: Icon(_labelIcon(r.label),
                                    color: Ember.calm, size: 22,
                                    shadows: const [Shadow(blurRadius: 4)]),
                              ),
                            if (state.userPosition != null)
                              Marker(
                                point: state.userPosition!,
                                width: 22,
                                height: 22,
                                child: const _YouDot(),
                              ),
                          ],
                        ),
                      ],
                    ),
                    // Compact data credit, clear of the "Report" button.
                    PositionedDirectional(
                      start: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Ember.surface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('NASA GIBS · FIRMS', style: monoStyle(size: 10)),
                      ),
                    ),
                    if (snap.connectionState == ConnectionState.waiting ||
                        state.locating)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(color: Ember.ember),
                      ),
                    if (snap.hasError) ErrorView(error: snap.error!),
                    PositionedDirectional(
                      start: 12,
                      end: 72,
                      top: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MapChip(
                            icon: Icons.local_fire_department,
                            iconColor: Ember.ember,
                            label: '${spots.length} ${s.t('fires_48h')}',
                            bold: true,
                          ),
                          if (snap.hasData) ...[
                            const SizedBox(height: 6),
                            _MapChip(
                              icon: spots.isEmpty
                                  ? Icons.check_circle_outline
                                  : Icons.touch_app_outlined,
                              iconColor: spots.isEmpty ? Ember.calm : Ember.textMuted,
                              label: spots.isEmpty ? s.t('map_empty') : s.t('map_hint'),
                            ),
                          ],
                          if (_showDanger) ...[
                            const SizedBox(height: 6),
                            _DangerPicker(
                              future: _danger,
                              day: _dangerDay,
                              onDay: (d) => setState(() => _dangerDay = d),
                            ),
                          ],
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      end: 12,
                      top: 12,
                      child: Column(children: [
                        FloatingActionButton.small(
                          heroTag: 'me',
                          tooltip: s.t('my_location'),
                          backgroundColor: Ember.surface,
                          onPressed: _goToMe,
                          child: Icon(Icons.my_location, color: Ember.text),
                        ),
                        const SizedBox(height: 4),
                        FloatingActionButton.small(
                          heroTag: 'danger',
                          tooltip: s.t('danger_layer'),
                          backgroundColor: _showDanger ? Ember.ember : Ember.surface,
                          onPressed: () => setState(() => _showDanger = !_showDanger),
                          child: Icon(Icons.thermostat_auto,
                              color: _showDanger ? Colors.white : Ember.text),
                        ),
                        const SizedBox(height: 4),
                        FloatingActionButton.small(
                          heroTag: 'legend',
                          tooltip: s.t('legend'),
                          backgroundColor: Ember.surface,
                          onPressed: () => _showLegend(context),
                          child: Icon(Icons.info_outline, color: Ember.text),
                        ),
                      ]),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showLegend(BuildContext context) {
    final s = S.of(context);
    Widget row(Widget symbol, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 40, child: Center(child: symbol)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          ]),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Ember.surface,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('legend'), style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 8),
              row(
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _HotspotDot.sized(16),
                  const SizedBox(width: 4),
                  _HotspotDot.sized(22),
                ]),
                s.t('legend_hotspot'),
              ),
              row(const _YouDot(), s.t('legend_you')),
              row(const Icon(Icons.local_fire_department, color: Ember.calm, size: 22),
                  s.t('legend_report')),
              row(
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Ember.extreme.withValues(alpha: 0.25),
                    border: Border.all(color: Ember.extreme, width: 2),
                  ),
                ),
                s.t('legend_estimate'),
              ),
              row(
                Container(width: 32, height: 3, color: Ember.amber),
                s.t('legend_line'),
              ),
              row(
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final l in [DangerLevel.low, DangerLevel.high, DangerLevel.extreme])
                    Container(
                      width: 10,
                      height: 22,
                      color: Ember.forDanger(l).withValues(alpha: 0.7),
                    ),
                ]),
                s.t('legend_danger'),
              ),
              const SizedBox(height: 8),
              Text('NASA GIBS · FIRMS', style: monoStyle(size: 11)),
            ],
          ),
        ),
      ),
    );
  }

  void _showEstimate(BuildContext context, SmokeEstimate e, List<Hotspot> spots) {
    final s = S.of(context);
    final near = nearestHotspot(spots, e.center);
    final confirmed = near != null && near.distanceKm <= e.radiusKm + 2;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Ember.surface,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.local_fire_department, color: Ember.extreme),
              const SizedBox(width: 8),
              Text(s.t('smoke_estimate'), style: Theme.of(sheet).textTheme.titleLarge),
            ]),
            const SizedBox(height: 10),
            Text('${e.reports.length} ${s.t('from_reports')} · '
                '${s.t('uncertainty')} ±${e.radiusKm.toStringAsFixed(1)} km',
                style: monoStyle(size: 13, color: Ember.text)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${e.center.latitude.toStringAsFixed(4)}, ${e.center.longitude.toStringAsFixed(4)}',
                style: monoStyle(size: 12),
              ),
            ),
            const SizedBox(height: 12),
            StatusPill(
              label: confirmed ? s.t('satellite_confirms') : s.t('not_seen_satellite'),
              color: confirmed ? Ember.amber : Ember.extreme,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  openSafety(context, target: e.center, fires: [
                    e.center,
                    for (final h in spots)
                      if (distanceKm(h.position, e.center) <= 30) h.position,
                  ]);
                },
                icon: const Icon(Icons.alt_route),
                label: Text(s.t('safety_title')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHotspot(BuildContext context, Hotspot h, List<Hotspot> spots) {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Ember.surface,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('hotspot'), style: Theme.of(sheet).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${h.position.latitude.toStringAsFixed(4)}, '
                '${h.position.longitude.toStringAsFixed(4)}\n'
                '${h.acquiredAt.toUtc().toIso8601String().substring(0, 16)} UTC\n'
                '${h.sensor} · ${s.t('confidence')} ${h.confidence} · ${h.frp} MW',
                style: monoStyle(size: 13, color: Ember.text),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => ReportScreen(hotspot: h)),
                  );
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(s.t('verify_field')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  // Every detection around this one is part of the same danger.
                  openSafety(context, target: h.position, fires: [
                    for (final o in spots)
                      if (distanceKm(o.position, h.position) <= 30) o.position,
                  ]);
                },
                icon: const Icon(Icons.alt_route, color: Ember.ember),
                label: Text(s.t('safety_title'), style: TextStyle(color: Ember.text)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _labelIcon(ReportLabel l) => switch (l) {
      ReportLabel.wildfire => Icons.local_fire_department,
      ReportLabel.smoke => Icons.cloud_outlined,
      ReportLabel.agriculturalBurn => Icons.agriculture,
      ReportLabel.industrial => Icons.factory_outlined,
      ReportLabel.falseAlarm => Icons.do_not_disturb_on_outlined,
      ReportLabel.unsure => Icons.help_outline,
    };

IconData labelIcon(ReportLabel l) => _labelIcon(l);

/// Floating label on top of the map.
class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.icon,
    required this.label,
    this.iconColor,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Ember.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Ember.outline),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: iconColor ?? Ember.text),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Ember.text,
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ]),
      );
}

class _YouDot extends StatelessWidget {
  const _YouDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.lightBlueAccent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 6)],
        ),
      );
}

class _HotspotDot extends StatelessWidget {
  const _HotspotDot(this.frp) : fixedSize = null;

  /// A badge of a fixed size, for the legend.
  const _HotspotDot.sized(double size)
      : fixedSize = size,
        frp = 30;

  final num frp;
  final double? fixedSize;

  @override
  Widget build(BuildContext context) {
    // Stronger fires (higher FRP) get a bigger, hotter badge.
    final t = (frp / 30).clamp(0.3, 1.0).toDouble();
    final size = fixedSize ?? 24 + 12 * t;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Ember.heat(0.55 + 0.45 * t),
          border: Border.all(color: Colors.white, width: size < 20 ? 1 : 2),
          boxShadow: [
            BoxShadow(color: Ember.ember.withValues(alpha: 0.7), blurRadius: 8),
          ],
        ),
        child: Icon(Icons.local_fire_department, color: Colors.white, size: size * 0.62),
      ),
    );
  }
}

/// Forecast grid points as translucent coloured squares for the chosen day.
class _DangerLayer extends StatelessWidget {
  const _DangerLayer({required this.future, required this.day});
  final Future<RegionDanger>? future;
  final int day;

  @override
  Widget build(BuildContext context) => FutureBuilder<RegionDanger>(
        future: future,
        builder: (context, snap) {
          final f = snap.data;
          if (f == null) return const SizedBox.shrink();
          final half = f.stepDegrees / 2;
          return PolygonLayer(
            polygons: [
              for (final p in f.points)
                if (day < p.levels.length)
                  Polygon(
                    points: [
                      LatLng(p.position.latitude - half, p.position.longitude - half),
                      LatLng(p.position.latitude - half, p.position.longitude + half),
                      LatLng(p.position.latitude + half, p.position.longitude + half),
                      LatLng(p.position.latitude + half, p.position.longitude - half),
                    ],
                    color: Ember.forDanger(p.levels[day]).withValues(alpha: 0.38),
                    borderStrokeWidth: 0,
                  ),
            ],
          );
        },
      );
}

/// Today / tomorrow / the day after, with the region's headline level.
class _DangerPicker extends StatelessWidget {
  const _DangerPicker({required this.future, required this.day, required this.onDay});
  final Future<RegionDanger>? future;
  final int day;
  final ValueChanged<int> onDay;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return FutureBuilder<RegionDanger>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return _MapChip(icon: Icons.cloud_off, label: s.t('forecast_failed'));
        }
        final f = snap.data;
        if (f == null) {
          return _MapChip(icon: Icons.thermostat_auto, label: s.t('danger_layer'));
        }
        final d = f.days[day.clamp(0, f.days.length - 1)];
        String name(int i) => i == 0
            ? s.t('today')
            : i == 1
                ? s.t('tomorrow')
                : s.weekday(f.days[i].date.weekday);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, children: [
              for (var i = 0; i < 3 && i < f.days.length; i++)
                ChoiceChip(
                  label: Text(name(i)),
                  selected: i == day,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onDay(i),
                ),
            ]),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => showDangerDay(context, d),
              child: _MapChip(
                icon: dangerIcon(d.level),
                iconColor: Ember.forDanger(d.level),
                label: '${s.t('danger_layer')}: ${s.danger(d.level)}',
                bold: true,
              ),
            ),
          ],
        );
      },
    );
  }
}
