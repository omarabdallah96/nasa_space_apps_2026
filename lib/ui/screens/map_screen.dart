import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/hotspot.dart';
import '../../data/models/region.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Recent hotspots (last 48 h) on NASA GIBS VIIRS true-colour imagery.
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

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
      appBar: AppBar(title: const Text('Hotspots · last 48 h')),
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
                          ],
                        ),
                        const SimpleAttributionWidget(
                          source: Text('NASA GIBS · FIRMS'),
                        ),
                      ],
                    ),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(color: Ember.ember),
                      ),
                    if (snap.hasError) ErrorView(error: snap.error!),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: StatusPill(
                        label: '${spots.length} detections',
                        color: Ember.amber,
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Ember.surface,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hotspot', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${h.position.latitude.toStringAsFixed(4)}, '
              '${h.position.longitude.toStringAsFixed(4)}\n'
              '${h.acquiredAt.toUtc().toIso8601String().substring(0, 16)} UTC\n'
              '${h.sensor} · confidence ${h.confidence} · ${h.frp} MW',
              style: monoStyle(size: 13, color: Ember.text),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Field verification is coming next'),
                  ));
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Verify in the field'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
