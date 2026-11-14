import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/hotspot.dart';
import '../../data/models/region.dart';
import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../../services/report_store.dart';
import '../../services/triangulation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'report_screen.dart';

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
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _map.fitCamera(
            CameraFit.bounds(bounds: _bounds(region), padding: const EdgeInsets.all(24))));
      }
    }

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
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
                              'VIIRS_SNPP_CorrectedReflectance_TrueColor/default/'
                              '$_gibsDate/GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg',
                          maxNativeZoom: 9,
                          userAgentPackageName: 'com.example.nasa_space_apps_2026',
                        ),
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
                                width: 22,
                                height: 22,
                                child: GestureDetector(
                                  onTap: () => _showHotspot(context, h),
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
                  _HotspotDot.sized(9),
                  const SizedBox(width: 4),
                  _HotspotDot.sized(16),
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
          ],
        ),
      ),
    );
  }

  void _showHotspot(BuildContext context, Hotspot h) {
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
  const _HotspotDot(this.frp);

  /// A dot of a fixed size, for the legend.
  const _HotspotDot.sized(double size) : frp = (size - 8) * 3;

  final num frp;

  @override
  Widget build(BuildContext context) {
    final t = (frp / 30).clamp(0.3, 1.0);
    final size = 8 + 10 * t;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Ember.heat(0.55 + 0.45 * t),
          border: Border.all(color: Colors.black54, width: 1),
          boxShadow: [
            BoxShadow(color: Ember.ember.withValues(alpha: 0.7), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
