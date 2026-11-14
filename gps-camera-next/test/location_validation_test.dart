import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/services/location_service.dart';
import 'package:gps_camera_next/services/native_location.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9);
  Fix fix(
    int seconds, {
    double lat = 12,
    double lon = 77,
    double accuracy = 5,
  }) => Fix(
    latitude: lat,
    longitude: lon,
    timestamp: now.add(Duration(seconds: seconds)),
    accuracy: accuracy,
  );

  test('accepts a fresh fix and rejects stale, future and invalid data', () {
    expect(LocationService.acceptsFix(fix(-2), null, now), isTrue);
    expect(LocationService.acceptsFix(fix(-60), null, now), isFalse);
    expect(LocationService.acceptsFix(fix(6), null, now), isFalse);
    expect(
      LocationService.acceptsFix(fix(0, accuracy: double.nan), null, now),
      isFalse,
    );
    expect(LocationService.acceptsFix(fix(0, lat: 91), null, now), isFalse);
  });

  test('rejects out-of-order fixes and implausible location jumps', () {
    expect(LocationService.acceptsFix(fix(-5), fix(-4), now), isFalse);
    expect(LocationService.acceptsFix(fix(0, lat: 13), fix(-5), now), isFalse);
    expect(
      LocationService.acceptsFix(fix(0, lat: 12.0001), fix(-5), now),
      isTrue,
    );
  });

  test('crossing the antimeridian does not look like a jump', () {
    expect(
      LocationService.acceptsFix(
        fix(0, lon: -179.9999),
        fix(-5, lon: 179.9999),
        now,
      ),
      isTrue,
    );
  });

  test('demo locations are never fresh device fixes', () {
    expect(GeoData.demo().hasFreshFix(now), isFalse);
  });

  test('a weak fix does not replace a recent better one', () {
    final good = fix(-5, accuracy: 10);
    // 13 s later a 200 m fix arrives: keep the 10 m fix.
    expect(
      LocationService.isBetterFix(
        fix(13, accuracy: 200),
        good,
        now.add(const Duration(seconds: 13)),
      ),
      isFalse,
    );
    // A fix at least as accurate always wins, and so does a comparable one,
    // which keeps a good position fresh.
    expect(LocationService.isBetterFix(fix(0, accuracy: 9), good, now), isTrue);
    expect(
      LocationService.isBetterFix(fix(0, accuracy: 15), good, now),
      isTrue,
    );
    expect(
      LocationService.isBetterFix(fix(0, accuracy: 40), good, now),
      isFalse,
    );
    // Once the good fix is over 20 s old, the newest fix wins, weak or not.
    expect(
      LocationService.isBetterFix(
        fix(16, accuracy: 200),
        good,
        now.add(const Duration(seconds: 16)),
      ),
      isTrue,
    );
    expect(
      LocationService.isBetterFix(fix(0, accuracy: 200), null, now),
      isTrue,
    );
  });

  test('a rough first fix never locks out accurate ones', () {
    // A cell-tower guess 2 km away claiming ±900 m, then a ±15 m fix.
    final rough = fix(-6, lat: 12.018, accuracy: 900);
    expect(
      LocationService.acceptsFix(fix(-1, accuracy: 15), rough, now),
      isTrue,
    );
    // A similar-quality fix far away is still rejected as a jump.
    expect(
      LocationService.acceptsFix(
        fix(-1, lat: 12.05, accuracy: 600),
        rough,
        now,
      ),
      isFalse,
    );
  });
}
