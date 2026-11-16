import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../camera/widgets/camera_design.dart';
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
  late final _site = TextEditingController(text: _t.config.siteId);
  late final _remarks = TextEditingController(text: _t.config.remarks);
  late final _note = TextEditingController(text: _t.config.note);
  late final _person = TextEditingController(text: _t.config.personName);
  late final _contact = TextEditingController(text: _t.config.contactNumber);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _site.dispose();
    _remarks.dispose();
    _person.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _syncText() {
    final c = _t.config;
    _title.text = c.projectTitle;
    _site.text = c.siteId;
    _remarks.text = c.remarks;
    _note.text = c.note;
    _person.text = c.personName;
    _contact.text = c.contactNumber;
  }

  Future<void> _saveTemplate() async {
    var name = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save custom template'),
        content: TextField(
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Template name'),
          onChanged: (value) => name = value,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title != null && mounted) _t.saveTemplate(title);
  }

  Future<void> _loadTemplate() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Saved templates'),
        children: [
          for (final name in _t.savedNames)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    _t.applySavedTemplate(title);
    _syncText();
  }

  Future<void> _reorderFields() async {
    final fields = _t.config.orderedDetails;
    final updated = await showModalBottomSheet<List<StampField>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            children: [
              const ListTile(title: Text('Reorder stamp details')),
              Expanded(
                child: ReorderableListView(
                  children: [
                    for (final field in fields)
                      ListTile(key: ValueKey(field), title: Text(field.label)),
                  ],
                  onReorderItem: (from, to) => setSheetState(() {
                    final field = fields.removeAt(from);
                    fields.insert(to, field);
                  }),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, fields),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && updated != null) _t.update((c) => c.fieldOrder = updated);
  }

  static const _groups = <String, List<StampField>>{
    'Location & Map': [
      StampField.mapType,
      StampField.fullAddress,
      StampField.shortAddress,
      StampField.countryFlag,
      StampField.latLong,
      StampField.plusCode,
      StampField.altitude,
      StampField.accuracy,
      StampField.speed,
      StampField.city,
      StampField.region,
      StampField.country,
    ],
    'Date & Time': [
      StampField.dateTime,
      StampField.timeZone,
      StampField.numbering,
    ],
    'Reporting': [
      StampField.logo,
      StampField.note,
      StampField.personName,
      StampField.contactNumber,
      StampField.siteId,
      StampField.remarks,
    ],
    // Weather fields are left out until the app has a weather data source.
    'Environment': [StampField.compass, StampField.magneticField],
  };

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      title: 'Custom Template',
      subtitle: 'Build your own stamp · sample location',
      body: ListenableBuilder(
        listenable: _t,
        builder: (context, _) {
          final c = _t.config;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Insets.md, 6, Insets.md, 36),
            children: [
              _previewCard(c),
              Wrap(
                spacing: Insets.xs,
                children: [
                  TextButton(
                    onPressed: _saveTemplate,
                    child: const Text('Save template'),
                  ),
                  TextButton(
                    onPressed: _t.savedNames.isEmpty ? null : _loadTemplate,
                    child: const Text('Load template'),
                  ),
                  TextButton(
                    onPressed: () {
                      _t.resetTemplate();
                      _syncText();
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              const SectionLabel('STYLE'),
              // Compact camera-style tiles: tap a tile to cycle its value.
              _glassCard(
                Row(
                  children: [
                    Expanded(
                      child: CycleTile(
                        icon: Icons.format_size,
                        label: c.size.label,
                        active: true,
                        onTap: () => _t.update(
                          (c) => c.size = _next(StampSize.values, c.size),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CycleTile(
                        icon: c.mapSide == MapSide.left
                            ? Icons.align_horizontal_left
                            : Icons.align_horizontal_right,
                        label: c.mapSide == MapSide.left ? 'Left' : 'Right',
                        active: true,
                        onTap: () => _t.update(
                          (c) => c.mapSide = c.mapSide == MapSide.left
                              ? MapSide.right
                              : MapSide.left,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CycleTile(
                        icon: Icons.palette_outlined,
                        label: c.palette.label,
                        active: true,
                        onTap: () => _t.update(
                          (c) =>
                              c.palette = _next(StampPalette.values, c.palette),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),

              TextButton(
                onPressed: c.orderedDetails.length < 2 ? null : _reorderFields,
                child: const Text('Reorder fields'),
              ),
              const SectionLabel('LAYOUT'),
              Wrap(
                spacing: Insets.xs,
                children: [
                  ActionChip(
                    label: Text(
                      'Width ${(c.width * 100).round()}%',
                      style: const TextStyle(color: Palette.accentYellow),
                    ),
                    onPressed: () => _t.update(
                      (c) => c.width = _next([1.0, 0.9, 0.75], c.width),
                    ),
                  ),
                  ActionChip(
                    label: Text(
                      'Map ${c.mapSize.label}',
                      style: const TextStyle(color: Palette.accentYellow),
                    ),
                    onPressed: () => _t.update(
                      (c) => c.mapSize = _next(StampSize.values, c.mapSize),
                    ),
                  ),
                  ActionChip(
                    label: Text(
                      'Spacing ${c.spacing.label}',
                      style: const TextStyle(color: Palette.accentYellow),
                    ),
                    onPressed: () => _t.update(
                      (c) => c.spacing = _next(StampSize.values, c.spacing),
                    ),
                  ),
                ],
              ),
              _glassCard(
                Column(
                  children: [
                    GlassSwitchTile(
                      label: 'Bold text',
                      icon: Icons.format_bold,
                      value: c.boldText,
                      onChanged: (value) =>
                          _t.update((c) => c.boldText = value),
                    ),
                    GlassSwitchTile(
                      label: 'Accent text',
                      icon: Icons.format_color_text,
                      value: c.accentText,
                      onChanged: (value) =>
                          _t.update((c) => c.accentText = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),

              _glassCard(
                ExpansionTile(
                  key: const PageStorageKey('custom-text-settings'),
                  title: Text(
                    'CUSTOM TEXT',
                    style: AppText.caption.copyWith(color: Palette.textMid),
                  ),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: Insets.xs),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  iconColor: Palette.textMid,
                  collapsedIconColor: Palette.textMid,
                  maintainState: true,
                  expansionAnimationStyle: AnimationStyle(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.normal,
                    curve: Motion.standard,
                  ),
                  onExpansionChanged: (expanded) {
                    if (!expanded) FocusScope.of(context).unfocus();
                  },
                  children: [
                    _field(
                      'Project / Title',
                      _title,
                      Icons.title,
                      (v) => _t.update((c) => c.projectTitle = v),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Site ID',
                      _site,
                      Icons.badge_outlined,
                      (v) => _t.update((c) {
                        c.siteId = v;
                        if (v.trim().isNotEmpty) {
                          c.fields.add(StampField.siteId);
                        }
                      }),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Remarks',
                      _remarks,
                      Icons.comment_outlined,
                      (v) => _t.update((c) {
                        c.remarks = v;
                        if (v.trim().isNotEmpty) {
                          c.fields.add(StampField.remarks);
                        }
                      }),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Note / Hashtag',
                      _note,
                      Icons.tag,
                      (v) => _t.update((c) => c.note = v),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Person Name',
                      _person,
                      Icons.person_outline,
                      (v) => _t.update((c) => c.personName = v),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'Contact Number',
                      _contact,
                      Icons.call_outlined,
                      (v) => _t.update((c) => c.contactNumber = v),
                      keyboard: TextInputType.phone,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),

              for (final entry in _groups.entries) ...[
                SectionLabel(entry.key.toUpperCase()),
                _glassCard(
                  Column(
                    children: [
                      for (var i = 0; i < entry.value.length; i++) ...[
                        if (i > 0) _div(),
                        _toggle(entry.value[i], c.has(entry.value[i])),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Insets.lg),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _previewCard(TemplateConfig c) {
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(Corners.lg),
      child: Container(
        constraints: const BoxConstraints(minHeight: 144),
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A3A3A), Color(0xFF151515), Color(0xFF272727)],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
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

  Widget _glassCard(Widget child) => CameraGlass(
    radius: Corners.lg,
    padding: const EdgeInsets.all(Insets.md),
    child: child,
  );

  /// Cycle an enum value to the next in its list (wraps around).
  T _next<T>(List<T> values, T current) =>
      values[(values.indexOf(current) + 1) % values.length];

  Widget _toggle(StampField f, bool on) => GlassSwitchTile(
    label: f.label,
    icon: f.icon,
    value: on,
    onChanged: (value) => _t.toggleField(f, value),
  );

  Widget _field(
    String hint,
    TextEditingController ctrl,
    IconData icon,
    ValueChanged<String> onChanged, {
    TextInputType? keyboard,
  }) {
    return Container(
      decoration: ShapeDecoration(
        color: Palette.glassFillStrong,
        shape: Corners.shape(
          Corners.md,
          side: const BorderSide(color: Palette.glassStrokeSoft),
        ),
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
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 6,
          ),
        ),
      ),
    );
  }

  Widget _div() =>
      Divider(color: Palette.glassStrokeSoft, height: 1, thickness: 0.6);
}
