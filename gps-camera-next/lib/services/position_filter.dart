import 'dart:math' as math;

import 'native_location.dart';

/// Why [PositionFilter.update] did or did not use a fix.
enum FilterResult {
  seeded,
  accepted,

  /// The fix disagreed for several fixes in a row, so the filter re-locked on
  /// it: the phone really moved (e.g. leaving a building, a car ride).
  relocked,
  rejectedAccuracy,
  rejectedOutlier;

  bool get used => this == seeded || this == accepted || this == relocked;
}

/// Kalman filter over the device's fixes, so the stamp's position is steadier
/// and closer to the truth than any single fix.
///
/// Two position states (east and north metres from the first fix) with one
/// shared variance. Each fix is weighted by its reported accuracy: a ±5 m fix
/// pulls hard and a ±35 m fix barely nudges, so the indoor mix of Wi-Fi and
/// weak GPS fixes averages instead of jumping. Between fixes the estimate
/// moves along the fix's own course when that is trustworthy (≥ 3 m/s, from
/// a fix of ±[motionMaxAccuracy] or better), and
/// otherwise its uncertainty grows with the distance it could have travelled.
///
/// Guards, adapted from the Trip Tracker position estimator:
/// * Accuracy gate: fixes worse than [maxUsableAccuracy] are ignored unless
///   no fix was used for [starvedAfter]; then they re-enter, weighted lightly.
/// * Outlier gate: a fix far outside the combined uncertainty is a jump or
///   multipath, and is ignored. [relockAfter] such fixes in a row mean the
///   phone moved, and the filter re-locks on the new place.
/// * Standstill hold: while the phone reports being still, fixes near the
///   estimate are weighted lightly, so the position does not wander.
///
/// The reported accuracy is never better than the best fix used in the last
/// [bestFixWindow]: averaging helps the position, but the stamp should not
/// claim more than the device measured.
class PositionFilter {
  // Local plane, anchored at the first fix.
  double _anchorLat = double.nan;
  double _anchorLon = double.nan;
  double _cosAnchor = 1;
  double _x = 0; // east, m
  double _y = 0; // north, m
  double _p = 0; // variance per axis, m²

  double _altitude = double.nan;
  double _altitudeVar = 0;

  Fix? _last; // the last fix used
  DateTime? _lastUsedAt;
  int _rejectedInRow = 0;
  // Accuracy of each fix used in the last [bestFixWindow].
  final _recent = <(DateTime, double)>[];

  bool get ready => !_anchorLat.isNaN;

  void reset() {
    _anchorLat = _anchorLon = _altitude = double.nan;
    _x = _y = _p = _altitudeVar = 0;
    _last = null;
    _lastUsedAt = null;
    _rejectedInRow = 0;
    _recent.clear();
  }

  /// Feeds one fix. When the result is [FilterResult.used], [estimate] is the
  /// new filtered position.
  FilterResult update(Fix fix) {
    final at = fix.timestamp;
    final accuracy = fix.accuracy.isFinite && fix.accuracy > 0
        ? fix.accuracy
        : defaultAccuracy;
    final last = _last;
    if (!ready || last == null) return _seed(fix, accuracy);

    final dt = fix.secondsSince(last);
    if (dt <= 0) return FilterResult.rejectedOutlier;
    final starved = at.difference(_lastUsedAt ?? at) > starvedAfter;
    if (accuracy > maxUsableAccuracy && !starved) {
      return FilterResult.rejectedAccuracy;
    }

    // Predict to this fix's time, without touching the saved state until the
    // fix is used: a rejected fix must leave the estimate as it was.
    var (x, y, p) = _predict(last, dt);

    final (gx, gy) = _toLocal(fix.latitude, fix.longitude);
    final ex = gx - x;
    final ey = gy - y;
    final distance = math.sqrt(ex * ex + ey * ey);
    // Reported accuracy is a 68 % radius, so per axis σ ≈ accuracy / √2.
    var r = (accuracy * accuracy / 2).clamp(minR, maxR);

    final gate = math.max(gateSigma * math.sqrt(p + r), minGate);
    if (distance > gate && !starved) {
      if (++_rejectedInRow < relockAfter) return FilterResult.rejectedOutlier;
      _relock(fix, accuracy, gx, gy);
      return FilterResult.relocked;
    }
    _rejectedInRow = 0;

    // Standstill: fixes close to the estimate are noise around a place that
    // is not moving. Only when the device reports a speed at all.
    if (fix.speed >= 0 &&
        fix.speed < stationarySpeed &&
        accuracy <= motionMaxAccuracy &&
        distance < math.max(holdFactor * accuracy, minHold)) {
      r *= stationaryWeight;
    }

    final k = p / (p + r);
    x += k * ex;
    y += k * ey;
    p *= 1 - k;
    _x = x;
    _y = y;
    _p = p;
    _updateAltitude(fix, accuracy, dt);
    _used(fix, accuracy);
    return FilterResult.accepted;
  }

  /// The filtered position as a fix: the last used fix with its place,
  /// altitude and accuracy replaced. Null before the first fix.
  Fix? get estimate {
    final last = _last;
    if (!ready || last == null) return null;
    final lat = _anchorLat + _y / earthRadius * _radToDeg;
    final lon = _anchorLon + _x / (earthRadius * _cosAnchor) * _radToDeg;
    final best = _recent.isEmpty
        ? 0.0
        : _recent.map((r) => r.$2).reduce(math.min);
    return Fix(
      latitude: lat,
      longitude: ((lon + 540) % 360) - 180,
      altitude: _altitude.isNaN ? last.altitude : _altitude,
      accuracy: math.max(math.sqrt(2 * _p), best),
      // Drift: a phone at rest still reports a creeping speed.
      speed: last.speed >= 0 && last.speed < driftSpeed ? 0 : last.speed,
      heading: last.heading,
      timestamp: last.timestamp,
      isMock: last.isMock,
      elapsedRealtimeNanos: last.elapsedRealtimeNanos,
      ageAtReceipt: last.ageAtReceipt,
    );
  }

  FilterResult _seed(Fix fix, double accuracy) {
    _anchorLat = fix.latitude;
    _anchorLon = fix.longitude;
    _cosAnchor = math.max(math.cos(fix.latitude * _degToRad), 0.01);
    _x = _y = 0;
    _p = accuracy * accuracy / 2;
    _altitude = double.nan;
    _updateAltitude(fix, accuracy, 0);
    _rejectedInRow = 0;
    _used(fix, accuracy);
    return FilterResult.seeded;
  }

  void _relock(Fix fix, double accuracy, double gx, double gy) {
    _x = gx;
    _y = gy;
    _p = accuracy * accuracy / 2;
    _altitude = double.nan;
    _updateAltitude(fix, accuracy, 0);
    _rejectedInRow = 0;
    // Accuracy from before the move says nothing about the new place.
    _recent.clear();
    _used(fix, accuracy);
  }

  void _used(Fix fix, double accuracy) {
    _last = fix;
    _lastUsedAt = fix.timestamp;
    _recent
      ..add((fix.timestamp, accuracy))
      ..removeWhere((r) => fix.timestamp.difference(r.$1) > bestFixWindow);
  }

  /// Position and variance moved on by [seconds] from the last used fix.
  (double, double, double) _predict(Fix last, double seconds) {
    var x = _x;
    var y = _y;
    var p = _p;
    final dt = math.min(seconds, maxPredict.inMilliseconds / 1000);
    // Speed and course from a weak fix are noise: indoors a phone lying still
    // reports 2–3 m/s from ±25 m fixes. Treat them as unknown.
    final v = last.accuracy <= motionMaxAccuracy ? last.speed : -1.0;
    if (v >= stationarySpeed) {
      // A fix's course is only meaningful at speed (3 m/s ramping to 8 m/s);
      // the untrusted share of the motion becomes uncertainty instead.
      final trust = last.heading >= 0
          ? ((v - courseTrustFrom) / (courseTrustFull - courseTrustFrom)).clamp(
              0.0,
              1.0,
            )
          : 0.0;
      final h = last.heading * _degToRad;
      x += v * trust * math.sin(h) * dt;
      y += v * trust * math.cos(h) * dt;
      p += (qBase + qPerSpeed * v) * dt + (1 - trust) * v * v * dt * dt;
    } else if (v >= 0) {
      p += qStill * dt;
    } else {
      // No speed reported (common indoors): allow walking pace.
      p += qBase * dt + walkingSpeed * walkingSpeed * dt * dt;
    }
    // Cap the growth, never the starting point: a rough seed stays rough.
    final cap = math.max(_p, maxVariance);
    if (seconds > dt) p = cap;
    return (x, y, math.min(p, cap));
  }

  /// Altitude: a scalar Kalman filter. GPS altitude is noisier than the
  /// horizontal position, so it is weighted at 1.5× the horizontal accuracy.
  void _updateAltitude(Fix fix, double accuracy, double dt) {
    if (!fix.altitude.isFinite || fix.altitude == 0) return;
    final r = math.pow(accuracy * 1.5, 2).toDouble();
    if (_altitude.isNaN) {
      _altitude = fix.altitude;
      _altitudeVar = r;
      return;
    }
    final p = _altitudeVar + qAltitude * dt;
    final k = p / (p + r);
    _altitude += k * (fix.altitude - _altitude);
    _altitudeVar = p * (1 - k);
  }

  (double, double) _toLocal(double lat, double lon) {
    final dLon = ((lon - _anchorLon + 540) % 360) - 180;
    return (
      dLon * _degToRad * earthRadius * _cosAnchor,
      (lat - _anchorLat) * _degToRad * earthRadius,
    );
  }

  static const earthRadius = 6371000.0;
  static const _degToRad = math.pi / 180;
  static const _radToDeg = 180 / math.pi;

  // Process noise, m² per second.
  static const qBase = 0.5;
  static const qPerSpeed = 0.35;
  static const qStill = 0.05;
  static const qAltitude = 0.5;
  static const walkingSpeed = 1.5; // m/s
  static const maxVariance = 10000.0; // ≈ ±140 m
  static const maxPredict = Duration(seconds: 30);

  // Measurement noise per axis, m².
  static const minR = 4.5; // ≈ ±3 m: phones are optimistic below that
  static const maxR = 5000.0; // ≈ ±100 m
  static const defaultAccuracy = 20.0;

  // Gates.
  static const maxUsableAccuracy = 40.0;
  static const starvedAfter = Duration(seconds: 15);
  static const gateSigma = 3.5;
  static const minGate = 15.0; // never tighter than urban multipath
  static const relockAfter = 3;
  static const stationarySpeed = 0.7; // m/s

  /// Speed and course are only trusted from fixes this accurate, in metres.
  static const motionMaxAccuracy = 20.0;
  static const driftSpeed = 0.5; // m/s
  static const courseTrustFrom = 3.0; // m/s: above walking pace
  static const courseTrustFull = 8.0; // m/s: ≈ 29 km/h
  static const holdFactor = 2.0;
  static const minHold = 10.0;
  static const stationaryWeight = 10.0;
  static const bestFixWindow = Duration(seconds: 20);
}
