import 'dart:math' as math;

import '../models/geo_data.dart';
import '../models/location_integrity.dart';
import 'location_service.dart';
import 'native_location.dart';

class IntegrityCheck {
  const IntegrityCheck(this.state, this.useFix, [this.reason = '']);
  final LocationIntegrity state;
  final bool useFix;
  final String reason;
}

/// Conservative evidence from the existing foreground sensor stream. A quiet
/// phone can be in a moving car: quiet sensors alone never imply spoofing.
class MotionEvidence {
  final _samples = <(double, double, double?)>[];

  void add(List<double> raw) {
    if (raw.length < 4 || raw.take(4).any((v) => !v.isFinite)) return;
    final at = raw[3];
    if (_samples.isNotEmpty && at <= _samples.last.$1) return;
    final acceleration = math.sqrt(
      raw[0] * raw[0] + raw[1] * raw[1] + raw[2] * raw[2],
    );
    final gyro = raw.length > 4 && raw[4].isFinite ? raw[4] : null;
    _samples
      ..add((at, acceleration, gyro))
      ..removeWhere((s) => at - s.$1 > 15);
  }

  bool quietDuring(Fix fix, double seconds) {
    final elapsed = fix.elapsedRealtimeNanos;
    if (elapsed == null || seconds < 2 || seconds > 10) return false;
    final end = elapsed / 1e9;
    final window = _samples
        .where((s) => s.$1 >= end - seconds && s.$1 <= end)
        .toList();
    if (window.length < 10 ||
        window.last.$1 - window.first.$1 < seconds - 0.7) {
      return false;
    }
    for (var i = 1; i < window.length; i++) {
      if (window[i].$1 - window[i - 1].$1 > 0.7) return false;
    }
    return window.every(
      (s) => (s.$2 - 9.81).abs() < 0.5 && s.$3 != null && s.$3! < 0.08,
    );
  }
}

/// Flags exposed mocks and implausible measurements. Multipath, missing
/// sensors and ordinary accuracy loss are not proof of spoofing.
class LocationIntegrityMonitor {
  LocationIntegrityMonitor(this.motion);
  final MotionEvidence motion;
  int _jumps = 0;
  int _recovery = 0;
  LocationIntegrity _held = LocationIntegrity.trusted;
  String _reason = '';

  IntegrityCheck _flag(
    LocationIntegrity state,
    String reason, {
    bool useFix = false,
  }) {
    if (state == LocationIntegrity.lowAccuracy &&
        (_held == LocationIntegrity.suspectedMock ||
            _held == LocationIntegrity.suspectedSpoofing)) {
      state = _held;
      reason = _reason;
    }
    _held = state;
    _reason = reason;
    _recovery = 0;
    return IntegrityCheck(state, useFix, reason);
  }

  IntegrityCheck check(Fix fix, Fix? previous, DateTime now) {
    // The native flag takes precedence even if the mock has invalid fields.
    if (fix.isMock) {
      return _flag(
        LocationIntegrity.suspectedMock,
        'Android mock provider',
        useFix: LocationService.acceptsFix(fix, null, now),
      );
    }
    if (!LocationService.acceptsFix(fix, null, now)) {
      return _flag(LocationIntegrity.lowAccuracy, 'Invalid or expired fix');
    }
    if (!fix.speed.isFinite || fix.speed > 110) {
      return _flag(LocationIntegrity.lowAccuracy, 'Implausible reported speed');
    }
    final age = fix.ageAtReceipt;
    if (age != null && (age.isNegative || age >= GeoData.fixLifetime)) {
      return _flag(LocationIntegrity.lowAccuracy, 'Invalid fix age');
    }
    if (previous != null &&
        !previous.isMock &&
        GeoData.isFreshFix(previous.timestamp, now)) {
      final seconds = fix.secondsSince(previous);
      // Providers can deliver the same fix twice; duplicates are not attacks.
      if (seconds == 0) return IntegrityCheck(_held, false, _reason);
      final wallSeconds =
          fix.timestamp.difference(previous.timestamp).inMicroseconds / 1e6;
      final clockConflict = seconds < 0 || (seconds - wallSeconds).abs() > 5;
      if (clockConflict) {
        return _flag(
          LocationIntegrity.lowAccuracy,
          'Inconsistent fix timestamps',
        );
      }
      final distance = LatLngLite(
        previous.latitude,
        previous.longitude,
      ).distanceTo(LatLngLite(fix.latitude, fix.longitude));
      final accurate = fix.accuracy <= 40 && previous.accuracy <= 40;
      final jump = distance > seconds * 110 + previous.accuracy + fix.accuracy;
      if (jump && accurate) {
        _jumps++;
        final speedConflict =
            fix.speed >= 0 &&
            fix.speed < 10 &&
            distance >
                seconds * (fix.speed + 30) + previous.accuracy + fix.accuracy;
        final sensorConflict = motion.quietDuring(fix, seconds);
        final suspicious = _jumps >= 3 || (speedConflict && sensorConflict);
        return _flag(
          suspicious
              ? LocationIntegrity.suspectedSpoofing
              : LocationIntegrity.lowAccuracy,
          suspicious
              ? 'Repeated or conflicting location jumps'
              : 'Location jump rejected',
        );
      }
      if (!LocationService.acceptsFix(fix, previous, now)) {
        return _flag(
          LocationIntegrity.lowAccuracy,
          'Inconsistent location update',
        );
      }
    }
    _jumps = 0;
    // Three clean fixes are needed to remove a mock/spoof warning. Do not
    // silently certify the first non-mock point after a mock provider stops.
    if (_held == LocationIntegrity.suspectedMock ||
        _held == LocationIntegrity.suspectedSpoofing) {
      if (++_recovery < 3) return IntegrityCheck(_held, true, _reason);
    }
    _held = LocationIntegrity.trusted;
    _reason = '';
    return const IntegrityCheck(LocationIntegrity.trusted, true);
  }
}
