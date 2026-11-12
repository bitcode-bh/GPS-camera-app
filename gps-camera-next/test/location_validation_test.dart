import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/services/location_service.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9);
  Position fix(
    int seconds, {
    double lat = 12,
    double lon = 77,
    double accuracy = 5,
  }) => Position(
    latitude: lat,
    longitude: lon,
    timestamp: now.add(Duration(seconds: seconds)),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
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
}
