import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/hotspot.dart';
import '../../l10n/strings.dart';
import '../../services/report_store.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'map_screen.dart' show labelIcon;

/// Field verification: photo + GPS + "what do you see?".
/// Turns a satellite detection into ground truth.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.hotspot});

  /// The satellite hotspot being verified, if any.
  final Hotspot? hotspot;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _note = TextEditingController();
  final _picker = ImagePicker();
  ReportLabel? _label;
  String? _photoPath;
  LatLng? _position;
  bool _locating = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final state = AppScope.read(context);
    try {
      _position = await state.location.currentPosition();
    } catch (_) {
      // Fall back to the hotspot or last known position.
      _position = widget.hotspot?.position ?? state.userPosition;
    }
    if (mounted) setState(() => _locating = false);
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
          source: source, maxWidth: 1600, imageQuality: 80);
      if (file != null) setState(() => _photoPath = file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.of(context).t('could_not_open')}: $e')));
    }
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final photo = await ReportStore.keepPhoto(_photoPath, id);
    await state.addReport(FieldReport(
      id: id,
      position: _position ?? widget.hotspot!.position,
      createdAt: DateTime.now(),
      label: _label!,
      note: _note.text.trim(),
      photoPath: photo,
      hotspotSensor: widget.hotspot?.sensor,
      hotspotTime: widget.hotspot?.acquiredAt,
    ));
    messenger.showSnackBar(SnackBar(content: Text(s.t('report_saved'))));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final h = widget.hotspot;
    final canSave = _label != null &&
        !_saving &&
        (_position != null || h != null);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('field_report'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Photo.
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: Ember.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Ember.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoPath == null
                  ? const Icon(Icons.photo_camera_outlined,
                      size: 48, color: Ember.textMuted)
                  : kIsWeb
                      ? Image.network(_photoPath!, fit: BoxFit.cover)
                      : Image.file(File(_photoPath!), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(s.t('take_photo')),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.t('from_gallery')),
            ),
          ]),
          const SizedBox(height: 20),
          Text(s.t('what_see'), style: text.titleLarge?.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in ReportLabel.values)
                ChoiceChip(
                  avatar: Icon(labelIcon(l), size: 18),
                  label: Text(s.label(l)),
                  selected: _label == l,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _label = l),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: s.t('note'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.place_outlined,
            label: s.t('position'),
            value: _locating
                ? s.t('getting_position')
                : _position == null
                    ? '—'
                    : '${_position!.latitude.toStringAsFixed(5)}, '
                        '${_position!.longitude.toStringAsFixed(5)}',
          ),
          if (h != null)
            _InfoRow(
              icon: Icons.satellite_alt_outlined,
              label: s.t('linked_hotspot'),
              value: '${h.sensor} · ${h.acquiredAt.toUtc().toIso8601String().substring(0, 16)}',
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.t('save_report')),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: Ember.textMuted),
          const SizedBox(width: 8),
          Text('$label: ', style: monoStyle(size: 12)),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(value,
                  style: monoStyle(size: 12, color: Ember.text),
                  textAlign: TextAlign.end),
            ),
          ),
        ]),
      );
}

/// All saved field reports.
class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('my_reports'))),
      body: state.reports.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(s.t('no_reports'), textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.t('reports_note'), style: monoStyle(size: 11)),
                const SizedBox(height: 12),
                for (final r in state.reports) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: r.photoPath != null && !kIsWeb
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(r.photoPath!),
                                  width: 52, height: 52, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(labelIcon(r.label))),
                            )
                          : Icon(labelIcon(r.label), color: Ember.calm),
                      title: Text(s.label(r.label)),
                      subtitle: Text(
                        '${r.createdAt.toLocal().toString().substring(0, 16)}\n'
                        '${r.position.latitude.toStringAsFixed(4)}, '
                        '${r.position.longitude.toStringAsFixed(4)}'
                        '${r.note.isEmpty ? '' : '\n${r.note}'}',
                        style: monoStyle(size: 11),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: s.t('delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => state.deleteReport(r.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}
