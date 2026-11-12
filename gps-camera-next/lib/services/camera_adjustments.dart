import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';

class CameraAdjustments {
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
