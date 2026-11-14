import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/signal_filters.dart';
import 'package:gps_camera_next/services/native_location.dart';
import 'package:gps_camera_next/services/position_filter.dart';

const lat0 = 28.6139;
const lon0 = 77.209;
final t0 = DateTime.utc(2026, 11, 15, 10);

/// A fix [north]/[east] metres from the start, [s] seconds in.
Fix at(
  double s, {
  double north = 0,
  double east = 0,
  double accuracy = 10,
  double speed = -1,
  double heading = -1,
  double altitude = 0,
}) => Fix(
  latitude: lat0 + north / 111195,
  longitude: lon0 + east / (111195 * math.cos(lat0 * math.pi / 180)),
  accuracy: accuracy,
  speed: speed,
  heading: heading,
  altitude: altitude,
  timestamp: t0.add(Duration(milliseconds: (s * 1000).round())),
);

/// Metres between the estimate and the start point.
double offset(Fix f) {
  final n = (f.latitude - lat0) * 111195;
  final e = (f.longitude - lon0) * 111195 * math.cos(lat0 * math.pi / 180);
  return math.sqrt(n * n + e * e);
}

void main() {
  test('noisy fixes around one place average out', () {
    final filter = PositionFilter();
    final random = math.Random(7);
    var rawError = 0.0;
    var filteredError = 0.0;
    for (var i = 0; i < 60; i++) {
      // ±10 m fixes scattered about the true spot (σ ≈ 7 m per axis).
      final n = (random.nextDouble() * 2 - 1) * 12;
      final e = (random.nextDouble() * 2 - 1) * 12;
      final fix = at(i.toDouble(), north: n, east: e);
      filter.update(fix);
      if (i >= 10) {
        rawError += offset(fix);
        filteredError += offset(filter.estimate!);
      }
    }
    expect(filteredError, lessThan(rawError * 0.5));
  });

  test('a weak fix barely moves a good position, a junk one is ignored', () {
    final filter = PositionFilter();
    for (var i = 0; i < 5; i++) {
      filter.update(at(i.toDouble(), accuracy: 8));
    }
    // ±35 m fix 30 m away: used, but weighted lightly.
    expect(
      filter.update(at(5, north: 30, accuracy: 35)),
      FilterResult.accepted,
    );
    expect(offset(filter.estimate!), lessThan(6));
    // ±300 m cell-tower guess: not used at all.
    expect(
      filter.update(at(6, north: 400, accuracy: 300)),
      FilterResult.rejectedAccuracy,
    );
    expect(offset(filter.estimate!), lessThan(6));
  });

  test('a lone jump is rejected, a persistent one re-locks', () {
    final filter = PositionFilter();
    for (var i = 0; i < 5; i++) {
      filter.update(at(i.toDouble(), accuracy: 5, speed: 0));
    }
    expect(
      filter.update(at(5, north: 200, accuracy: 10)),
      FilterResult.rejectedOutlier,
    );
    expect(offset(filter.estimate!), lessThan(2));
    expect(filter.update(at(6, north: 200, accuracy: 10)).used, isFalse);
    expect(
      filter.update(at(7, north: 200, accuracy: 10)),
      FilterResult.relocked,
    );
    expect(offset(filter.estimate!), closeTo(200, 1));
  });

  test('a rough first fix gives way to the first good one', () {
    final filter = PositionFilter();
    filter.update(at(0, north: 600, accuracy: 900));
    expect(filter.update(at(1, accuracy: 12)), FilterResult.accepted);
    expect(offset(filter.estimate!), lessThan(5));
  });

  test('follows a moving car along its course', () {
    final filter = PositionFilter();
    // 15 m/s due east, a ±8 m fix every second.
    for (var i = 0; i <= 20; i++) {
      filter.update(
        at(i.toDouble(), east: 15.0 * i, accuracy: 8, speed: 15, heading: 90),
      );
    }
    final e = filter.estimate!;
    final east = (e.longitude - lon0) * 111195 * math.cos(lat0 * math.pi / 180);
    expect(east, closeTo(300, 5));
  });

  test('keeps up with walking when no speed is reported', () {
    final filter = PositionFilter();
    // 1.4 m/s north, fixes every 2 s, no speed or course from the device.
    for (var i = 0; i <= 15; i++) {
      final s = i * 2.0;
      expect(filter.update(at(s, north: 1.4 * s, accuracy: 10)).used, isTrue);
    }
    final north = (filter.estimate!.latitude - lat0) * 111195;
    expect(north, closeTo(42, 8));
  });

  test('never claims better accuracy than the device measured', () {
    final filter = PositionFilter();
    for (var i = 0; i < 30; i++) {
      filter.update(at(i.toDouble(), accuracy: 12, speed: 0));
    }
    expect(filter.estimate!.accuracy, greaterThanOrEqualTo(12));
    expect(filter.estimate!.accuracy, lessThan(13));
  });

  test('altitude is smoothed and drift speed is zeroed', () {
    final filter = PositionFilter();
    final random = math.Random(3);
    for (var i = 0; i < 40; i++) {
      filter.update(
        at(
          i.toDouble(),
          accuracy: 6,
          speed: 0.3,
          altitude: 210 + (random.nextDouble() * 2 - 1) * 15,
        ),
      );
    }
    expect(filter.estimate!.altitude, closeTo(210, 5));
    expect(filter.estimate!.speed, 0);
  });

  group('signal filters', () {
    test('low-pass smooths by time, not sample count', () {
      final fast = LowPass(1);
      final slow = LowPass(1);
      for (var i = 0; i <= 50; i++) {
        fast.add(i == 0 ? 0 : 1, Duration(milliseconds: i * 20));
      }
      for (var i = 0; i <= 5; i++) {
        slow.add(i == 0 ? 0 : 1, Duration(milliseconds: i * 200));
      }
      // Both have seen one second of a step: about the same response.
      expect(fast.value!, closeTo(slow.value!, 0.05));
      expect(fast.value!, inInclusiveRange(0.95, 1.0));
    });

    test('heading smoothing turns the short way through north', () {
      final h = HeadingLowPass(2);
      h.add(355, Duration.zero);
      final next = h.add(5, const Duration(milliseconds: 100));
      expect(next < 5 || next > 355, isTrue);
    });
  });
}
