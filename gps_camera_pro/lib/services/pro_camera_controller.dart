import 'package:flutter/services.dart';

/// Dart binding for the native Camera2 manual-sensor pipeline ([ProCamera2.kt]).
///
/// Unlike the `camera` plugin, this drives real `SENSOR_SENSITIVITY` (ISO),
/// `SENSOR_EXPOSURE_TIME` (shutter), white balance (preset or Kelvin),
/// `LENS_FOCUS_DISTANCE` and exposure compensation straight into the repeating
/// preview request, so changes apply to the live preview immediately.
class ProCameraController {
  static const _method = MethodChannel('com.gpscamera.gps_camera_pro/procam');
  static const _events = EventChannel('com.gpscamera.gps_camera_pro/procam/events');

  int? textureId;
  int previewWidth = 0;
  int previewHeight = 0;
  int sensorOrientation = 90;
  bool front = false;
  bool get isOpen => textureId != null;

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// Opens the back camera, allocates a Flutter texture and starts the preview.
  /// Returns the texture id to feed a [Texture] widget.
  Future<int?> open({int width = 1920, int height = 1080, bool front = false}) async {
    final res = await _method.invokeMethod<Map>('open', {
      'width': width,
      'height': height,
      'front': front,
    });
    if (res == null) return null;
    textureId = res['textureId'] as int?;
    previewWidth = (res['previewWidth'] as int?) ?? 0;
    previewHeight = (res['previewHeight'] as int?) ?? 0;
    sensorOrientation = (res['sensorOrientation'] as int?) ?? 90;
    this.front = (res['front'] as bool?) ?? front;
    return textureId;
  }

  /// Pushes manual controls to the live preview. Any omitted axis is left
  /// unchanged; pass an explicit auto sentinel to clear one (see [setAuto]).
  Future<void> setControls({
    int? iso,
    int? exposureNs,
    int? awbMode,
    int? kelvin,
    double? focusDistance,
    int? ev,
    double? zoom,
  }) {
    final args = <String, dynamic>{};
    if (iso != null) args['iso'] = iso;
    if (exposureNs != null) args['exposureNs'] = exposureNs;
    if (awbMode != null) args['awbMode'] = awbMode;
    if (kelvin != null) args['kelvin'] = kelvin;
    if (focusDistance != null) args['focusDistance'] = focusDistance;
    if (ev != null) args['ev'] = ev;
    if (zoom != null) args['zoom'] = zoom;
    return _method.invokeMethod('setControls', args);
  }

  /// Clears manual exposure (ISO/shutter) back to auto. Pass iso/exposure as a
  /// negative sentinel handled natively, or simply omit them here and re-open.
  Future<void> setAutoExposure() =>
      _method.invokeMethod('setControls', {'iso': -1, 'exposureNs': -1});

  /// Captures a still JPEG to [path] using the current manual settings.
  Future<String?> capture(String path) =>
      _method.invokeMethod<String>('capture', {'path': path});

  /// Captures 3 bracketed JPEG frames and Mertens-fuses them into a single
  /// HDR JPEG written to [path].
  Future<String?> captureHdr(String path) =>
      _method.invokeMethod<String>('captureHdr', {'path': path});

  Future<void> close() async {
    await _method.invokeMethod('close');
    textureId = null;
  }
}
