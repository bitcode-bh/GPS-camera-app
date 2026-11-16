import 'package:flutter/material.dart';

import '../core/design/palette.dart';
import '../core/design/text_styles.dart';
import '../core/design/tokens.dart';
import '../core/widgets/ticking_builder.dart';
import '../models/geo_data.dart';
import '../models/location_integrity.dart';
import '../models/map_kind.dart';
import '../models/template.dart';
import '../state/settings_controller.dart';
import 'mini_map.dart';
import 'map_credits.dart';

const _stampShadows = [
  Shadow(color: Color(0x66000000), blurRadius: 1, offset: Offset(0, .5)),
];

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

  /// A saved stamp must render independently of the live camera texture.
  final bool forCapture;

  /// While recording, the stamp on screen is what the video carries.
  final bool recording;

  /// When false the mini-map renders as a painted placeholder instead of a live
  /// tile map — used by the small previews to avoid many map engines at once.
  final bool realMap;

  /// Callback when the mini-map is tapped (not active in preview)
  final VoidCallback? onMapTap;

  const GeoStamp({
    super.key,
    required this.geo,
    required this.config,
    required this.settings,
    this.preview = false,
    this.live = true,
    this.forCapture = false,
    this.recording = false,
    this.realMap = true,
    this.onMapTap,
  });

  double get _s => config.size.scale * (preview ? 0.82 : 1.0);
  Color get _accent => config.palette.accent;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: config.width,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _surface(context, constraints.maxWidth),
      ),
    );
  }

  Widget _surface(BuildContext context, double availableWidth) {
    if (geo.hasLocation && config.showsMap && MapTiles.available && realMap) {
      return MapCreditsBuilder(
        kind: settings.mapKind,
        builder: (context, credit) => _content(context, availableWidth, credit),
      );
    }
    return _content(context, availableWidth, null);
  }

  Widget _content(BuildContext context, double availableWidth, String? credit) {
    final hasRealMap =
        geo.hasLocation && config.showsMap && MapTiles.available && realMap;
    final creditStyle = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: 9 * _s,
        height: 1.15,
        color: Colors.white,
        shadows: _stampShadows,
      ),
    );
    final creditHeight = 64 * _s;
    final creditLayout = TextPainter(
      text: TextSpan(text: credit ?? '', style: creditStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: availableWidth);
    // Never export uncredited imagery or clip provider names. Reserve the same
    // credit area before/after metadata arrives so camera controls cannot shift.
    final creditFits = credit != null && creditLayout.height <= creditHeight;
    creditLayout.dispose();
    final mapWidth = (136 * _s * config.mapSize.scale).clamp(
      0.0,
      availableWidth * 0.45,
    );
    final spacing = _s * config.spacing.scale;
    final mapWidget = geo.hasLocation && config.showsMap && MapTiles.available
        ? SizedBox(
            width: mapWidth,
            height: mapWidth * (118 / 136),
            child: MiniMap(
              lat: geo.lat,
              lon: geo.lon,
              heading: geo.heading,
              kind: settings.mapKind,
              zoom: settings.mapZoom,
              accent: _accent,
              radius: Corners.xs,
              compact: preview,
              showHints: !forCapture && !recording,
              realMap: realMap,
              allowTiles: creditFits,
            ),
          )
        : null;

    double mapDragDy = 0;
    final map = (mapWidget != null && onMapTap != null)
        ? Semantics(
            label: 'Open location map',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMapTap,
              // No horizontal-drag handlers here: a horizontal swipe on the map
              // must fall through to the parent stamp's pan handler, which toggles
              // the map side (left ↔ right). Vertical drag still cycles map style.
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
                    nextIndex =
                        (currentIndex - 1 + kinds.length) % kinds.length;
                  }
                  settings.update(() {
                    settings.mapKind = kinds[nextIndex];
                  });
                }
              },
              child: IgnorePointer(child: mapWidget),
            ),
          )
        : mapWidget;

    final details = _Details(
      geo: geo,
      config: config,
      settings: settings,
      scale: _s,
      accent: _accent,
      live: live && !preview && !forCapture,
    );

    final row = Row(
      key: const ValueKey('geostamp-row'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (map != null && config.mapSide == MapSide.left) ...[
          map,
          SizedBox(width: 10 * spacing),
        ],
        Expanded(child: details),
        if (map != null && config.mapSide == MapSide.right) ...[
          SizedBox(width: 10 * spacing),
          map,
        ],
      ],
    );

    final warning =
        geo.integrity != LocationIntegrity.trusted &&
        geo.integrity != LocationIntegrity.unavailable;
    final notice = warning
        ? Text(
            key: ValueKey(geo.integrity),
            [
              geo.integrity.warning,
              if (geo.hasLocation) geo.accuracyStr(settings.unitSystem),
              if (geo.locationNote.isNotEmpty) geo.locationNote,
            ].join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10 * _s,
              height: 1.2,
              color: const Color(0xFFFFD180),
              fontWeight: FontWeight.w600,
              shadows: _stampShadows,
            ),
          )
        : const SizedBox.shrink();

    return IconTheme.merge(
      data: const IconThemeData(shadows: _stampShadows),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep unused credit space above the visible stamp, never below it.
          if (hasRealMap)
            SizedBox(
              key: const ValueKey('geostamp-map-credits'),
              height: creditHeight,
              width: double.infinity,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  creditFits
                      ? credit
                      : 'Map unavailable: full credits could not be displayed.',
                  style: creditStyle,
                ),
              ),
            ),
          // Reserve the warning area: GPS status never moves the stamp row.
          SizedBox(
            key: const ValueKey('geostamp-notice'),
            height:
                MediaQuery.textScalerOf(context).scale(10 * _s) * 3.6 + 4 * _s,
            width: double.infinity,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: 4 * _s),
                // Captures must include a new integrity warning immediately.
                child: forCapture || recording
                    ? notice
                    : AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.bottomLeft,
                          children: [...previous, ?current],
                        ),
                        child: notice,
                      ),
              ),
            ),
          ),
          row,
        ],
      ),
    );
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

    final details = <StampField, Widget>{};
    if (!geo.hasLocation) {
      section(_line(Icons.location_off, 'GPS unavailable', muted: true));
    } else {
      if (has(StampField.fullAddress) || has(StampField.shortAddress)) {
        final full = has(StampField.fullAddress);
        final raw = geo
            .address(full ? AddressFormat.long : AddressFormat.short)
            .trim();
        details[full
            ? StampField.fullAddress
            : StampField.shortAddress] = _line(
          raw.isEmpty ? Icons.location_off : Icons.location_on,
          raw.isEmpty ? 'Address unavailable' : raw,
          maxLines: 2,
          bold: true,
          muted: raw.isEmpty,
        );
      }
      for (final (field, value) in [
        (StampField.city, geo.city),
        (StampField.region, geo.region),
        (StampField.country, geo.country),
      ]) {
        if (has(field) && value.trim().isNotEmpty) {
          details[field] = _line(field.icon, value);
        }
      }
      if (has(StampField.latLong)) {
        details[StampField.latLong] = _line(
          Icons.my_location,
          '${geo.coords(settings.coordFormat)}${config.template == StampTemplate.minimal && has(StampField.accuracy) ? ' · ${geo.accuracyStr(settings.unitSystem)}' : ''}',
          mono: true,
        );
      }
      if (has(StampField.plusCode)) {
        details[StampField.plusCode] = _line(
          Icons.qr_code_2,
          'Plus Code  ${geo.plusCode}',
          mono: true,
        );
      }
    }

    if (has(StampField.dateTime)) {
      final tz = has(StampField.timeZone) ? '  ·  ${geo.timeZoneStr}' : '';
      Widget clock(DateTime time) => _line(
        Icons.schedule,
        '${geo.dateTimeLineAt(time, settings.clock24)}$tz',
        mono: true,
      );
      details[StampField.dateTime] = live
          ? TickingBuilder(builder: (_, now) => clock(now))
          : clock(geo.time);
    }

    final metrics = geo.hasLocation ? _metrics() : const <StampField, Widget>{};
    if (metrics.isNotEmpty) {
      if (config.fieldOrder.isEmpty) {
        details[metrics.keys.first] = Wrap(
          spacing: 7 * scale,
          runSpacing: 6 * scale,
          children: metrics.values.toList(),
        );
      } else {
        details.addAll(metrics);
      }
    }

    for (final (field, value, maxLines) in [
      (
        StampField.siteId,
        config.siteId.trim().isEmpty ? '' : 'Site ${config.siteId}',
        1,
      ),
      (StampField.remarks, config.remarks, 2),
      (StampField.note, config.note, 2),
      (StampField.personName, config.personName, 1),
      (StampField.contactNumber, config.contactNumber, 1),
    ]) {
      if (has(field) && value.trim().isNotEmpty) {
        details[field] = _line(
          field.icon,
          value,
          maxLines: maxLines,
          mono: field == StampField.contactNumber,
        );
      }
    }

    for (final field in config.orderedDetails) {
      final detail = details[field];
      if (detail != null) section(detail);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  Widget _gap([double h = 7]) => SizedBox(
    height:
        (config.template == StampTemplate.minimal ? 3 : h) *
        scale *
        config.spacing.scale,
  );

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
                shadows: _stampShadows,
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
          if (showTitle || showFlag)
            SizedBox(width: 6 * scale)
          else
            const SizedBox.shrink(),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 6 * scale,
              vertical: 1.5 * scale,
            ),
            child: Text(
              '#${config.photoNumber.toString().padLeft(3, '0')}',
              style: AppText.caption.copyWith(
                shadows: _stampShadows,
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

  Widget _line(
    IconData icon,
    String text, {
    int maxLines = 1,
    bool mono = false,
    bool bold = false,
    bool muted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (config.template != StampTemplate.minimal) ...[
          Padding(
            padding: EdgeInsets.only(top: 1.5 * scale),
            child: Icon(
              icon,
              size: 12.5 * scale,
              color: muted ? Palette.textLo : accent,
            ),
          ),
          SizedBox(width: 5 * scale),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: (mono ? AppText.metric : AppText.bodyHi).copyWith(
              shadows: _stampShadows,
              fontSize: 11.5 * scale,
              height: 1.25,
              fontWeight: bold || config.boldText
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: muted
                  ? Palette.textMid
                  : (config.accentText ? accent : Palette.textHi),
            ),
          ),
        ),
      ],
    );
  }

  Map<StampField, Widget> _metrics() {
    final out = <StampField, Widget>{};
    void add(StampField f, IconData icon, String value) {
      if (config.template == StampTemplate.minimal &&
          f == StampField.accuracy &&
          has(StampField.latLong)) {
        return;
      }
      if (has(f) && value.isNotEmpty && value != '—') {
        out[f] = _Metric(
          icon: icon,
          value: value,
          scale: scale,
          accent: accent,
        );
      }
    }

    add(
      StampField.altitude,
      Icons.terrain,
      geo.altitudeStr(settings.unitSystem),
    );
    add(
      StampField.accuracy,
      Icons.gps_fixed,
      geo.accuracyStr(settings.unitSystem),
    );
    add(StampField.compass, Icons.explore, geo.headingStr);
    add(
      StampField.temperature,
      Icons.thermostat,
      geo.tempStr(settings.tempUnit),
    );
    add(StampField.magneticField, Icons.sensors, geo.magneticStr);
    add(StampField.wind, Icons.air, geo.windStr);
    add(StampField.humidity, Icons.water_drop, geo.humidityStr);
    add(StampField.pressure, Icons.speed, geo.pressureStr);
    add(
      StampField.speed,
      Icons.directions_run,
      geo.speedStr(settings.unitSystem),
    );
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
      padding: EdgeInsets.symmetric(
        horizontal: 7 * scale,
        vertical: 3.5 * scale,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11 * scale, color: accent),
          SizedBox(width: 4 * scale),
          Text(
            value,
            style: AppText.metric.copyWith(
              shadows: _stampShadows,
              fontSize: 10.5 * scale,
              color: Palette.textHi,
            ),
          ),
        ],
      ),
    );
  }
}
