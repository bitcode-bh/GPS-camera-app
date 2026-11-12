import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../models/geo_data.dart';

/// Why there is, or is not, a position right now.
enum GpsState {
  permissionRequired,
  permissionDenied,
  disabled,
  acquiring,
  fix,
  stale,
  unavailable,
}

class GpsStatus {
  const GpsStatus(this.state, {this.fix, this.approximate = false});

  final GpsState state;
  final GeoData? fix;

  /// The user granted approximate location only, so fixes stay coarse.
  final bool approximate;

  /// A fix ages out on its own: one that was valid is stale once its
  /// lifetime passes, even if no newer status has arrived.
  GpsState stateAt(DateTime now) =>
      state == GpsState.fix && !(fix?.hasFreshFix(now) ?? false)
      ? GpsState.stale
      : state;
}

/// Provides live fixes and says why when there are none.
class LocationService {
  LatLngLite? _geocodedAt;
  String _place = '';
  String _full = '';
  String _short = '';
  String _city = '';
  String _region = '';
  String _country = '';
  String _flag = '';
  String _iso = '';
  Position? _lastAccepted;
  bool _geocoding = false;

  static const acquireTimeout = Duration(seconds: 20);

  /// Status changes for as long as someone listens. Restarts itself when the
  /// device's location switch changes, and stops all GPS work on cancel.
  Stream<GpsStatus> watch() {
    late final StreamController<GpsStatus> out;
    StreamSubscription<Position>? positions;
    StreamSubscription<ServiceStatus>? service;
    Timer? acquiring;
    var run = 0;
    var approximate = false;

    void emit(GpsState state, [GeoData? fix]) {
      if (!out.isClosed) {
        out.add(GpsStatus(state, fix: fix, approximate: approximate));
      }
    }

    Future<void> start() async {
      final mine = ++run;
      bool current() => mine == run && !out.isClosed;
      acquiring?.cancel();
      await positions?.cancel();
      positions = null;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          if (current()) emit(GpsState.disabled);
          return;
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (!current()) return;
        if (permission == LocationPermission.deniedForever) {
          return emit(GpsState.permissionDenied);
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine) {
          return emit(GpsState.permissionRequired);
        }
        try {
          approximate =
              await Geolocator.getLocationAccuracy() ==
              LocationAccuracyStatus.reduced;
        } catch (_) {
          approximate = false;
        }
        if (!current()) return;
        emit(GpsState.acquiring);
        acquiring = Timer(acquireTimeout, () {
          if (current()) emit(GpsState.unavailable);
        });
        positions =
            Geolocator.getPositionStream(
              locationSettings: defaultTargetPlatform == TargetPlatform.android
                  ? AndroidSettings(
                      accuracy: LocationAccuracy.high,
                      intervalDuration: const Duration(seconds: 5),
                    )
                  : const LocationSettings(accuracy: LocationAccuracy.high),
            ).listen(
              (position) {
                if (!current() ||
                    !acceptsFix(position, _lastAccepted, DateTime.now())) {
                  return;
                }
                acquiring?.cancel();
                _lastAccepted = position;
                // Publish the position now. The address follows when resolved.
                emit(GpsState.fix, _toGeo(position));
                _resolveAddress(position, () {
                  if (current() && identical(position, _lastAccepted)) {
                    emit(GpsState.fix, _toGeo(position));
                  }
                });
              },
              onError: (Object error) {
                if (!current()) return;
                acquiring?.cancel();
                emit(
                  error is LocationServiceDisabledException
                      ? GpsState.disabled
                      : GpsState.unavailable,
                );
              },
            );
      } catch (_) {
        if (current()) emit(GpsState.unavailable);
      }
    }

    out = StreamController<GpsStatus>(
      onListen: () {
        start();
        try {
          service = Geolocator.getServiceStatusStream().listen(
            (_) => start(),
            onError: (Object _) {},
          );
        } catch (_) {
          // Not available on every platform.
        }
      },
      onCancel: () async {
        run++;
        acquiring?.cancel();
        await positions?.cancel();
        await service?.cancel();
        await out.close();
      },
    );
    return out.stream;
  }

  static bool acceptsFix(Position fix, Position? previous, DateTime now) {
    if (!GeoData.isFreshFix(fix.timestamp, now) ||
        !fix.latitude.isFinite ||
        fix.latitude.abs() > 90 ||
        !fix.longitude.isFinite ||
        fix.longitude.abs() > 180 ||
        !fix.accuracy.isFinite ||
        fix.accuracy <= 0) {
      return false;
    }
    if (previous == null || !GeoData.isFreshFix(previous.timestamp, now)) {
      return true;
    }
    final seconds =
        fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (seconds <= 0) return false;
    final from = LatLngLite(previous.latitude, previous.longitude);
    final to = LatLngLite(fix.latitude, fix.longitude);
    return from.distanceTo(to) <=
        seconds * 110 + previous.accuracy + fix.accuracy;
  }

  bool _hasAddressFor(LatLngLite here) =>
      _geocodedAt != null && _geocodedAt!.distanceTo(here) <= 25;

  /// Looks up the address without holding back the fix. One lookup at a time.
  Future<void> _resolveAddress(Position p, void Function() onResolved) async {
    final here = LatLngLite(p.latitude, p.longitude);
    if (_geocoding || _hasAddressFor(here)) return;
    _geocoding = true;
    try {
      _place = _full = _short = _city = _region = _country = _flag = _iso = '';
      await _reverseGeocode(p.latitude, p.longitude);
      _geocodedAt = here;
    } finally {
      _geocoding = false;
    }
    onResolved();
  }

  GeoData _toGeo(Position p) {
    // An address resolved for another place is never shown for this one.
    final known = _hasAddressFor(LatLngLite(p.latitude, p.longitude));
    String at(String value) => known ? value : '';
    return GeoData(
      lat: p.latitude,
      lon: p.longitude,
      altitude: p.altitude,
      accuracy: p.accuracy,
      heading: p.heading < 0 ? 0 : p.heading,
      speed: p.speed < 0 ? 0 : p.speed,
      // Address is left empty when it can't be resolved (the stamp then shows a
      // clear "Address unavailable" instead of masking it with coordinates).
      place: at(_place),
      fullAddress: at(_full),
      shortAddress: at(_short.isEmpty ? _place : _short),
      city: at(_city),
      region: at(_region),
      country: at(_country),
      countryFlag: at(_flag),
      isoCode: at(_iso),
      time: DateTime.now(),
      fixTime: p.timestamp,
      magneticUt: 0,
      isLive: true,
    );
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    try {
      final marks = await placemarkFromCoordinates(
        lat,
        lon,
      ).timeout(const Duration(seconds: 4));
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
        _city = p.locality ?? '';
        _region = p.administrativeArea ?? '';
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
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.userAgentHeader, 'gps_camera_next/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
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
        _short = [
          city,
          state,
          country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');
        _place = _short.isEmpty ? display : _short;
        _city = city ?? '';
        _region = state ?? '';
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
    return String.fromCharCodes(
      upper.codeUnits.map((c) => 0x1F1E6 + (c - 0x41)),
    );
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
    final dLon = ((o.lon - lon + 540) % 360 - 180) * deg2rad;
    final x = dLon * math.cos((lat + o.lat) / 2 * deg2rad);
    return earth * math.sqrt(dLat * dLat + x * x);
  }
}
