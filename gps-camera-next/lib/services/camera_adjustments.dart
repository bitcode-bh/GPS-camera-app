import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';

class CameraAdjustments {
  // CameraX exposes a continuous range, not the OEM camera app's preset list.
  static double nextZoomPreset(double current, double min, double max) {
    final stops = [
      min,
      if (1 > min && 1 <= max) 1.0,
      if (2 > min && 2 <= max) 2.0,
    ];
    return stops.firstWhere(
      (stop) => stop > current + .01,
      orElse: () => stops.first,
    );
  }

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/adjustments',
  );

  static Future<({bool flash, int? whiteBalanceMin, int? whiteBalanceMax})>
  features(CameraDescription camera) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'features',
        {'camera': camera.name},
      );
      return (
        flash: result?['flash'] == true,
        whiteBalanceMin: result?['whiteBalanceMin'] as int?,
        whiteBalanceMax: result?['whiteBalanceMax'] as int?,
      );
    } on MissingPluginException {
      return (flash: false, whiteBalanceMin: null, whiteBalanceMax: null);
    } on PlatformException {
      return (flash: false, whiteBalanceMin: null, whiteBalanceMax: null);
    }
  }

  static Future<void> setWhiteBalance(
    CameraController camera,
    int? kelvin,
  ) async {
    int? controlId;
    final platform = CameraPlatform.instance;
    if (platform is AndroidCameraCameraX) {
      final control = platform.cameraControl;
      controlId = control.pigeon_instanceManager.getIdentifier(control);
      if (controlId == null) throw PlatformException(code: 'CAMERA_CLOSED');
    }
    await _channel.invokeMethod<void>('setWhiteBalance', {
      'camera': camera.description.name,
      'control': controlId,
      'kelvin': kelvin,
    });
  }
}
