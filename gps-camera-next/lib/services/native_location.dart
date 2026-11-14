import 'package:flutter/services.dart';

/// One position from the device (see `LocationChannel.kt`).
class Fix {
  const Fix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracy,
    this.altitude = 0,
    this.heading = -1,
    this.speed = -1,
  });

  factory Fix.fromMap(Map<Object?, Object?> m) => Fix(
    latitude: (m['lat'] as num).toDouble(),
    longitude: (m['lon'] as num).toDouble(),
    altitude: (m['altitude'] as num?)?.toDouble() ?? 0,
    accuracy: (m['accuracy'] as num?)?.toDouble() ?? double.nan,
    heading: (m['heading'] as num?)?.toDouble() ?? -1,
    speed: (m['speed'] as num?)?.toDouble() ?? -1,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (m['time'] as num).toInt(),
      isUtc: true,
    ),
  );

  final double latitude;
  final double longitude;
  final double altitude;

  /// Metres; NaN when unknown.
  final double accuracy;

  /// Degrees; negative when unknown.
  final double heading;

  /// m/s; negative when unknown.
  final double speed;
  final DateTime timestamp;
}

enum LocationPermit { granted, denied, deniedForever }

class LocationAccess {
  const LocationAccess({
    required this.serviceEnabled,
    required this.permit,
    required this.approximate,
  });

  static LocationAccess _from(Map<Object?, Object?>? m) => LocationAccess(
    serviceEnabled: m?['service'] == true,
    permit: switch (m?['permission']) {
      'granted' => LocationPermit.granted,
      'deniedForever' => LocationPermit.deniedForever,
      _ => LocationPermit.denied,
    },
    approximate: m?['approximate'] == true,
  );

  final bool serviceEnabled;
  final LocationPermit permit;

  /// Only "approximate location" was granted.
  final bool approximate;
}

/// Errors from [NativeLocation.positions].
class LocationDisabled implements Exception {
  const LocationDisabled();
}

class NativeLocation {
  NativeLocation._();

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/location',
  );
  static const _positions = EventChannel(
    'com.gpscamera.gps_camera_next/positions',
  );
  static const _switch = EventChannel(
    'com.gpscamera.gps_camera_next/location_switch',
  );

  static Future<LocationAccess> access() async => LocationAccess._from(
    await _channel.invokeMapMethod<Object?, Object?>('status'),
  );

  /// Shows the system prompt if permission can still be asked for.
  static Future<LocationAccess> request() async => LocationAccess._from(
    await _channel.invokeMapMethod<Object?, Object?>('request'),
  );

  static Stream<Fix> positions() => _positions
      .receiveBroadcastStream()
      .handleError((Object error) {
        if (error is PlatformException && error.code == 'disabled') {
          throw const LocationDisabled();
        }
        throw error;
      })
      .map((value) => Fix.fromMap(value as Map<Object?, Object?>));

  /// Emits when the device location switch changes.
  static Stream<bool> switchChanges() =>
      _switch.receiveBroadcastStream().map((value) => value == true);

  static Future<bool> openAppSettings() async =>
      await _channel.invokeMethod<bool>('openAppSettings') ?? false;

  static Future<bool> openLocationSettings() async =>
      await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
}
