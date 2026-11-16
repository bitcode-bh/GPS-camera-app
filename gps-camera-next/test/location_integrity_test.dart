import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/location_integrity.dart';
import 'package:gps_camera_next/services/location_integrity.dart';
import 'package:gps_camera_next/services/native_location.dart';

void main() {
  final start = DateTime.utc(2026, 11, 15);
  Fix fix(
    int seconds, {
    double north = 0,
    double accuracy = 5,
    double speed = 0,
    bool mock = false,
    int? elapsed,
    int wallOffset = 0,
  }) => Fix(
    latitude: 12 + north / 111195,
    longitude: 77,
    accuracy: accuracy,
    speed: speed,
    isMock: mock,
    timestamp: start.add(Duration(seconds: seconds + wallOffset)),
    elapsedRealtimeNanos: elapsed ?? (100 + seconds) * 1000000000,
    ageAtReceipt: Duration.zero,
  );

  test('native mock and monotonic age survive the platform boundary', () {
    final raw = Fix.fromMap({
      'lat': 12.0,
      'lon': 77.0,
      'accuracy': 6.0,
      'time': start.millisecondsSinceEpoch,
      'isMock': true,
      'elapsedRealtimeNanos': 123000000000,
      'ageNanos': 250000000,
    });
    expect(raw.isMock, isTrue);
    expect(raw.ageAtReceipt, const Duration(milliseconds: 250));
    final check = LocationIntegrityMonitor(
      MotionEvidence(),
    ).check(raw, null, start);
    expect(check.state, LocationIntegrity.suspectedMock);
    expect(check.useFix, isTrue);
  });

  test('still, walking and driving fixes do not trigger spoof warnings', () {
    for (final speed in [0.0, 1.5, 30.0]) {
      final monitor = LocationIntegrityMonitor(MotionEvidence());
      Fix? previous;
      for (var second = 0; second <= 60; second += 5) {
        final current = fix(second, north: second * speed, speed: speed);
        final check = monitor.check(current, previous, current.timestamp);
        expect(
          check.state,
          LocationIntegrity.trusted,
          reason: '$speed m/s at $second',
        );
        expect(check.useFix, isTrue);
        previous = current;
      }
    }
  });

  test(
    'indoor drift, urban multipath and one jump are not called spoofing',
    () {
      final monitor = LocationIntegrityMonitor(MotionEvidence());
      final previous = fix(0);
      final poor = fix(5, north: 200, accuracy: 300);
      expect(
        monitor.check(poor, previous, poor.timestamp).state,
        isNot(LocationIntegrity.suspectedSpoofing),
      );
      final jump = fix(10, north: 10000);
      final check = monitor.check(jump, previous, jump.timestamp);
      expect(check.state, LocationIntegrity.lowAccuracy);
      expect(check.useFix, isFalse);
    },
  );

  test('repeated accurate impossible jumps are flagged and rejected', () {
    final monitor = LocationIntegrityMonitor(MotionEvidence());
    final previous = fix(0);
    for (var i = 1; i <= 3; i++) {
      final jump = fix(i * 5, north: 20000, accuracy: 1);
      final check = monitor.check(jump, previous, jump.timestamp);
      expect(check.useFix, isFalse);
      expect(
        check.state,
        i == 3
            ? LocationIntegrity.suspectedSpoofing
            : LocationIntegrity.lowAccuracy,
      );
    }
    final invalid = fix(16, accuracy: double.nan);
    expect(
      monitor.check(invalid, previous, invalid.timestamp).state,
      LocationIntegrity.suspectedSpoofing,
    );
  });

  test('a rough initial fix can recover without a spoof warning', () {
    final monitor = LocationIntegrityMonitor(MotionEvidence());
    final previous = fix(0, north: 2000, accuracy: 900);
    final current = fix(5, accuracy: 15);
    final check = monitor.check(current, previous, current.timestamp);
    expect(check.useFix, isTrue);
    expect(check.state, LocationIntegrity.trusted);
  });

  test('mock warnings require three clean fixes and survive invalid data', () {
    final monitor = LocationIntegrityMonitor(MotionEvidence());
    final mock = fix(0, mock: true);
    monitor.check(mock, null, mock.timestamp);
    final invalid = fix(1, accuracy: double.nan);
    expect(
      monitor.check(invalid, mock, invalid.timestamp).state,
      LocationIntegrity.suspectedMock,
    );
    var previous = mock;
    for (var i = 1; i <= 3; i++) {
      final current = fix(i * 5);
      expect(
        monitor.check(current, previous, current.timestamp).state,
        i == 3 ? LocationIntegrity.trusted : LocationIntegrity.suspectedMock,
      );
      previous = current;
    }
  });

  test('duplicate and conflicting clocks never advance the position', () {
    final monitor = LocationIntegrityMonitor(MotionEvidence());
    final previous = fix(0);
    expect(
      monitor.check(previous, previous, previous.timestamp).useFix,
      isFalse,
    );
    final reversed = fix(5, elapsed: 99000000000);
    expect(
      monitor.check(reversed, previous, reversed.timestamp).useFix,
      isFalse,
    );
    final changedClock = fix(5, wallOffset: 10);
    final check = monitor.check(changedClock, previous, changedClock.timestamp);
    expect(check.state, LocationIntegrity.lowAccuracy);
    expect(check.useFix, isFalse);
  });

  test('quiet IMU corroborates a jump with conflicting reported speed', () {
    final motion = MotionEvidence();
    for (var tick = 0; tick <= 100; tick++) {
      motion.add([0, 0, 9.81, 100 + tick / 20, 0]);
    }
    final jump = fix(5, north: 10000);
    final check = LocationIntegrityMonitor(
      motion,
    ).check(jump, fix(0), jump.timestamp);
    expect(check.state, LocationIntegrity.suspectedSpoofing);
    // No gyroscope, or a gap in samples, means no corroboration.
    final missingGyro = MotionEvidence()..add([0, 0, 9.81, 100]);
    expect(
      LocationIntegrityMonitor(
        missingGyro,
      ).check(jump, fix(0), jump.timestamp).state,
      LocationIntegrity.lowAccuracy,
    );
    final moving = fix(5, north: 150, speed: 30);
    expect(
      LocationIntegrityMonitor(
        motion,
      ).check(moving, fix(0, speed: 30), moving.timestamp).state,
      LocationIntegrity.trusted,
    );
  });

  test(
    'future, stale, impossible speeds and invalid raw coordinates are rejected',
    () {
      for (final current in [
        fix(-60),
        fix(6),
        fix(0, speed: 500),
        fix(0, north: double.nan),
      ]) {
        expect(
          LocationIntegrityMonitor(
            MotionEvidence(),
          ).check(current, null, start).useFix,
          isFalse,
        );
      }
    },
  );
}
