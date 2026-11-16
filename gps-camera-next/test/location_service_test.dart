import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/location_integrity.dart';
import 'package:gps_camera_next/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefix = 'com.gpscamera.gps_camera_next';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final statuses = <GpsStatus>[];
  StreamSubscription<GpsStatus>? subscription;
  Completer<Map<String, String>?>? address;
  late DateTime start;
  late LocationService location;

  setUp(() async {
    start = DateTime.now().subtract(const Duration(seconds: 1));
    statuses.clear();
    address = null;
    for (final name in [
      'positions',
      'location_switch',
      'platform',
      'location',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel('$prefix/$name'), (
        call,
      ) async {
        if (call.method == 'status') {
          return {
            'service': true,
            'permission': 'granted',
            'approximate': false,
          };
        }
        if (call.method == 'geocode') return address?.future;
        return null;
      });
    }
    location = LocationService();
    subscription = location.watch(ask: false).listen(statuses.add);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await subscription?.cancel();
    for (final name in [
      'positions',
      'location_switch',
      'platform',
      'location',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel('$prefix/$name'), null);
    }
  });

  Future<void> position(
    int second, {
    double lat = 12,
    double accuracy = 5,
    bool mock = false,
  }) async {
    final done = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      '$prefix/positions',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'lat': lat,
        'lon': 77.0,
        'accuracy': accuracy,
        'time': start.add(Duration(seconds: second)).millisecondsSinceEpoch,
        'elapsedRealtimeNanos': (100 + second) * 1000000000,
        'ageNanos': 0,
        'isMock': mock,
      }),
      (_) => done.complete(),
    );
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'rejected updates retain the measurement time and matching raw source',
    () async {
      await position(0);
      final first = statuses.last.fix!;
      await position(1, lat: 12.003, accuracy: 300);
      final rejected = statuses.last;
      expect(rejected.integrity, LocationIntegrity.lowAccuracy);
      expect(rejected.rawFix!.accuracy, 300);
      expect(rejected.fix!.fixTime, first.fixTime);
      expect(rejected.fix!.lat, first.lat);
      expect(rejected.fix!.rawLat, first.rawLat);
      expect(rejected.fix!.rawAccuracy, first.rawAccuracy);
    },
  );

  test('reopening the camera does not clear a latched mock warning', () async {
    await position(0, mock: true);
    await subscription!.cancel();
    subscription = location.watch(ask: false).listen(statuses.add);
    await Future<void>.delayed(Duration.zero);
    await position(1);
    expect(statuses.last.integrity, LocationIntegrity.suspectedMock);
    expect(statuses.last.fix!.lat, 12);
  });

  test('an address completing after a jump cannot erase its warning', () async {
    address = Completer<Map<String, String>?>();
    await position(0);
    await position(1, lat: 13);
    final count = statuses.length;
    expect(statuses.last.integrity, LocationIntegrity.lowAccuracy);
    address!.complete({'locality': 'A city'});
    await Future<void>.delayed(Duration.zero);
    expect(statuses.length, count);
    expect(statuses.last.integrity, LocationIntegrity.lowAccuracy);
  });

  test(
    'mock transitions reset the Kalman filter before real recovery',
    () async {
      await position(0);
      await position(1, lat: 13, mock: true);
      expect(statuses.last.integrity, LocationIntegrity.suspectedMock);
      expect(statuses.last.fix!.lat, 13);
      await position(2);
      expect(statuses.last.integrity, LocationIntegrity.suspectedMock);
      expect(statuses.last.fix!.lat, 12);
      await position(3);
      await position(4);
      expect(statuses.last.integrity, LocationIntegrity.trusted);
      expect(statuses.last.fix!.lat, closeTo(12, 0.000001));
    },
  );
}
