import 'package:flutter/material.dart';

import '../core/design/palette.dart';
import '../core/design/text_styles.dart';
import '../core/design/tokens.dart';
import '../core/glass.dart';
import '../core/widgets/ticking_builder.dart';
import '../models/geo_data.dart';
import '../models/map_kind.dart';
import '../models/template.dart';
import '../state/settings_controller.dart';
import 'mini_map.dart';

/// The premium GPS geostamp. Rebuilds entirely from [config] + [settings], so
/// toggling a field or switching templates instantly changes what's rendered —
/// the same widget is reused for the live preview, the template thumbnails and
/// the burned-in capture.
class GeoStamp extends StatelessWidget {
  final GeoData geo;
  final TemplateConfig config;
  final SettingsController settings;

  /// Compact thumbnail mode for the template gallery (smaller, no blur cost).
  final bool preview;

  /// When true the date/time ticks live (off for static gallery thumbnails).
  final bool live;

  /// When false the mini-map renders as a painted placeholder instead of a live
  /// tile map — used by the small previews to avoid many map engines at once.
  final bool realMap;

  /// Callback when the mini-map is double-tapped (not active in preview)
  final VoidCallback? onMapDoubleTap;

  const GeoStamp({
    super.key,
    required this.geo,
    required this.config,
    required this.settings,
    this.preview = false,
    this.live = true,
    this.realMap = true,
    this.onMapDoubleTap,
  });

  double get _s => config.size.scale * (preview ? 0.82 : 1.0);
  Color get _accent => config.palette.accent;

  @override
  Widget build(BuildContext context) {
    final mapWidget = config.showsMap
        ? SizedBox(
            width: 112 * _s,
            height: 96 * _s,
            child: MiniMap(
              lat: geo.lat,
              lon: geo.lon,
              heading: geo.heading,
              kind: settings.mapKind,
              zoom: settings.mapZoom,
              accent: _accent,
              radius: Corners.sm,
              compact: preview,
              realMap: realMap,
            ),
          )
        : null;

    double mapDragDy = 0;
    final map = (mapWidget != null && onMapDoubleTap != null)
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: onMapDoubleTap,
            onHorizontalDragStart: (_) {},
            onHorizontalDragUpdate: (_) {},
            onHorizontalDragEnd: (_) {},
            onVerticalDragStart: (_) {
              mapDragDy = 0;
            },
            onVerticalDragUpdate: (details) {
              mapDragDy += details.delta.dy;
            },
            onVerticalDragEnd: (_) {
              if (mapDragDy.abs() >= 20) {
                final currentKind = settings.mapKind;
                final kinds = MapKind.values;
                final currentIndex = kinds.indexOf(currentKind);
                int nextIndex;
                if (mapDragDy < 0) {
                  // Swipe up -> next style
                  nextIndex = (currentIndex + 1) % kinds.length;
                } else {
                  // Swipe down -> previous style
                  nextIndex = (currentIndex - 1 + kinds.length) % kinds.length;
                }
                settings.update(() {
                  settings.mapKind = kinds[nextIndex];
                });
              }
            },
            child: mapWidget,
          )
        : mapWidget;

    final details = _Details(
      geo: geo,
      config: config,
      settings: settings,
      scale: _s,
      accent: _accent,
      live: live && !preview,
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (map != null && config.mapSide == MapSide.left) ...[
          map,
          SizedBox(width: 10 * _s),
        ],
        Expanded(child: details),
        if (map != null && config.mapSide == MapSide.right) ...[
          SizedBox(width: 10 * _s),
          map,
        ],
      ],
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(12 * _s, 11 * _s, 12 * _s, 11 * _s),
      child: row,
    );

    final double bgOpacity = config.stampOpacity <= 0
        ? (1.0 + config.stampOpacity) * 0.85
        : 0.85 + (config.stampOpacity * 0.15);
    final clampedOpacity = bgOpacity.clamp(0.0, 1.0);
    final bgFill = Colors.black.withValues(alpha: clampedOpacity);
    final borderStroke = Palette.glassStrokeSoft.withValues(alpha: clampedOpacity);
    final blurSigma = clampedOpacity * Blurs.panel;

    final Widget surface;
    if (preview) {
      // Cheaper surface for gallery thumbnails (no backdrop blur).
      // Use Stack to keep background opacity separate from content opacity
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(Corners.md),
        child: Stack(
          children: [
            // Opaque background layer — Positioned.fill so it matches the
            // content's size instead of forcing the Stack to be infinite.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bgFill,
                  border: Border.all(color: borderStroke),
                ),
              ),
            ),
            // Content layer (not affected by background opacity) — this is the
            // only non-positioned child, so it drives the Stack's size.
            content,
          ],
        ),
      );
    } else {
      // Use Stack to separate background opacity from content opacity
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(Corners.lg),
        child: Stack(
          children: [
            // Opaque background layer with glass effect — Positioned.fill so it
            // matches the content's size instead of forcing infinite height.
            Positioned.fill(
              child: GlassSurface(
                radius: Corners.lg,
                blur: blurSigma,
                fill: bgFill,
                stroke: borderStroke,
                padding: EdgeInsets.zero,
                child: const SizedBox.shrink(),
              ),
            ),
            // Content layer (not affected by background opacity) — the only
            // non-positioned child, so it drives the Stack's size.
            content,
          ],
        ),
      );
    }

    return surface;
  }
}

class _Details extends StatelessWidget {
  final GeoData geo;
  final TemplateConfig config;
  final SettingsController settings;
  final double scale;
  final Color accent;
  final bool live;

  const _Details({
    required this.geo,
    required this.config,
    required this.settings,
    required this.scale,
    required this.accent,
    required this.live,
  });

  bool has(StampField f) => config.has(f);

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    void section(Widget w) {
      if (lines.isNotEmpty) lines.add(_gap());
      lines.add(w);
    }

    // Header — only the user's project title / flag / numbering (no branding).
    final header = _header();
    if (header != null) lines.add(header);

    // Address (falls back to a clear "unavailable" message, never blank).
    if (has(StampField.fullAddress) || has(StampField.shortAddress)) {
      final fmt =
          has(StampField.fullAddress) ? AddressFormat.long : AddressFormat.short;
      final raw = geo.address(fmt).trim();
      final unresolved = raw.isEmpty;
      section(_line(
        unresolved ? Icons.location_off : Icons.location_on,
        unresolved ? 'Address unavailable' : raw,
        maxLines: 2,
        bold: true,
        muted: unresolved,
      ));
    }

    // Coordinates + plus code.
    if (has(StampField.latLong)) {
      section(_line(Icons.my_location, geo.coords(settings.coordFormat),
          mono: true));
    }
    if (has(StampField.plusCode)) {
      lines.add(_gap(4));
      lines.add(_line(Icons.qr_code_2, 'Plus Code  ${geo.plusCode}', mono: true));
    }

    // Date / time line (ticks live so the preview clock advances without
    // rebuilding the map or the rest of the stamp).
    if (has(StampField.dateTime)) {
      final tz = has(StampField.timeZone) ? '  ·  ${geo.timeZoneStr}' : '';
      section(
        live
            ? TickingBuilder(
                builder: (_, now) => _line(
                  Icons.schedule,
                  '${geo.dateTimeLineAt(now, settings.clock24)}$tz',
                  mono: true,
                ),
              )
            : _line(
                Icons.schedule,
                '${geo.dateTimeLine(settings.clock24)}$tz',
                mono: true,
              ),
      );
    }

    // Metric chips (only enabled + meaningful ones).
    final metrics = _metrics();
    if (metrics.isNotEmpty) {
      section(Wrap(
        spacing: 7 * scale,
        runSpacing: 6 * scale,
        children: metrics,
      ));
    }

    // Reporting extras.
    final extras = <Widget>[];
    if (has(StampField.note) && config.note.isNotEmpty) {
      extras.add(_line(Icons.notes, config.note, maxLines: 2));
    }
    if (has(StampField.personName) && config.personName.isNotEmpty) {
      extras.add(_line(Icons.person, config.personName));
    }
    if (has(StampField.contactNumber) && config.contactNumber.isNotEmpty) {
      extras.add(_line(Icons.call, config.contactNumber, mono: true));
    }
    if (extras.isNotEmpty) {
      if (lines.isNotEmpty) lines.add(_gap());
      for (var i = 0; i < extras.length; i++) {
        if (i > 0) lines.add(_gap(4));
        lines.add(extras[i]);
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  Widget _gap([double h = 7]) => SizedBox(height: h * scale);

  /// The header only renders the user's own project title, the country flag and
  /// the photo number — no app branding. Returns null when there's nothing.
  Widget? _header() {
    final title = config.projectTitle.trim();
    final showTitle = title.isNotEmpty;
    final showFlag = has(StampField.countryFlag) && geo.countryFlag.isNotEmpty;
    final showNum = has(StampField.numbering);
    if (!showTitle && !showFlag && !showNum) return null;

    return Row(
      children: [
        if (showTitle)
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.title.copyWith(
                fontSize: 12.5 * scale,
                letterSpacing: 0.2,
                color: Palette.textHi,
              ),
            ),
          ),
        if (showFlag) ...[
          if (showTitle) SizedBox(width: 6 * scale),
          Text(geo.countryFlag, style: TextStyle(fontSize: 13 * scale)),
        ],
        if (showNum) ...[
          if (showTitle || showFlag) SizedBox(width: 6 * scale) else const SizedBox.shrink(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(Corners.pill),
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Text(
              '#${config.photoNumber.toString().padLeft(3, '0')}',
              style: AppText.caption.copyWith(
                color: accent,
                fontSize: 8.5 * scale,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(IconData icon, String text,
      {int maxLines = 1, bool mono = false, bool bold = false, bool muted = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1.5 * scale),
          child: Icon(icon, size: 12.5 * scale, color: muted ? Palette.textLo : accent),
        ),
        SizedBox(width: 5 * scale),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: (mono ? AppText.metric : AppText.bodyHi).copyWith(
              fontSize: 11.5 * scale,
              height: 1.25,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              color: muted ? Palette.textMid : Palette.textHi,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _metrics() {
    final out = <Widget>[];
    void add(StampField f, IconData icon, String value) {
      if (has(f) && value.isNotEmpty && value != '—') {
        out.add(_Metric(icon: icon, value: value, scale: scale, accent: accent));
      }
    }

    add(StampField.altitude, Icons.terrain, geo.altitudeStr(settings.unitSystem));
    add(StampField.accuracy, Icons.gps_fixed, geo.accuracyStr(settings.unitSystem));
    add(StampField.compass, Icons.explore, geo.headingStr);
    add(StampField.temperature, Icons.thermostat, geo.tempStr(settings.tempUnit));
    add(StampField.magneticField, Icons.sensors, geo.magneticStr);
    add(StampField.wind, Icons.air, geo.windStr);
    add(StampField.humidity, Icons.water_drop, geo.humidityStr);
    add(StampField.pressure, Icons.speed, geo.pressureStr);
    add(StampField.speed, Icons.directions_run, geo.speedStr(settings.unitSystem));
    return out;
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final double scale;
  final Color accent;

  const _Metric({
    required this.icon,
    required this.value,
    required this.scale,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3.5 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Corners.pill),
        border: Border.all(color: Palette.glassStrokeSoft, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11 * scale, color: accent),
          SizedBox(width: 4 * scale),
          Text(
            value,
            style: AppText.metric.copyWith(
              fontSize: 10.5 * scale,
              color: Palette.textHi,
            ),
          ),
        ],
      ),
    );
  }
}
