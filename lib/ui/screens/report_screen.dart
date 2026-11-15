import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/hotspot.dart';
import '../../l10n/strings.dart';
import '../../services/report_store.dart';
import '../../state/app_state.dart';
import '../../services/triangulation.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/compass_aim.dart';
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
  double? _bearing;
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

  /// Camera only: a live photo is the evidence, so gallery images are not accepted.
  Future<void> _takePhoto() async {
    try {
      final file = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
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
      bearing: _bearing,
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
        _photoPath != null &&
        !_saving &&
        (_position != null || h != null);

    final needsDirection =
        _label == ReportLabel.smoke || _label == ReportLabel.wildfire;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('field_report'))),
      // Always-visible send button that says why it is disabled.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Ember.surface,
            border: Border(top: BorderSide(color: Ember.outline)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_label == null || _photoPath == null) ...[
                Row(children: [
                  Icon(Icons.info_outline, size: 16, color: Ember.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.t(_label == null ? 'save_hint' : 'photo_hint'),
                        style: text.bodySmall?.copyWith(color: Ember.textMuted)),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(s.t('save_report')),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Step 1: what (required).
          StepHeader(number: 1, title: s.t('what_see'), done: _label != null),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in ReportLabel.values)
                ChoiceChip(
                  avatar: Icon(labelIcon(l), size: 14),
                  label: Text(s.label(l)),
                  labelStyle: text.labelSmall?.copyWith(fontSize: 12),
                  labelPadding: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: _label == l,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _label = l),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Step 2: photo (required, camera only).
          StepHeader(number: 2, title: s.t('step_photo'), done: _photoPath != null),
          const SizedBox(height: 12),
          if (_photoPath != null) ...[
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: kIsWeb
                    ? Image.network(_photoPath!, fit: BoxFit.cover)
                    : Image.file(File(_photoPath!), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _takePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(s.t(_photoPath == null ? 'take_photo' : 'retake_photo')),
          ),
          // Step 3: direction, only when it helps (smoke / wildfire).
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topCenter,
            child: !needsDirection
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StepHeader(
                          number: 3,
                          title: s.t('step_direction'),
                          subtitle: s.t('step_direction_sub'),
                          optional: true,
                          done: _bearing != null,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Ember.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Ember.amber, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.explore_outlined,
                                    color: Ember.amber, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(s.t('compass_title'),
                                      style: text.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              CompassAim(
                                locked: _bearing,
                                onChanged: (b) => setState(() => _bearing = b),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          // Last step: note (optional).
          StepHeader(
            number: needsDirection ? 4 : 3,
            title: s.t('step_note'),
            optional: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: s.t('note'),
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
      appBar: AppBar(
        title: Text(s.t('my_reports')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) async {
              final messenger = ScaffoldMessenger.of(context);
              await state.addReports(demoSmokeReports());
              messenger.showSnackBar(SnackBar(content: Text(s.t('demo_smoke_done'))));
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'demo',
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(s.t('demo_smoke')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: state.reports.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fact_check_outlined, size: 56, color: Ember.textMuted),
                    const SizedBox(height: 16),
                    Text(s.t('no_reports'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => Navigator.pushReplacement(context,
                          MaterialPageRoute<void>(builder: (_) => const ReportScreen())),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(s.t('report_fire')),
                    ),
                  ],
                ),
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
                        '${r.bearing == null ? '' : ' · ${r.bearing!.round()}°'}'
                        '${r.note.isEmpty ? '' : '\n${r.note}'}',
                        style: monoStyle(size: 11),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: s.t('delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: Text(s.t('delete_confirm')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: Text(s.t('cancel')),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Ember.extreme),
                                  onPressed: () => Navigator.pop(d, true),
                                  child: Text(s.t('delete')),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await state.deleteReport(r.id);
                        },
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
