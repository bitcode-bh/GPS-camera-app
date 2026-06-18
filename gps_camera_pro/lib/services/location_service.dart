import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_data.dart';

/// Wraps geolocator + geocoding and always yields *something* renderable: a live
/// fix when permission + signal are available, otherwise a demo fix so the
/// stamp and map are never empty (e.g. on a simulator).
class LocationService {
  GeoData _last = GeoData.demo();
  LatLngLite? _geocodedAt;
  String _place = '';
  String _full = '';
  String _short = '';
  String _country = '';
  String _flag = '';
  String _iso = '';

  GeoData get last => _last;

  /// Continuous stream of fixes. Reverse-geocoding is throttled to only run when
  /// the user has moved a meaningful distance, keeping it cheap and quota-safe.
  Stream<GeoData> watch() async* {
    if (!await _ensurePermission()) {
      yield _last = GeoData.demo();
      return;
    }
    // Emit a fast first fix.
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      yield _last = await _toGeo(p);
    } catch (_) {
      yield _last = GeoData.demo();
    }

    try {
      yield* Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 2,
        ),
      ).handleError((_) {
        // Gracefully ignore stream errors to prevent crashes
      }).asyncMap((p) async {
        try {
          return _last = await _toGeo(p);
        } catch (_) {
          return _last;
        }
      });
    } catch (_) {
      yield _last;
    }
  }

  /// One-shot fix (used where a stream isn't needed).
  Future<GeoData> fetch() async {
    if (!await _ensurePermission()) return _last = GeoData.demo();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      return _last = await _toGeo(p);
    } catch (_) {
      return _last = GeoData.demo();
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<GeoData> _toGeo(Position p) async {
    final here = LatLngLite(p.latitude, p.longitude);
    if (_geocodedAt == null || _geocodedAt!.distanceTo(here) > 25) {
      await _reverseGeocode(p.latitude, p.longitude);
      _geocodedAt = here;
    }
    return GeoData(
      lat: p.latitude,
      lon: p.longitude,
      altitude: p.altitude,
      accuracy: p.accuracy,
      heading: p.heading < 0 ? 0 : p.heading,
      speed: p.speed < 0 ? 0 : p.speed,
      // Address is left empty when it can't be resolved (the stamp then shows a
      // clear "Address unavailable" instead of masking it with coordinates).
      place: _place,
      fullAddress: _full,
      shortAddress: _short.isEmpty ? _place : _short,
      country: _country,
      countryFlag: _flag,
      isoCode: _iso,
      time: DateTime.now(),
      magneticUt: 0,
      isLive: true,
    );
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lon);
      if (marks.isNotEmpty) {
        final p = marks.first;
        String j(Iterable<String?> parts) => parts
            .where((e) => e != null && e.trim().isNotEmpty)
            .map((e) => e!.trim())
            .toSet()
            .join(', ');

        _place = j([p.locality, p.administrativeArea, p.country]);
        _short = _place;
        _full = j([
          p.name,
          p.thoroughfare,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
          p.country,
        ]);
        _country = p.country ?? '';
        _iso = p.isoCountryCode ?? '';
        _flag = _flagFromIso(p.isoCountryCode);
      }
    } catch (_) {
      // platform geocoder unavailable on some devices — fall through to network
    }

    // Many budget devices have no on-device geocoder backend, so the platform
    // call returns nothing. Fall back to OpenStreetMap's Nominatim service.
    if (_full.isEmpty) {
      await _nominatim(lat, lon);
    }
  }

  Future<void> _nominatim(double lat, double lon) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
        '&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'gps_camera_pro/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final display = (json['display_name'] as String?)?.trim();
      if (display == null || display.isEmpty) return;
      _full = display;

      final addr = json['address'] as Map<String, dynamic>?;
      if (addr != null) {
        String? pick(List<String> keys) {
          for (final k in keys) {
            final v = addr[k];
            if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
          }
          return null;
        }

        final city = pick(['city', 'town', 'village', 'suburb', 'county']);
        final state = pick(['state', 'region']);
        final country = pick(['country']);
        _short = [city, state, country]
            .where((e) => e != null && e.isNotEmpty)
            .join(', ');
        _place = _short.isEmpty ? display : _short;
        _country = country ?? '';
        _iso = (addr['country_code'] as String?)?.toUpperCase() ?? '';
        _flag = _flagFromIso(_iso);
      } else {
        _place = display;
        _short = display;
      }
    } catch (_) {
      // network failed — address stays empty → stamp shows "Address unavailable"
    } finally {
      client?.close();
    }
  }

  static String _flagFromIso(String? iso) {
    if (iso == null || iso.length != 2) return '';
    final upper = iso.toUpperCase();
    return String.fromCharCodes(upper.codeUnits.map((c) => 0x1F1E6 + (c - 0x41)));
  }
}

/// A tiny lat/lon pair with an approximate metres distance (equirectangular —
/// plenty accurate for the 25 m geocode threshold).
class LatLngLite {
  final double lat;
  final double lon;
  const LatLngLite(this.lat, this.lon);

  double distanceTo(LatLngLite o) {
    const earth = 6371000.0;
    const deg2rad = 0.017453292519943295;
    final dLat = (o.lat - lat) * deg2rad;
    final dLon = (o.lon - lon) * deg2rad;
    final x = dLon * math.cos((lat + o.lat) / 2 * deg2rad);
    return earth * math.sqrt(dLat * dLat + x * x);
  }
}
