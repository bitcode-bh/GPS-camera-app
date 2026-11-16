import 'dart:async';
import 'dart:math' as math;

import 'native.dart';
import 'native_location.dart';
import 'position_filter.dart';
import 'location_integrity.dart';

import '../models/geo_data.dart';
import '../models/location_integrity.dart';

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
  const GpsStatus(
    this.state, {
    this.fix,
    this.approximate = false,
    this.integrity = LocationIntegrity.trusted,
    this.integrityReason = '',
    this.rawFix,
  });

  final GpsState state;
  final GeoData? fix;
  final LocationIntegrity integrity;
  final String integrityReason;
  final Fix? rawFix;

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
  final motion = MotionEvidence();
  late final _integrity = LocationIntegrityMonitor(motion);
  LatLngLite? _geocodedAt;
  String _place = '';
  String _full = '';
  String _short = '';
  String _city = '';
  String _region = '';
  String _country = '';
  String _flag = '';
  String _iso = '';
  Fix? _lastAccepted;
  Fix? _lastEstimate;
  Fix? _estimateRaw;
  bool _geocoding = false;

  static const acquireTimeout = Duration(seconds: 20);

  /// Status changes for as long as someone listens. Restarts itself when the
  /// device's location switch changes, and stops all GPS work on cancel.
  /// [ask] shows the system permission prompt when needed. Pass false to
  /// only report that permission is required (no prompt).
  Stream<GpsStatus> watch({bool ask = true}) {
    late final StreamController<GpsStatus> out;
    StreamSubscription<Fix>? positions;
    StreamSubscription<bool>? service;
    Timer? acquiring;
    var run = 0;
    var approximate = false;
    var check = const IntegrityCheck(LocationIntegrity.trusted, false);
    Fix? rawFix;
    var revision = 0;

    void emit(GpsState state, [GeoData? fix]) {
      if (!out.isClosed) {
        out.add(
          GpsStatus(
            state,
            fix: fix,
            approximate: approximate,
            integrity: check.state,
            integrityReason: check.reason,
            rawFix: rawFix,
          ),
        );
      }
    }

    Future<void> start() async {
      final mine = ++run;
      bool current() => mine == run && !out.isClosed;
      acquiring?.cancel();
      await positions?.cancel();
      positions = null;
      try {
        var access = await NativeLocation.access();
        if (!access.serviceEnabled) {
          if (current()) emit(GpsState.disabled);
          return;
        }
        if (access.permit == LocationPermit.denied && ask) {
          access = await NativeLocation.request();
        }
        if (!current()) return;
        if (access.permit == LocationPermit.deniedForever) {
          return emit(GpsState.permissionDenied);
        }
        if (access.permit != LocationPermit.granted) {
          return emit(GpsState.permissionRequired);
        }
        approximate = access.approximate;
        emit(GpsState.acquiring);
        acquiring = Timer(acquireTimeout, () {
          if (current()) emit(GpsState.unavailable);
        });
        // A fresh filter per run: a restart may follow a long pause.
        final filter = PositionFilter();
        final integrity = _integrity;
        _lastAccepted = null;
        _lastEstimate = null;
        _estimateRaw = null;
        positions = NativeLocation.positions().listen(
          (position) {
            final now = DateTime.now();
            if (!current()) return;
            final sample = ++revision;
            rawFix = position;
            check = integrity.check(position, _lastAccepted, now);
            if (!check.useFix) {
              emit(
                GpsState.fix,
                _lastEstimate == null ? null : _toGeo(_lastEstimate!),
              );
              return;
            }
            if (position.isMock || _lastAccepted?.isMock == true) {
              filter.reset();
            }
            _lastAccepted = position;
            final result = filter.update(position);
            if (!result.used) {
              check = IntegrityCheck(
                check.state == LocationIntegrity.trusted
                    ? LocationIntegrity.lowAccuracy
                    : check.state,
                false,
                result == FilterResult.rejectedAccuracy
                    ? 'Weak GPS signal'
                    : 'GPS outlier rejected',
              );
              emit(
                GpsState.fix,
                _lastEstimate == null ? null : _toGeo(_lastEstimate!),
              );
              return;
            }
            final estimate = filter.estimate!;
            acquiring?.cancel();
            _lastEstimate = estimate;
            _estimateRaw = position;
            // Publish the position now. The address follows when resolved.
            emit(GpsState.fix, _toGeo(estimate));
            _resolveAddress(estimate, () {
              if (current() &&
                  sample == revision &&
                  identical(estimate, _lastEstimate)) {
                emit(GpsState.fix, _toGeo(estimate));
              }
            });
          },
          onError: (Object error) {
            if (!current()) return;
            acquiring?.cancel();
            emit(
              error is LocationDisabled
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
          // Android also broadcasts internal provider changes; restart only
          // when the location switch itself flips, or the fix is lost.
          bool? enabled;
          service = NativeLocation.switchChanges().listen((on) {
            if (on == enabled) return;
            final first = enabled == null;
            enabled = on;
            if (!first || !on) start();
          }, onError: (Object _) {});
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

  static bool acceptsFix(Fix fix, Fix? previous, DateTime now) {
    if (!GeoData.isFreshFix(fix.timestamp, now) ||
        (fix.ageAtReceipt != null &&
            (fix.ageAtReceipt!.isNegative ||
                fix.ageAtReceipt! >= GeoData.fixLifetime)) ||
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
    final seconds = fix.secondsSince(previous);
    if (seconds <= 0) return false;
    // A clearly more accurate fix is trusted over a rough one (e.g. a cell
    // tower guess), or one bad first fix would lock out every good one.
    if (fix.accuracy * 2 <= previous.accuracy) return true;
    final from = LatLngLite(previous.latitude, previous.longitude);
    final to = LatLngLite(fix.latitude, fix.longitude);
    return from.distanceTo(to) <=
        seconds * 110 + previous.accuracy + fix.accuracy;
  }

  bool _hasAddressFor(LatLngLite here) =>
      _geocodedAt != null && _geocodedAt!.distanceTo(here) <= 25;

  /// Looks up the address without holding back the fix. One lookup at a time.
  Future<void> _resolveAddress(Fix p, void Function() onResolved) async {
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

  GeoData _toGeo(Fix p) {
    // An address resolved for another place is never shown for this one.
    final known = _hasAddressFor(LatLngLite(p.latitude, p.longitude));
    String at(String value) => known ? value : '';
    return GeoData(
      lat: p.latitude,
      lon: p.longitude,
      altitude: p.altitude.isFinite ? p.altitude : 0,
      accuracy: p.accuracy,
      heading: p.heading.isFinite && p.heading >= 0 ? p.heading : 0,
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
      rawLat: _estimateRaw?.latitude,
      rawLon: _estimateRaw?.longitude,
      rawAccuracy: _estimateRaw?.accuracy,
      magneticUt: 0,
      isLive: true,
    );
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    try {
      final p = await Native.geocode(
        lat,
        lon,
      ).timeout(const Duration(seconds: 4));
      if (p != null) {
        String j(Iterable<String?> parts) => parts
            .where((e) => e != null && e.trim().isNotEmpty)
            .map((e) => e!.trim())
            .toSet()
            .join(', ');

        _place = j([p['locality'], p['administrativeArea'], p['country']]);
        _short = _place;
        _full = j([
          p['name'],
          p['thoroughfare'],
          p['subLocality'],
          p['locality'],
          p['administrativeArea'],
          p['postalCode'],
          p['country'],
        ]);
        _city = p['locality'] ?? '';
        _region = p['administrativeArea'] ?? '';
        _country = p['country'] ?? '';
        _iso = p['isoCountryCode'] ?? '';
        _flag = _flagFromIso(p['isoCountryCode']);
      }
    } catch (_) {
      // No on-device geocoder (some budget phones). The stamp then shows
      // coordinates without an address. A public geocoder is deliberately not
      // used: OpenStreetMap's Nominatim policy forbids automatic, periodic app
      // lookups, and any paid geocoder must allow storing results, since an
      // address burned into a photo is stored.
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
