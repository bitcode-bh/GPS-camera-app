import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/design/palette.dart';

/// Predefined geostamp styles shown in the template gallery (mirrors the
/// reference app's template set).
enum StampTemplate { advance, classic, dateTime, scanLocation, reporting, navigationCompass, weather, minimal, survey }

extension StampTemplateX on StampTemplate {
  String get title => switch (this) {
        StampTemplate.advance => 'Advanced',
        StampTemplate.classic => 'Classic',
        StampTemplate.dateTime => 'Date & Time',
        StampTemplate.scanLocation => 'Scan Location',
        StampTemplate.reporting => 'Reporting',
        StampTemplate.navigationCompass => 'Navigation',
        StampTemplate.weather => 'Weather',
        StampTemplate.minimal => 'Minimal',
        StampTemplate.survey => 'Survey',
      };

  String get blurb => switch (this) {
        StampTemplate.advance => 'Map, full address, coordinates & metrics',
        StampTemplate.classic => 'Map, address, lat/long, date & time',
        StampTemplate.dateTime => 'Minimal date, time & place',
        StampTemplate.scanLocation => 'Address with a scannable Plus Code',
        StampTemplate.reporting => 'Project header, note & contact details',
        StampTemplate.navigationCompass => 'Compass, heading, altitude & field',
        StampTemplate.weather => 'Temperature, humidity, pressure & wind',
        StampTemplate.minimal => 'Coordinates and time only — clean & compact',
        StampTemplate.survey => 'Numbering, address, lat/long & altitude',
      };

  bool get isNew => this == StampTemplate.weather || this == StampTemplate.survey;
}

/// Every toggleable line that can appear on a custom stamp.
enum StampField {
  mapType,
  shortAddress,
  fullAddress,
  countryFlag,
  latLong,
  plusCode,
  dateTime,
  timeZone,
  numbering,
  logo,
  note,
  personName,
  contactNumber,
  temperature,
  compass,
  magneticField,
  wind,
  humidity,
  pressure,
  altitude,
  accuracy,
  speed,
}

extension StampFieldX on StampField {
  String get label => switch (this) {
        StampField.mapType => 'Map',
        StampField.shortAddress => 'Short Address',
        StampField.fullAddress => 'Full Address',
        StampField.countryFlag => 'Country Flag',
        StampField.latLong => 'Coordinates',
        StampField.plusCode => 'Plus Code',
        StampField.dateTime => 'Date & Time',
        StampField.timeZone => 'Time Zone',
        StampField.numbering => 'Photo Numbering',
        StampField.logo => 'Logo',
        StampField.note => 'Note / Hashtag',
        StampField.personName => 'Person Name',
        StampField.contactNumber => 'Contact Number',
        StampField.temperature => 'Temperature',
        StampField.compass => 'Compass',
        StampField.magneticField => 'Magnetic Field',
        StampField.wind => 'Wind',
        StampField.humidity => 'Humidity',
        StampField.pressure => 'Pressure',
        StampField.altitude => 'Altitude',
        StampField.accuracy => 'Accuracy',
        StampField.speed => 'Speed',
      };

  IconData get icon => switch (this) {
        StampField.mapType => Icons.map_outlined,
        StampField.shortAddress => Icons.short_text,
        StampField.fullAddress => Icons.location_on_outlined,
        StampField.countryFlag => Icons.flag_outlined,
        StampField.latLong => Icons.my_location_outlined,
        StampField.plusCode => Icons.qr_code_2_outlined,
        StampField.dateTime => Icons.schedule_outlined,
        StampField.timeZone => Icons.public_outlined,
        StampField.numbering => Icons.tag_outlined,
        StampField.logo => Icons.image_outlined,
        StampField.note => Icons.notes_outlined,
        StampField.personName => Icons.person_outline,
        StampField.contactNumber => Icons.call_outlined,
        StampField.temperature => Icons.thermostat_outlined,
        StampField.compass => Icons.explore_outlined,
        StampField.magneticField => Icons.sensors_outlined,
        StampField.wind => Icons.air_outlined,
        StampField.humidity => Icons.water_drop_outlined,
        StampField.pressure => Icons.speed_outlined,
        StampField.altitude => Icons.terrain_outlined,
        StampField.accuracy => Icons.gps_fixed_outlined,
        StampField.speed => Icons.directions_run_outlined,
      };
}

enum StampSize { small, medium, large }

extension StampSizeX on StampSize {
  double get scale => switch (this) {
        StampSize.small => 0.9,
        StampSize.medium => 1.0,
        StampSize.large => 1.14,
      };
  String get label => name[0].toUpperCase() + name.substring(1);
}

enum StampPosition { top, bottom }

enum MapSide { left, right }

/// Accent theme for the stamp text/icons.
enum StampPalette { aurora, white, amber, mono }

extension StampPaletteX on StampPalette {
  Color get accent => switch (this) {
        StampPalette.aurora => Palette.teal,
        StampPalette.white => Colors.white,
        StampPalette.amber => Palette.warning,
        StampPalette.mono => Palette.textMid,
      };
  String get label => switch (this) {
        StampPalette.aurora => 'Aurora',
        StampPalette.white => 'White',
        StampPalette.amber => 'Amber',
        StampPalette.mono => 'Mono',
      };
}

/// The current stamp configuration — template + which fields are on + styling +
/// the user's custom text. Serializable so it survives app restarts.
class TemplateConfig {
  StampTemplate template;
  Set<StampField> fields;
  StampSize size;
  StampPosition position;
  MapSide mapSide;
  StampPalette palette;

  String projectTitle;
  String note;
  String personName;
  String contactNumber;
  int photoNumber;

  /// Overall stamp opacity (0 = transparent, 1 = fully opaque).
  double stampOpacity;

  TemplateConfig({
    required this.template,
    required this.fields,
    this.size = StampSize.medium,
    this.position = StampPosition.bottom,
    this.mapSide = MapSide.left,
    this.palette = StampPalette.aurora,
    this.projectTitle = '',
    this.note = '',
    this.personName = '',
    this.contactNumber = '',
    this.photoNumber = 1,
    this.stampOpacity = 0.0,
  });

  bool has(StampField f) => fields.contains(f);

  bool get showsMap => has(StampField.mapType);

  static const List<StampField> editableOrder = StampField.values;

  static Set<StampField> defaultsFor(StampTemplate t) {
    switch (t) {
      case StampTemplate.advance:
        return {
          StampField.mapType, StampField.fullAddress, StampField.countryFlag,
          StampField.latLong, StampField.dateTime, StampField.timeZone,
          StampField.altitude, StampField.accuracy,
        };
      case StampTemplate.classic:
        return {
          StampField.mapType, StampField.fullAddress, StampField.latLong,
          StampField.dateTime,
        };
      case StampTemplate.dateTime:
        return {StampField.shortAddress, StampField.dateTime, StampField.timeZone};
      case StampTemplate.scanLocation:
        return {
          StampField.mapType, StampField.fullAddress, StampField.plusCode,
          StampField.dateTime,
        };
      case StampTemplate.reporting:
        return {
          StampField.fullAddress, StampField.latLong, StampField.dateTime,
          StampField.note, StampField.personName, StampField.contactNumber,
          StampField.numbering,
        };
      case StampTemplate.navigationCompass:
        return {
          StampField.mapType, StampField.shortAddress, StampField.latLong,
          StampField.compass, StampField.altitude, StampField.magneticField,
          StampField.dateTime,
        };
      case StampTemplate.weather:
        return {
          StampField.shortAddress, StampField.temperature, StampField.humidity,
          StampField.pressure, StampField.wind, StampField.dateTime,
        };
      case StampTemplate.minimal:
        return {StampField.latLong, StampField.dateTime};
      case StampTemplate.survey:
        return {
          StampField.numbering, StampField.mapType, StampField.fullAddress,
          StampField.latLong, StampField.altitude, StampField.accuracy,
          StampField.dateTime,
        };
    }
  }

  factory TemplateConfig.forTemplate(StampTemplate t) =>
      TemplateConfig(template: t, fields: defaultsFor(t));

  Map<String, dynamic> toJson() => {
        'template': template.name,
        'fields': fields.map((f) => f.name).toList(),
        'size': size.name,
        'position': position.name,
        'mapSide': mapSide.name,
        'palette': palette.name,
        'projectTitle': projectTitle,
        'note': note,
        'personName': personName,
        'contactNumber': contactNumber,
        'photoNumber': photoNumber,
        'stampOpacity': stampOpacity,
      };

  static T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  factory TemplateConfig.fromJson(Map<String, dynamic> j) => TemplateConfig(
        template: _enum(StampTemplate.values, j['template'], StampTemplate.advance),
        fields: ((j['fields'] as List?) ?? [])
            .map((n) => _enum(StampField.values, n as String, StampField.dateTime))
            .toSet(),
        size: _enum(StampSize.values, j['size'], StampSize.medium),
        position: _enum(StampPosition.values, j['position'], StampPosition.bottom),
        mapSide: _enum(MapSide.values, j['mapSide'], MapSide.left),
        palette: _enum(StampPalette.values, j['palette'], StampPalette.aurora),
        projectTitle: j['projectTitle'] as String? ?? '',
        note: j['note'] as String? ?? '',
        personName: j['personName'] as String? ?? '',
        contactNumber: j['contactNumber'] as String? ?? '',
        photoNumber: j['photoNumber'] as int? ?? 1,
        stampOpacity: (j['stampOpacity'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? 0.0,
      );

  String encode() => jsonEncode(toJson());
  static TemplateConfig decode(String s) =>
      TemplateConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
