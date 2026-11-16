import 'dart:io';

import 'package:flutter/services.dart';

/// Small platform services, implemented in `PlatformChannel.kt` instead of a
/// plugin each: app folders, version, gallery, geocoder and sensors.
class Native {
  Native._();

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/platform',
  );
  static const _heading = EventChannel('com.gpscamera.gps_camera_next/heading');
  static const _gravity = EventChannel('com.gpscamera.gps_camera_next/gravity');

  static Map<String, String>? _dirs;

  static Future<Map<String, String>> _folders() async {
    final known = _dirs;
    if (known != null) return known;
    final dirs = await _channel.invokeMapMethod<String, String>('dirs');
    if (dirs == null) return const {};
    return _dirs = dirs;
  }

  /// Private app storage (`Context.getFilesDir`).
  static Future<Directory> supportDir() => _dir('support');

  static Future<Directory> _dir(String name) async {
    final path = (await _folders())[name];
    if (path == null) throw StateError('No $name folder');
    return Directory(path);
  }

  /// Where earlier builds kept documents (`app_flutter`).
  static Future<Directory> documentsDir() => _dir('documents');

  /// "1.2.0 (14)".
  static Future<String?> appVersion() async {
    final info = await _channel.invokeMapMethod<String, Object?>('appVersion');
    if (info == null) return null;
    return '${info['name']} (${info['code']})';
  }

  static Future<bool> openGallery() async =>
      await _channel.invokeMethod<bool>('openGallery') ?? false;

  /// Opens public policy/provider pages in the user's browser.
  static Future<bool> openWebPage(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    return await _channel.invokeMethod<bool>('openWebPage', {'url': value}) ??
        false;
  }

  /// The device geocoder's address for a point, or null when the phone has
  /// no geocoder or nothing is known there.
  static Future<Map<String, String?>?> geocode(double lat, double lon) async {
    final row = await _channel.invokeMapMethod<String, String?>('geocode', {
      'lat': lat,
      'lon': lon,
    });
    return row;
  }

  /// Compass heading in degrees (−180…180, 0 = north), while listened to.
  static Stream<double> heading() => _heading.receiveBroadcastStream().map(
    (value) => (value as num).toDouble(),
  );

  /// Accelerometer x, y, z in m/s², while listened to.
  static Stream<List<double>> gravity() => _gravity
      .receiveBroadcastStream()
      .map((value) => [for (final v in value as List) (v as num).toDouble()]);
}
