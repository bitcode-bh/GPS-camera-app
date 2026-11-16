import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/models/location_integrity.dart';
import 'package:gps_camera_next/models/media_item.dart';
import 'package:gps_camera_next/services/geostamp_snapshot.dart';
import 'package:gps_camera_next/services/location_service.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/state/settings_controller.dart';

void main() {
  final now = DateTime.utc(2026, 11, 15);
  GeoData geo({
    int age = 0,
    double lat = 12,
    double accuracy = 5,
    double? rawAccuracy,
  }) => GeoData(
    lat: lat,
    lon: 77,
    altitude: 10,
    accuracy: accuracy,
    heading: 0,
    place: '',
    fullAddress: '',
    shortAddress: '',
    country: '',
    countryFlag: '',
    isoCode: '',
    time: now,
    fixTime: now.subtract(Duration(seconds: age)),
    isLive: true,
    rawLat: lat + 0.00001,
    rawLon: 77,
    rawAccuracy: rawAccuracy ?? accuracy,
  );
  GeoData snapshot(
    GpsStatus status, {
    GeoData? good,
    MockLocationPolicy policy = MockLocationPolicy.label,
  }) => geostampSnapshot(
    status: status,
    now: now,
    accuracyLimit: 25,
    mockPolicy: policy,
    lastGood: good,
  );

  test('photo snapshot stays immutable when the next GPS update arrives', () {
    var status = GpsStatus(GpsState.fix, fix: geo());
    final photo = snapshot(status);
    status = GpsStatus(GpsState.fix, fix: geo(lat: 13));
    expect(snapshot(status).lat, 13);
    expect(photo.lat, 12);
    expect(photo.fixTime, now);
    expect(photo.rawLat, 12.00001);
    expect(photo.copyWith(heading: 90).rawLat, photo.rawLat);
  });

  test(
    'weak fixes remain explicitly uncertain, including filtered optimistic accuracy',
    () {
      for (final current in [geo(accuracy: 300), geo(rawAccuracy: 80)]) {
        final result = snapshot(GpsStatus(GpsState.fix, fix: current));
        expect(result.hasLocation, isTrue);
        expect(result.integrity, LocationIntegrity.lowAccuracy);
        expect(result.locationNote, 'Weak GPS signal');
      }
    },
  );

  test(
    'retained indoor fixes are labeled, and disappear when expired or switched off',
    () {
      final good = geo(age: 20);
      final result = snapshot(
        GpsStatus(GpsState.fix, fix: geo(accuracy: 80)),
        good: good,
      );
      expect(result.accuracy, 5);
      expect(result.locationNote, contains('Last acceptable fix'));
      expect(result.locationNote, contains('20s old'));
      expect(result.integrity, LocationIntegrity.lowAccuracy);
      expect(
        snapshot(
          GpsStatus(GpsState.fix, fix: geo(age: 60)),
          good: good,
        ).hasLocation,
        isFalse,
      );
      expect(
        snapshot(const GpsStatus(GpsState.disabled), good: good).hasLocation,
        isFalse,
      );
    },
  );

  test(
    'warning survives good-fix fallback and omission of mock coordinates',
    () {
      final status = GpsStatus(
        GpsState.fix,
        fix: geo(accuracy: 80),
        integrity: LocationIntegrity.suspectedMock,
      );
      expect(
        snapshot(status, good: geo()).integrity,
        LocationIntegrity.suspectedMock,
      );
      final omitted = snapshot(
        status,
        good: geo(),
        policy: MockLocationPolicy.omitCoordinates,
      );
      expect(omitted.hasLocation, isFalse);
      expect(omitted.integrity, LocationIntegrity.suspectedMock);
      expect(omitted.locationNote, 'Coordinates omitted');
      expect(omitted.locationDescription, contains('Mock Location'));
    },
  );

  test('aging and approximate locations never get a trusted state', () {
    expect(
      snapshot(GpsStatus(GpsState.fix, fix: geo(age: 15))).integrity,
      LocationIntegrity.lowAccuracy,
    );
    expect(
      snapshot(
        GpsStatus(GpsState.fix, fix: geo(), approximate: true),
      ).integrity,
      LocationIntegrity.lowAccuracy,
    );
    expect(
      snapshot(GpsStatus(GpsState.fix, fix: GeoData.demo())).hasLocation,
      isFalse,
    );
  });

  test(
    'video samples carry integrity changes without rewriting earlier samples',
    () {
      final start = snapshot(GpsStatus(GpsState.fix, fix: geo()));
      final warning = snapshot(
        GpsStatus(
          GpsState.fix,
          fix: geo(),
          integrity: LocationIntegrity.suspectedSpoofing,
        ),
      );
      final missing = snapshot(const GpsStatus(GpsState.unavailable));
      expect(start.integrity, LocationIntegrity.trusted);
      expect(warning.locationDescription, contains('Suspected spoofing'));
      expect(missing.hasLocation, isFalse);
      expect(start.lat, warning.lat);
    },
  );

  test(
    'library metadata retains uncertainty across a saved-index round trip',
    () {
      const location = MediaLocation(
        12,
        77,
        place: 'A place',
        integrityNote: 'Mock Location',
      );
      final loaded = MediaLocation.fromJson(location.toJson())!;
      expect(loaded.integrityNote, 'Mock Location');
      expect(loaded.lat, location.lat);
      expect(loaded.lon, location.lon);
      expect(
        MediaLocation.fromJson({'lat': 12, 'lon': 77})!.integrityNote,
        isEmpty,
      );
    },
  );

  test(
    'mock capture policy persists and invalid preferences use label policy',
    () {
      final settings = SettingsController.instance;
      final prefs = Prefs.memory();
      settings.attach(prefs);
      settings.update(
        () => settings.mockLocationPolicy = MockLocationPolicy.omitCoordinates,
      );
      settings.attach(prefs);
      expect(settings.mockLocationPolicy, MockLocationPolicy.omitCoordinates);
      prefs.setString('mockLocationPolicy', 'invalid');
      settings.attach(prefs);
      expect(settings.mockLocationPolicy, MockLocationPolicy.label);
    },
  );
}
