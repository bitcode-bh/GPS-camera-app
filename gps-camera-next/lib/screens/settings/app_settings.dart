import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/transitions.dart';
import '../../models/coordinates.dart';
import '../../models/geo_data.dart';
import '../../models/map_kind.dart';
import '../../models/template.dart';
import '../../state/settings_controller.dart';
import '../../state/template_controller.dart';
import '../camera/widgets/camera_design.dart';
import '../templates/custom_template_editor.dart';
import '../templates/templates_screen.dart';
import 'legal.dart';

/// App-settings categories. Map, coordinates and format/units are merged into a
/// single **Display & Units** popup, so the strip stays down to three clean
/// icons; Stamp and About keep their own popups.
enum SettingsCat { stamp, display, about }

extension SettingsCatX on SettingsCat {
  String get label => switch (this) {
    SettingsCat.stamp => 'Stamp',
    SettingsCat.display => 'Display & Units',
    SettingsCat.about => 'About',
  };
  IconData get icon => switch (this) {
    SettingsCat.stamp => Icons.dashboard_customize_outlined,
    SettingsCat.display => Icons.display_settings_outlined,
    SettingsCat.about => Icons.info_outline,
  };

  /// A short title shown under the icon in the expandable strip.
  String get stripLabel => switch (this) {
    SettingsCat.stamp => 'Stamp',
    SettingsCat.display => 'Display',
    SettingsCat.about => 'About',
  };
}

/// A settings control strip: a fixed button that expands into a horizontal row
/// of category icons. When [alignLeft] is true the button sits on the left and
/// the strip expands rightward; otherwise the button is on the right and the
/// strip expands leftward (default, original behaviour).
class AppSettingsStrip extends StatefulWidget {
  final bool open;
  final ValueChanged<bool>? onOpenChanged;
  final bool alignLeft;
  const AppSettingsStrip({
    super.key,
    required this.open,
    this.onOpenChanged,
    this.alignLeft = false,
  });

  @override
  State<AppSettingsStrip> createState() => _AppSettingsStripState();
}

class _AppSettingsStripState extends State<AppSettingsStrip> {
  late bool _open;
  // The category whose popup is currently open — drives the icon highlight.
  SettingsCat? _active;

  @override
  void initState() {
    super.initState();
    _open = widget.open;
  }

  @override
  void didUpdateWidget(covariant AppSettingsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      _open = widget.open;
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    widget.onOpenChanged?.call(_open);
  }

  Future<void> _select(SettingsCat c) async {
    // Keep the strip expanded behind the popup and light up the active icon.
    setState(() => _active = c);
    await showSettingsCategory(context, c);
    if (mounted) setState(() => _active = null);
  }

  @override
  Widget build(BuildContext context) {
    // When alignLeft: strip expands rightward (button on left, strip on right).
    // When !alignLeft (default): strip expands leftward (strip on left, button on right).
    final expandRight = widget.alignLeft;

    final strip = ClipRect(
      child: AnimatedAlign(
        alignment: expandRight ? Alignment.centerLeft : Alignment.centerRight,
        duration: Motion.normal,
        curve: Motion.emphasized,
        widthFactor: _open ? 1.0 : 0.0,
        child: AnimatedOpacity(
          opacity: _open ? 1 : 0,
          duration: Motion.normal,
          curve: Motion.emphasized,
          child: Padding(
            padding: expandRight
                ? const EdgeInsets.only(left: 8)
                : const EdgeInsets.only(right: 8),
            child: GlassSurface.menu(
              radius: Corners.pill,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final c in SettingsCat.values) _catTile(c)],
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: expandRight
          ? [_toggleButton(), strip]
          : [strip, _toggleButton()],
    );
  }

  // A flat category tile: icon over a short label, no selection container — the
  // active state (its popup open) is shown by colour alone.
  Widget _catTile(SettingsCat c) {
    final active = _active == c;
    return Pressable(
      onTap: () => _select(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              c.icon,
              size: 21,
              color: active ? Palette.accentMuted : Palette.textMid,
            ),
            const SizedBox(height: 4),
            Text(
              c.stripLabel,
              style: AppText.caption.copyWith(
                fontSize: 9,
                letterSpacing: 0.2,
                color: active ? Palette.textHi : Palette.textMid,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The settings gear stays visible when collapsed and flips to a close (✕)
  // while the strip is expanded.
  Widget _toggleButton() => GlassIconButton(
    icon: _open ? Icons.close : Icons.settings_outlined,
    label: _open ? 'Close settings' : 'Open settings',
    active: _open,
    size: 46,
    onTap: _toggle,
  );
}

/// Opens a category's settings in a centered glass popup.
Future<void> showSettingsCategory(BuildContext context, SettingsCat cat) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) => _SettingsPopup(cat: cat),
  );
}

class _SettingsPopup extends StatelessWidget {
  final SettingsCat cat;
  const _SettingsPopup({required this.cat});

  @override
  Widget build(BuildContext context) {
    final s = SettingsController.instance;
    final t = TemplateController.instance;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: Colors.transparent,
            child: CameraGlass(
              radius: Corners.lg,
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.md,
                Insets.lg,
                Insets.lg,
              ),
              child: ListenableBuilder(
                listenable: Listenable.merge([s, t]),
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        icon: cat.icon,
                        title: cat.label,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: Insets.sm),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _content(context, s, t),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    SettingsController s,
    TemplateController t,
  ) {
    switch (cat) {
      case SettingsCat.stamp:
        return [
          // Toggle at the top
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('Show stamp', style: AppText.bodyHi)),
                const SizedBox(width: Insets.sm),
                CycleTile(
                  icon: Icons.visibility_outlined,
                  label: s.stampEnabled ? 'On' : 'Off',
                  active: true,
                  onTap: () => s.update(() => s.stampEnabled = !s.stampEnabled),
                ),
              ],
            ),
          ),
          _div(),
          _NavTile(
            icon: Icons.dashboard_customize_outlined,
            title: 'Template',
            value: t.config.template.title,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(SheetRoute(page: const TemplatesScreen()));
            },
          ),
          _div(),
          _NavTile(
            icon: Icons.tune,
            title: 'Customize fields',
            value: '${t.config.fields.length} on',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(SheetRoute(page: const CustomTemplateEditor()));
            },
          ),
        ];
      case SettingsCat.display:
        // One combined popup: base map, coordinate format, and the format/unit
        // tiles, each under its own small group label.
        return [
          _SettingRow<int>(
            label: 'Maximum GPS error',
            options: [
              for (final limit in SettingsController.gpsAccuracyOptions)
                (value: limit, label: '$limit m'),
            ],
            selected: s.gpsAccuracyLimit,
            onChanged: (v) => s.update(() => s.gpsAccuracyLimit = v),
          ),
          _SettingRow<MapKind>(
            label: 'Base map',
            options: [
              for (final v in MapKind.values) (value: v, label: v.label),
            ],
            selected: s.mapKind,
            onChanged: (v) => s.update(() => s.mapKind = v),
          ),
          _SettingRow<CoordFormat>(
            label: 'Coordinate format',
            options: [
              for (final v in CoordFormat.values)
                (value: v, label: v == CoordFormat.plusCode ? 'Plus' : v.label),
            ],
            selected: s.coordFormat,
            onChanged: (v) => s.update(() => s.coordFormat = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: Insets.xs),
                  child: Text(
                    'FORMAT & UNITS',
                    style: AppText.caption.copyWith(color: Palette.textMid),
                  ),
                ),
                // Compact camera-style tiles: tapping a tile cycles its value.
                Row(
                  children: [
                    Expanded(
                      child: CycleTile(
                        icon: Icons.place_outlined,
                        label: s.addressFormat == AddressFormat.long
                            ? 'Full'
                            : 'Short',
                        active: true,
                        onTap: () => s.update(
                          () => s.addressFormat =
                              s.addressFormat == AddressFormat.long
                              ? AddressFormat.short
                              : AddressFormat.long,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CycleTile(
                        icon: Icons.straighten,
                        label: s.unitSystem == UnitSystem.metric
                            ? 'Metric'
                            : 'Imperial',
                        active: true,
                        onTap: () => s.update(
                          () => s.unitSystem = s.unitSystem == UnitSystem.metric
                              ? UnitSystem.imperial
                              : UnitSystem.metric,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CycleTile(
                        icon: Icons.thermostat,
                        label: s.tempUnit == TempUnit.celsius ? '°C' : '°F',
                        active: true,
                        onTap: () => s.update(
                          () => s.tempUnit = s.tempUnit == TempUnit.celsius
                              ? TempUnit.fahrenheit
                              : TempUnit.celsius,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CycleTile(
                        icon: Icons.schedule,
                        label: s.clock24 ? '24h' : '12h',
                        active: true,
                        onTap: () => s.update(() => s.clock24 = !s.clock24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
      case SettingsCat.about:
        return [
          const _AboutRow(label: 'App', value: 'GPS Camera Next'),
          FutureBuilder<String>(
            future: appVersion(),
            builder: (context, version) =>
                _AboutRow(label: 'Version', value: version.data ?? '—'),
          ),
          const _AboutRow(label: 'Maps', value: 'Powered by Esri'),
          const _AboutRow(label: 'Addresses', value: 'Device geocoder'),
          _AboutLink(label: 'Privacy', onTap: () => showPrivacy(context)),
          _AboutLink(
            label: 'Open-source licences',
            onTap: () => showOpenSourceLicences(context),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              mapAccuracyNotice,
              style: AppText.body.copyWith(fontSize: 12, height: 1.35),
            ),
          ),
        ];
    }
  }

  Widget _div() =>
      Divider(color: Palette.glassStrokeSoft, height: 1, thickness: 0.6);
}

// ── Standardized controls (shared, uniform sizing) ───────────────────────────

/// One labelled setting: a small uppercase field label above a full-width
/// [GlassSegmented] control. The active option is shown by colour alone and
/// every segment is always tappable, so switching options is a single tap —
/// the flat selection model, identical to the camera menu's controls.
class _SettingRow<T> extends StatelessWidget {
  final String label;
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const _SettingRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: Insets.xs),
            child: Text(
              label.toUpperCase(),
              style: AppText.caption.copyWith(color: Palette.textMid),
            ),
          ),
          GlassSegmented<T>(
            options: options,
            selected: selected,
            onChanged: onChanged,
            height: 44,
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Palette.accentMuted),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: AppText.bodyHi)),
            Text(value, style: AppText.label.copyWith(color: Palette.textMid)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Palette.textMid),
          ],
        ),
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AboutLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Text(label, style: AppText.body),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
          ],
        ),
      ),
    ),
  );
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(label, style: AppText.body),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppText.bodyHi,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
