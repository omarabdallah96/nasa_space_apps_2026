import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/zone.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'paywall.dart';

/// Opens the zone editor for a new zone, or the paywall when the free zone is
/// already used. [center] defaults to the user, then the selected region.
Future<void> addZone(BuildContext context, {LatLng? center}) async {
  final state = AppScope.read(context);
  if (!state.canAddZone) {
    final pro = await showPaywall(context, reasonKey: 'pro_reason_zones');
    if (!pro || !context.mounted) return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ZoneEditorScreen(
        initialCenter: center ?? state.userPosition ?? state.lastKnownPosition ?? state.selected?.center,
      ),
    ),
  );
}

/// Place a circle on the map: pan the map under the pin, set the radius and a
/// name. Editing an existing zone keeps its center.
class ZoneEditorScreen extends StatefulWidget {
  const ZoneEditorScreen({super.key, this.zone, this.initialCenter});

  final AlertZone? zone;
  final LatLng? initialCenter;

  @override
  State<ZoneEditorScreen> createState() => _ZoneEditorScreenState();
}

class _ZoneEditorScreenState extends State<ZoneEditorScreen> {
  final _map = MapController();
  late final _name = TextEditingController(text: widget.zone?.name ?? '');
  late double _radius = widget.zone?.radiusKm ?? AlertZone.defaultRadiusKm;
  late LatLng _center = widget.zone?.center ?? widget.initialCenter ?? const LatLng(33.9, 35.8);
  bool _saving = false;

  bool get _editing => widget.zone != null;

  /// A zoom that fits the circle with some margin.
  double get _zoom => switch (_radius) { <= 2 => 13, <= 5 => 12, <= 12 => 11, <= 25 => 10, _ => 9 };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    final state = AppScope.read(context);
    final name = _name.text.trim().isEmpty ? s.t('zone_default_name') : _name.text.trim();
    setState(() => _saving = true);
    if (_editing) {
      await state.updateZone(widget.zone!.id, name: name, radiusKm: _radius);
    } else if (!await state.addZone(name, _center, _radius)) {
      setState(() => _saving = false);
      if (mounted) await showPaywall(context, reasonKey: 'pro_reason_zones');
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t(_editing ? 'zone_edit' : 'zone_new'))),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                backgroundColor: Ember.background,
                // An existing zone keeps its place; only a new one is placed.
                interactionOptions: InteractionOptions(
                  flags: _editing ? InteractiveFlag.pinchZoom : InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: (camera, _) {
                  if (!_editing) setState(() => _center = camera.center);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
                      'VIIRS_NOAA20_CorrectedReflectance_TrueColor/default/'
                      '${_gibsDate()}/GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg',
                  maxNativeZoom: 9,
                  userAgentPackageName: 'com.example.nasa_space_apps_2026',
                ),
                // Place names, so people can find their village.
                TileLayer(
                  urlTemplate: 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
                      'Reference_Labels_15m/default/GoogleMapsCompatible_Level13/{z}/{y}/{x}.png',
                  maxNativeZoom: 13,
                  userAgentPackageName: 'com.example.nasa_space_apps_2026',
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius * 1000,
                    useRadiusInMeter: true,
                    color: Ember.ember.withValues(alpha: 0.16),
                    borderColor: Ember.ember,
                    borderStrokeWidth: 2.5,
                  ),
                ]),
              ],
            ),
            // The pin stays in the middle; the map moves under it.
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 36),
                  child: Icon(Icons.location_on, size: 40, color: Ember.ember,
                      shadows: [Shadow(blurRadius: 6)]),
                ),
              ),
            ),
            if (!_editing)
              PositionedDirectional(
                start: 12,
                end: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Ember.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(s.t('zone_place_hint'), style: const TextStyle(fontSize: 13)),
                ),
              ),
          ]),
        ),
        Material(
          color: Ember.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('zone_name'),
                    controller: _name,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: s.t('zone_name'),
                      hintText: s.t('zone_name_hint'),
                      prefixIcon: const Icon(Icons.label_outline),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text(s.t('zone_radius')),
                    Expanded(
                      child: Slider(
                        value: _radius,
                        min: AlertZone.minRadiusKm,
                        max: AlertZone.maxRadiusKm,
                        divisions: 49,
                        label: '${_radius.round()} ${s.t('km')}',
                        onChanged: (v) {
                          final before = _zoom;
                          setState(() => _radius = v);
                          if (_zoom != before) _map.move(_center, _zoom);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text('${_radius.round()} ${s.t('km')}',
                          textAlign: TextAlign.end, style: monoStyle(size: 13)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  FilledButton(
                    key: const ValueKey('zone_save'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Ember.ember,
                      foregroundColor: Colors.black,
                    ),
                    child: Text(s.t(_editing ? 'save' : 'zone_save'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// GIBS daily imagery: yesterday, so the tile set is complete.
String _gibsDate() {
  final d = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
