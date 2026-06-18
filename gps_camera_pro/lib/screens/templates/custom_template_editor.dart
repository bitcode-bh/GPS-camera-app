import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/glass_scaffold.dart';
import '../../models/geo_data.dart';
import '../../models/template.dart';
import '../../state/settings_controller.dart';
import '../../state/template_controller.dart';
import '../../widgets/geo_stamp.dart';

class CustomTemplateEditor extends StatefulWidget {
  const CustomTemplateEditor({super.key});

  @override
  State<CustomTemplateEditor> createState() => _CustomTemplateEditorState();
}

class _CustomTemplateEditorState extends State<CustomTemplateEditor> {
  final _t = TemplateController.instance;
  final _settings = SettingsController.instance;
  final _geo = GeoData.demo();

  late final _title = TextEditingController(text: _t.config.projectTitle);
  late final _note = TextEditingController(text: _t.config.note);
  late final _person = TextEditingController(text: _t.config.personName);
  late final _contact = TextEditingController(text: _t.config.contactNumber);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _person.dispose();
    _contact.dispose();
    super.dispose();
  }

  static const _groups = <String, List<StampField>>{
    'Location & Map': [
      StampField.mapType, StampField.fullAddress, StampField.shortAddress,
      StampField.countryFlag, StampField.latLong, StampField.plusCode,
      StampField.altitude, StampField.accuracy, StampField.speed,
    ],
    'Date & Time': [
      StampField.dateTime, StampField.timeZone, StampField.numbering,
    ],
    'Reporting': [
      StampField.logo, StampField.note, StampField.personName, StampField.contactNumber,
    ],
    'Environment': [
      StampField.temperature, StampField.compass, StampField.magneticField,
      StampField.wind, StampField.humidity, StampField.pressure,
    ],
  };

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: 'Custom Template',
      subtitle: 'Build your own stamp',
      body: ListenableBuilder(
        listenable: _t,
        builder: (context, _) {
          final c = _t.config;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Insets.md, 6, Insets.md, 36),
            children: [
              _previewCard(c),
              const SizedBox(height: Insets.lg),

              const SectionLabel('STYLE'),
              // Compact camera-style tiles: tap a tile to cycle its value.
              _glassCard(Row(
                children: [
                  Expanded(child: CycleTile(
                    icon: Icons.format_size,
                    label: c.size.label,
                    active: true,
                    onTap: () => _t.update((c) => c.size = _next(StampSize.values, c.size)),
                  )),
                  Expanded(child: CycleTile(
                    icon: c.position == StampPosition.top
                        ? Icons.vertical_align_top
                        : Icons.vertical_align_bottom,
                    label: c.position == StampPosition.top ? 'Top' : 'Bottom',
                    active: true,
                    onTap: () => _t.update((c) => c.position =
                        c.position == StampPosition.top
                            ? StampPosition.bottom
                            : StampPosition.top),
                  )),
                  Expanded(child: CycleTile(
                    icon: c.mapSide == MapSide.left
                        ? Icons.align_horizontal_left
                        : Icons.align_horizontal_right,
                    label: c.mapSide == MapSide.left ? 'Left' : 'Right',
                    active: true,
                    onTap: () => _t.update((c) => c.mapSide =
                        c.mapSide == MapSide.left ? MapSide.right : MapSide.left),
                  )),
                  Expanded(child: CycleTile(
                    icon: Icons.palette_outlined,
                    label: c.palette.label,
                    active: true,
                    onTap: () => _t.update((c) => c.palette = _next(StampPalette.values, c.palette)),
                  )),
                ],
              )),
              const SizedBox(height: Insets.lg),

              const SectionLabel('CUSTOM TEXT'),
              _glassCard(Column(
                children: [
                  _field('Project / Title', _title, Icons.title,
                      (v) => _t.update((c) => c.projectTitle = v)),
                  const SizedBox(height: 10),
                  _field('Note / Hashtag', _note, Icons.tag,
                      (v) => _t.update((c) => c.note = v)),
                  const SizedBox(height: 10),
                  _field('Person Name', _person, Icons.person_outline,
                      (v) => _t.update((c) => c.personName = v)),
                  const SizedBox(height: 10),
                  _field('Contact Number', _contact, Icons.call_outlined,
                      (v) => _t.update((c) => c.contactNumber = v),
                      keyboard: TextInputType.phone),
                ],
              )),
              const SizedBox(height: Insets.lg),

              for (final entry in _groups.entries) ...[
                SectionLabel(entry.key.toUpperCase()),
                _glassCard(Column(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      if (i > 0) _div(),
                      _toggle(entry.value[i], c.has(entry.value[i])),
                    ],
                  ],
                )),
                const SizedBox(height: Insets.lg),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _previewCard(TemplateConfig c) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Corners.lg),
      child: Container(
        height: 240,
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF26354F), Color(0xFF121A2C), Color(0xFF1C2638)],
          ),
        ),
        child: Align(
          alignment:
              c.position == StampPosition.top ? Alignment.topCenter : Alignment.bottomCenter,
          child: GeoStamp(
            geo: _geo,
            config: c,
            settings: _settings,
            live: false,
            realMap: false,
          ),
        ),
      ),
    );
  }

  Widget _glassCard(Widget child) => GlassSurface(
        radius: Corners.lg,
        blur: 10,
        padding: const EdgeInsets.all(Insets.md),
        child: child,
      );

  /// Cycle an enum value to the next in its list (wraps around).
  T _next<T>(List<T> values, T current) =>
      values[(values.indexOf(current) + 1) % values.length];

  Widget _toggle(StampField f, bool on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(f.icon, size: 16, color: on ? Palette.textHi : Palette.textLo),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                f.label,
                style: AppText.body.copyWith(
                  color: on ? Palette.textHi : Palette.textMid,
                ),
              ),
            ),
            GlassSwitch(value: on, onChanged: (v) => _t.toggleField(f, v), compact: true),
          ],
        ),
      );

  Widget _field(String hint, TextEditingController ctrl, IconData icon,
      ValueChanged<String> onChanged,
      {TextInputType? keyboard}) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.glassFillStrong,
        borderRadius: BorderRadius.circular(Corners.md),
        border: Border.all(color: Palette.glassStrokeSoft),
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        keyboardType: keyboard,
        style: AppText.bodyHi,
        cursorColor: Palette.accentMuted,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.body.copyWith(color: Palette.textLo),
          prefixIcon: Icon(icon, size: 18, color: Palette.textMid),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        ),
      ),
    );
  }

  Widget _div() => Divider(color: Palette.glassStrokeSoft, height: 18, thickness: 0.6);
}
