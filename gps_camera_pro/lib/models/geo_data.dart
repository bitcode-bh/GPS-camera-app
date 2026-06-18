import 'package:intl/intl.dart';

import 'coordinates.dart';

/// Address verbosity for the stamp (mirrors the reference app's long/short).
enum AddressFormat { long, short }

/// Measurement systems for altitude/speed and temperature units.
enum UnitSystem { metric, imperial }

enum TempUnit { celsius, fahrenheit }

/// A snapshot of everything a geostamp can render. Raw values only — the string
/// formatting takes the user's chosen formats so the same data can render in
/// decimal/DMS/UTM/MGRS, long/short address, °C/°F, etc.
class GeoData {
  final double lat;
  final double lon;
  final double altitude; // metres
  final double accuracy; // metres
  final double heading; // degrees 0..360
  final double speed; // m/s

  final String place; // headline: locality, admin area, country
  final String fullAddress; // detailed street address
  final String shortAddress; // locality, admin, country
  final String country;
  final String countryFlag; // emoji
  final String isoCode;

  final DateTime time;

  // Environmental probes (best-effort; default to placeholders when unwired).
  final double? temperatureC;
  final double? windKph;
  final int? humidity;
  final double? pressureHpa;
  final double magneticUt;

  /// True when the values come from the device GPS, false for the demo fallback.
  final bool isLive;

  const GeoData({
    required this.lat,
    required this.lon,
    required this.altitude,
    required this.accuracy,
    required this.heading,
    this.speed = 0,
    required this.place,
    required this.fullAddress,
    required this.shortAddress,
    required this.country,
    required this.countryFlag,
    required this.isoCode,
    required this.time,
    this.temperatureC,
    this.windKph,
    this.humidity,
    this.pressureHpa,
    this.magneticUt = 0,
    required this.isLive,
  });

  factory GeoData.demo() => GeoData(
        lat: 28.6273,
        lon: 77.3721,
        altitude: 214,
        accuracy: 2.4,
        heading: 142,
        speed: 0,
        place: 'Noida, Uttar Pradesh, India',
        fullAddress:
            'Plot 12, Sector 62 Industrial Area, Noida, Uttar Pradesh 201309, India',
        shortAddress: 'Noida, Uttar Pradesh, India',
        country: 'India',
        countryFlag: '🇮🇳',
        isoCode: 'IN',
        time: DateTime.now(),
        temperatureC: 31.0,
        windKph: 8.0,
        humidity: 54,
        pressureHpa: 1009,
        magneticUt: 41.2,
        isLive: false,
      );

  GeoData copyWith({DateTime? time, double? heading}) => GeoData(
        lat: lat,
        lon: lon,
        altitude: altitude,
        accuracy: accuracy,
        heading: heading ?? this.heading,
        speed: speed,
        place: place,
        fullAddress: fullAddress,
        shortAddress: shortAddress,
        country: country,
        countryFlag: countryFlag,
        isoCode: isoCode,
        time: time ?? this.time,
        temperatureC: temperatureC,
        windKph: windKph,
        humidity: humidity,
        pressureHpa: pressureHpa,
        magneticUt: magneticUt,
        isLive: isLive,
      );

  // ── Coordinates ──────────────────────────────────────────────────────
  String coords(CoordFormat fmt) => Coordinates.format(fmt, lat, lon);
  String get latStr => '${lat.abs().toStringAsFixed(6)}° ${lat >= 0 ? 'N' : 'S'}';
  String get lonStr => '${lon.abs().toStringAsFixed(6)}° ${lon >= 0 ? 'E' : 'W'}';
  String get plusCode => Coordinates.format(CoordFormat.plusCode, lat, lon);

  String address(AddressFormat fmt) =>
      fmt == AddressFormat.short ? shortAddress : fullAddress;

  // ── Metrics ──────────────────────────────────────────────────────────
  String altitudeStr(UnitSystem u) => u == UnitSystem.imperial
      ? '${(altitude * 3.28084).toStringAsFixed(0)} ft'
      : '${altitude.toStringAsFixed(0)} m';

  String accuracyStr(UnitSystem u) => u == UnitSystem.imperial
      ? '±${(accuracy * 3.28084).toStringAsFixed(0)} ft'
      : '±${accuracy.toStringAsFixed(1)} m';

  String speedStr(UnitSystem u) => u == UnitSystem.imperial
      ? '${(speed * 2.23694).toStringAsFixed(0)} mph'
      : '${(speed * 3.6).toStringAsFixed(0)} km/h';

  String tempStr(TempUnit u) {
    if (temperatureC == null) return '—';
    return u == TempUnit.fahrenheit
        ? '${(temperatureC! * 9 / 5 + 32).toStringAsFixed(0)}°F'
        : '${temperatureC!.toStringAsFixed(0)}°C';
  }

  String get windStr => windKph == null ? '—' : '${windKph!.toStringAsFixed(0)} km/h';
  String get humidityStr => humidity == null ? '—' : '$humidity%';
  String get pressureStr =>
      pressureHpa == null ? '—' : '${pressureHpa!.toStringAsFixed(0)} hPa';
  String get magneticStr => '${magneticUt.toStringAsFixed(1)} µT';

  String get headingStr => '${heading.toStringAsFixed(0)}° $compassDir';
  String get compassDir {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((heading % 360) / 45).round() % 8];
  }

  String get compassFacing {
    const names = [
      'North', 'North East', 'East', 'South East',
      'South', 'South West', 'West', 'North West',
    ];
    return names[((heading % 360) / 45).round() % 8];
  }

  // ── Date / time ──────────────────────────────────────────────────────
  String clock(bool h24) => DateFormat(h24 ? 'HH:mm' : 'hh:mm a').format(time);
  String get dateLong => DateFormat('d MMM yyyy').format(time);
  String get weekday => DateFormat('EEEE').format(time);

  String dateTimeLine(bool h24) => dateTimeLineAt(time, h24);

  /// Format an arbitrary instant — used so the live stamp can tick each second
  /// (and the capture can stamp the exact shutter time) without re-reading the
  /// snapshot's frozen [time].
  String dateTimeLineAt(DateTime t, bool h24) => DateFormat(
        h24 ? 'EEE, dd MMM yyyy HH:mm:ss' : 'EEE, dd MMM yyyy hh:mm:ss a',
      ).format(t);

  String get timeZoneStr {
    final o = time.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final h = o.inHours.abs().toString().padLeft(2, '0');
    final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'GMT $sign$h:$m';
  }
}
