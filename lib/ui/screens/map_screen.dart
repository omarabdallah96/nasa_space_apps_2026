import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/hotspot.dart';
import '../../data/models/region.dart';
import '../../l10n/strings.dart';
import '../../services/report_store.dart';
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
                        MarkerLayer(
                          markers: [
                            for (final h in spots)
                              Marker(
                                point: h.position,
                                width: 22,
                                height: 22,
                                child: GestureDetector(
                                  onTap: () => _showHotspot(context, h),
                                  child: _HotspotDot(h),
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
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.lightBlueAccent,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: const [BoxShadow(blurRadius: 6)],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SimpleAttributionWidget(
                          source: Text('NASA GIBS · FIRMS'),
                        ),
                      ],
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
                      top: 12,
                      child: StatusPill(
                        label: '${spots.length} ${s.t('detections')}',
                        color: Ember.amber,
                      ),
                    ),
                    PositionedDirectional(
                      end: 12,
                      top: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'me',
                        tooltip: s.t('my_location'),
                        backgroundColor: Ember.surface,
                        onPressed: _goToMe,
                        child: const Icon(Icons.my_location, color: Ember.text),
                      ),
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
      ReportLabel.agriculturalBurn => Icons.agriculture,
      ReportLabel.industrial => Icons.factory_outlined,
      ReportLabel.falseAlarm => Icons.do_not_disturb_on_outlined,
      ReportLabel.unsure => Icons.help_outline,
    };

IconData labelIcon(ReportLabel l) => _labelIcon(l);

class _HotspotDot extends StatelessWidget {
  const _HotspotDot(this.h);
  final Hotspot h;

  @override
  Widget build(BuildContext context) {
    final t = (h.frp / 30).clamp(0.3, 1.0);
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
