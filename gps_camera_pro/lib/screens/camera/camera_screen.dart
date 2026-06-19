import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/pressable.dart';
import '../../models/capture_options.dart';
import '../../models/geo_data.dart';
import '../../models/template.dart';
import '../../services/camera_capability_service.dart';
import '../../services/capture_service.dart';
import '../../services/pro_camera_controller.dart';
import '../../services/location_service.dart';
import '../../state/settings_controller.dart';
import '../../state/template_controller.dart';
import '../../widgets/geo_stamp.dart';
import '../../widgets/mini_map.dart';
import '../settings/app_settings.dart';
import 'widgets/camera_chrome.dart';
import 'widgets/camera_layer.dart';
import 'widgets/camera_tool_strip.dart';
import 'widgets/level_overlay.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _location = LocationService();
  final _settings = SettingsController.instance;
  final _templates = TemplateController.instance;
  final _freezeKey = GlobalKey();
  // Raster key for the stamp-only RepaintBoundary — used by the full-res native
  // capture path to composite just the stamp over the sensor-resolution JPEG.
  final _stampRasterKey = GlobalKey();
  Uint8List? _lastShot; // most recent capture, for the gallery thumbnail
  bool _isZoomMode = true; // Zoom/Exposure mode switcher state
  // Zoom is no longer a Pro-menu chip (pinch still zooms), so the active Pro
  // control defaults to exposure rather than the now-absent zoom mode.
  ProControlMode _activeProControl = ProControlMode.exposure;
  double _proDragAccum = 0; // accumulated viewfinder drag for pro-control steps

  // Native Camera2 manual-sensor backend (used while in Pro mode so ISO/shutter/
  // WB/focus actually apply to the live preview).
  // Native Camera2 manual-sensor backend is built and its controls/capture
  // apply at the HAL, but live preview display via the Flutter texture is not
  // yet rendering on Impeller — kept off until that's resolved so the working
  // plugin preview stays intact. Flip to true to resume the native pipeline.
  static const bool _useNativePro = true;
  final ProCameraController _proCam = ProCameraController();
  bool _proActive = false;
  bool _proSwitching = false;
  bool _lastProMode = false;
  bool _proFront = false; // native backend facing
  int? _proTextureId;
  int _proPreviewW = 0;
  int _proPreviewH = 0;

  StreamSubscription<GeoData>? _geoSub;
  GeoData _geo = GeoData.demo();

  // Live magnetometer compass (GPS heading is only valid while moving).
  // Kept in a ValueNotifier so compass ticks only repaint the stamp widget
  // instead of rebuilding the entire camera screen at ~12 fps.
  StreamSubscription<CompassEvent>? _compassSub;
  final ValueNotifier<double?> _compassHeading = ValueNotifier(null);
  DateTime _lastCompassTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Geo snapshot with the live compass heading folded in (used by the stamp,
  /// mini-map pin and capture so the heading/compass update in real time).
  GeoData get _stampGeo =>
      _compassHeading.value == null ? _geo : _geo.copyWith(heading: _compassHeading.value);

  // Computed once when camera limits are known; never recomputed on every build.
  List<double> _zoomLevels = const [1.0];
  List<double> _exposureLevels = const [0.0];

  void _rebuildCameraLevels() {
    _zoomLevels = _computeZoomLevels();
    _exposureLevels = _computeExposureLevels();
  }

  List<double> _computeZoomLevels() {
    final detected = CameraCapabilityService.instance.lensOptions
        .map((e) => e.zoom.clamp(_minZoom, _maxZoom).toDouble())
        .where((z) => z >= _minZoom && z <= _maxZoom)
        .map((z) => (z * 10).round() / 10.0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (detected.length >= 2) return detected;
    if (_minZoom >= _maxZoom) return [1.0];
    final levels = <double>[];
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      final val = _minZoom * math.pow(_maxZoom / _minZoom, i / (steps - 1));
      double rounded = (val * 10).round() / 10.0;
      if ((rounded - rounded.round()).abs() < 0.05) rounded = rounded.roundToDouble();
      if (!levels.contains(rounded)) levels.add(rounded);
    }
    if (levels.length < steps) {
      levels.clear();
      for (var i = 0; i < steps; i++) {
        final val = _minZoom + (_maxZoom - _minZoom) * i / (steps - 1);
        final rounded = (val * 10).round() / 10.0;
        if (!levels.contains(rounded)) levels.add(rounded);
      }
    }
    levels.sort((a, b) => b.compareTo(a));
    return levels;
  }

  List<double> _computeExposureLevels() {
    if (_minExp >= _maxExp) return [0.0];
    // Enumerate the real hardware EV stops using the device's reported step
    // size, so increments match what the sensor actually supports.
    final step = _evStep > 0 ? _evStep : (_maxExp - _minExp) / 8;
    final levels = <double>[];
    for (var v = _minExp; v <= _maxExp + step / 2; v += step) {
      levels.add(double.parse(v.toStringAsFixed(2)));
    }
    if (!levels.contains(0.0) && _minExp < 0 && _maxExp > 0) levels.add(0.0);
    levels.sort((a, b) => b.compareTo(a));
    return levels;
  }

  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  bool _initializing = false; // guard against concurrent controller inits
  bool _pausedByLifecycle = false;

  double _zoom = 1, _minZoom = 1, _maxZoom = 8, _baseZoom = 1;
  double _dragDx = 0, _dragDy = 0; // single-finger pan accumulators
  int _activeResolutionIdx = 0;
  double _exposure = 0, _minExp = 0, _maxExp = 0, _evStep = 0;

  // ── Idle sleep ───────────────────────────────────────────────────────────
  Timer? _idleTimer;
  bool _cameraSleeping = false;
  static const _idleTimeout = Duration(seconds: 30);
  bool _focusLocked = false;
  int _countdown = 0; // self-timer countdown shown over the viewfinder

  bool _level = false; // horizon level overlay
  // Level roll lives in a notifier so high-frequency accelerometer updates only
  // repaint the level overlay instead of rebuilding the whole camera screen.
  final ValueNotifier<double> _roll = ValueNotifier(0.0);
  StreamSubscription<AccelerometerEvent>? _accelSub;
  bool _toolsOpen = false; // camera tool strip expanded
  bool _settingsOpen = false; // app settings strip expanded
  Timer? _menuTimer; // auto-collapse open strips after idle timeout
  static const _menuTimeout = Duration(seconds: 10);
  bool _showPreview = false; // in-app preview of the last capture
  double _stampDragDx = 0, _stampDragDy = 0;
  String? _notificationMsg;
  Timer? _notificationTimer;

  int _mode = 0; // 0 = photo, 1 = video

  bool _busy = false;
  bool _recording = false;
  Duration _recElapsed = Duration.zero;
  Timer? _recTimer;

  bool _showFreeze = false;
  ImageProvider? _frozenBg;
  bool _flash2 = false; // white shutter flash

  // ── Live histogram stream ─────────────────────────────────────────────────
  bool _histogramStreaming = false;
  List<int>? _histogramData;

  Offset? _focus;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Settings changes (grid, map type, formats…) are infrequent and may affect
    // top-level chrome, so rebuild the screen when they change.
    _settings.addListener(_onSettings);
    _proCam.events.listen((e) {
      if (!mounted) return;
      final event = e['event'] as String?;
      if (event == 'histogram' && _histogramStreaming) {
        final data = e['data'];
        if (data is List) setState(() => _histogramData = data.cast<int>());
      }
    });
    // Detect hardware capabilities up front so the Pro chips gate correctly
    // even when we launch straight into the native (Pro) backend.
    CameraCapabilityService.instance.detect().then((_) {
      if (mounted) setState(() {});
    });
    _syncLevelIndicator();
    _lastProMode = _settings.proMode;
    // Start on the right backend: native Camera2 if launching already in Pro.
    if (_settings.proMode && _useNativePro) {
      _enterProBackend();
    } else {
      _initCamera();
    }
    _resetIdleTimer();
    _geoSub = _location.watch().listen(
      (g) {
        if (mounted) setState(() => _geo = g);
      },
      onError: (_) {
        if (mounted) setState(() => _geo = GeoData.demo());
      },
    );
    _compassSub = FlutterCompass.events?.listen(_onCompass);
    // Restore the last capture so the thumbnail/preview works after a restart.
    CaptureService.instance.loadLast().then((b) {
      if (b != null && mounted) setState(() => _lastShot = b);
    });
  }

  void _onCompass(CompassEvent e) {
    final h = e.heading;
    if (h == null || !mounted) return;
    final norm = (h % 360 + 360) % 360;
    final now = DateTime.now();
    // Throttle: at most ~12 fps and only on a meaningful change.
    // Updating the ValueNotifier instead of setState means only the stamp
    // widget rebuilds — not the entire camera screen.
    final delta = ((norm - (_compassHeading.value ?? -999)).abs()) % 360;
    if (now.difference(_lastCompassTick).inMilliseconds < 80) return;
    if (_compassHeading.value != null && delta < 1.0) return;
    _lastCompassTick = now;
    _compassHeading.value = norm;
  }

  void _onSettings() {
    if (!mounted) return;
    // Hand the camera between the plugin (Auto) and native Camera2 (Pro) backend
    // when the Pro toggle flips.
    if (_useNativePro && _settings.proMode != _lastProMode) {
      _lastProMode = _settings.proMode;
      if (_settings.proMode) {
        _enterProBackend();
      } else {
        _exitProBackend();
      }
      return;
    }
    if (_proActive) {
      // Native backend handles its own preview; skip plugin-only sync work.
      setState(() {});
      return;
    }
    _syncLevelIndicator();
    _syncHistogramStream();
    _applyProFocus();
    _applyFlashMode();
    // A resolution change needs a controller re-init; everything else rebuilds.
    if (_cameras.isNotEmpty &&
        _cam != null &&
        _activeResolutionIdx != _settings.captureResolutionIndex) {
      _reinitForResolution();
    } else {
      setState(() {});
    }
  }

  Future<void> _applyFlashMode() async {
    final cam = _cam;
    if (cam != null && cam.value.isInitialized) {
      try {
        await cam.setFlashMode(_settings.flashMode);
      } catch (_) {}
    }
  }

  void _syncLevelIndicator() {
    if (_settings.levelIndicator == _level) return;
    if (_settings.levelIndicator) {
      _startLevelStream();
    } else {
      _accelSub?.cancel();
      _accelSub = null;
    }
    _level = _settings.levelIndicator;
  }

  Future<void> _reinitForResolution() async {
    if (_initializing) return;
    final old = _cam;
    setState(() => _cam = null);
    await old?.dispose();
    await _setupController(_cameras[_camIndex]);
  }

  // ── Idle sleep / wake ────────────────────────────────────────────────────

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _sleepCamera);
  }

  void _sleepCamera() {
    final cam = _cam;
    if (cam == null || !mounted || _pausedByLifecycle) return;
    _cam = null;
    cam.dispose();
    if (mounted) setState(() => _cameraSleeping = true);
  }

  void _wakeCamera() {
    if (!_cameraSleeping || _cameras.isEmpty) return;
    setState(() => _cameraSleeping = false);
    _setupController(_cameras[_camIndex]);
    _resetIdleTimer();
  }

  void _onUserInteraction() {
    if (_cameraSleeping) {
      _wakeCamera();
    } else {
      _resetIdleTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    _geoSub?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _recTimer?.cancel();
    _focusTimer?.cancel();
    _notificationTimer?.cancel();
    _menuTimer?.cancel();
    _idleTimer?.cancel();
    if (_histogramStreaming) {
      _histogramStreaming = false;
      _cam?.stopImageStream().catchError((_) {});
    }
    _cam?.dispose();
    _proCam.close();
    _roll.dispose();
    _compassHeading.dispose();
    super.dispose();
  }

  void _dismissMenus() {
    if (!_toolsOpen && !_settingsOpen) return;
    _menuTimer?.cancel();
    _menuTimer = null;
    setState(() {
      _toolsOpen = false;
      _settingsOpen = false;
    });
  }

  void _startMenuTimer() {
    _menuTimer?.cancel();
    _menuTimer = Timer(_menuTimeout, _dismissMenus);
  }

  void _cancelMenuTimer() {
    _menuTimer?.cancel();
    _menuTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _pauseCameraForLifecycle();
    } else if (state == AppLifecycleState.resumed) {
      _pausedByLifecycle = false;
      unawaited(_resumeCameraAfterLifecycle());
    }
  }

  Future<void> _resumeCameraAfterLifecycle() async {
    if (_cameraSleeping) return;
    // Native (Pro) backend: reopen the Camera2 session it released on pause.
    if (_useNativePro && _settings.proMode) {
      if (!_proActive) await _enterProBackend();
      _resetIdleTimer();
      return;
    }
    if (_cameras.isEmpty) return;
    while (_initializing && mounted && !_pausedByLifecycle) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || _pausedByLifecycle || _cam != null) return;
    await _setupController(_cameras[_camIndex]);
    _resetIdleTimer();
  }

  Future<void> _pauseCameraForLifecycle() async {
    _pausedByLifecycle = true;
    _idleTimer?.cancel();
    // Release the native Camera2 session so it isn't held in the background.
    if (_proActive) {
      _proActive = false;
      _proTextureId = null;
      if (mounted) setState(() {});
      await _proCam.close();
      return;
    }
    final cam = _cam;
    _cam = null;
    if (mounted) setState(() {});
    if (cam == null) return;
    if (cam.value.isRecordingVideo) {
      try {
        await cam.stopVideoRecording();
      } catch (_) {}
      _recTimer?.cancel();
      if (mounted) setState(() => _recording = false);
    }
    await cam.dispose();
  }

  // ── Camera setup ───────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      // Detect hardware capabilities in parallel with Flutter camera discovery.
      final results = await Future.wait([
        availableCameras(),
        CameraCapabilityService.instance.detect().then((_) => null),
      ]);
      final cams = results[0] as List<CameraDescription>;
      if (cams.isEmpty) return;
      _cameras = cams;
      final back = cams.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _camIndex = back >= 0 ? back : 0;
      await _setupController(_cameras[_camIndex]);
    } catch (_) {
      // No camera (simulator/web) — the painted fallback scene shows instead.
    }
  }

  Future<void> _setupController(CameraDescription d) async {
    if (_initializing || _pausedByLifecycle) return;
    _initializing = true;
    _activeResolutionIdx = _settings.captureResolutionIndex;
    final resolution = CameraCapabilityService.instance.resolutionAt(
      _activeResolutionIdx,
    );
    final c = CameraController(d, resolution.preset, enableAudio: true);
    try {
      await c.initialize();
      // Fetch all limits and set flash in parallel to minimise startup time.
      final r = await Future.wait([
        c.getMinZoomLevel(),
        c.getMaxZoomLevel(),
        c.setFlashMode(_settings.flashMode).then((_) => 0.0),
        c.getMinExposureOffset().catchError((_) => 0.0),
        c.getMaxExposureOffset().catchError((_) => 0.0),
        c.getExposureOffsetStepSize().catchError((_) => 0.0),
      ]);
      _minZoom = r[0];
      _maxZoom = r[1];
      _minExp = r[3];
      _maxExp = r[4];
      _evStep = r[5];
      _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
      _exposure = _exposure.clamp(_minExp, _maxExp).toDouble();
      _rebuildCameraLevels();
      // Apply zoom and exposure together.
      await Future.wait([
        c.setZoomLevel(_zoom),
        c.setExposureOffset(_exposure).catchError((_) => 0.0),
      ]);
      if (!mounted || _pausedByLifecycle) {
        await c.dispose();
        _initializing = false;
        return;
      }
      setState(() => _cam = c);
      // Start histogram stream if the overlay is enabled.
      if (_settings.proMode) unawaited(_startHistogramStream());
    } catch (_) {
      await c.dispose();
    } finally {
      _initializing = false;
    }
  }

  // ── Controls ───────────────────────────────────────────────────────────
  void _setZoom(double z) {
    final clamped = z.clamp(_minZoom, _maxZoom).toDouble();
    if (clamped == _zoom) return;
    _onUserInteraction();
    setState(() => _zoom = clamped);
    _cam?.setZoomLevel(clamped);
    if (_proActive) _pushProControls();
    _showNotification('Zoom: ${clamped.toStringAsFixed(1)}x');
  }

  // Gestures: pinch or horizontal swipe → zoom; vertical swipe → template.
  void _onScaleStart(ScaleStartDetails d) {
    _onUserInteraction();
    _baseZoom = _zoom;
    _dragDx = 0;
    _dragDy = 0;
    _proDragAccum = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      _setZoom(_baseZoom * d.scale);
      return;
    }
    _dragDx += d.focalPointDelta.dx;
    _dragDy += d.focalPointDelta.dy;
    if (_dragDx.abs() > _dragDy.abs()) {
      // Horizontal swipe
      if (_settings.proMode) {
        // In Pro Mode, horizontal swipes adjust the active Pro Control value
        _adjustProControlValue(d.focalPointDelta.dx);
      } else {
        // Non-Pro mode: zoom or exposure
        if (_isZoomMode) {
          _setZoom(
            _zoom + d.focalPointDelta.dx * 0.012,
          ); // horizontal swipe → zoom
        } else {
          _setExposure(
            _exposure + d.focalPointDelta.dx * 0.015,
          ); // horizontal swipe → exposure
        }
      }
    } else if (_dragDy.abs() > _dragDx.abs()) {
      // Vertical swipe
      if (_settings.proMode) {
        // In Pro Mode, vertical swipes adjust the active Pro Control parameter
        _adjustProControlValue(d.focalPointDelta.dy);
      } else {
        // Non-Pro mode: only zoom responds to vertical swipes
        if (_isZoomMode) {
          _setZoom(
            _zoom + d.focalPointDelta.dy * -0.012,
          ); // vertical swipe up → zoom in
        }
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Zoom/Pinch is completed. Template cycle moved to stamp gestures.
  }

  /// Accumulates the per-frame drag delta and steps the active pro control one
  /// value for every [_proStepPx] dragged — giving a smooth, continuous feel
  /// like the zoom control instead of a single jump per gesture.
  static const double _proStepPx = 24.0;

  void _adjustProControlValue(double dragDelta) {
    _proDragAccum += dragDelta;
    while (_proDragAccum.abs() >= _proStepPx) {
      final isRight = _proDragAccum > 0;
      _proDragAccum -= isRight ? _proStepPx : -_proStepPx;
      _stepProControl(isRight);
    }
  }

  /// Steps the active pro control one value. Right = previous value, left = next.
  /// Clamps at the ends — no wrap-around looping.
  void _stepProControl(bool isRight) {
    final caps = CameraCapabilityService.instance;
    switch (_activeProControl) {
      case ProControlMode.zoom:
        final currentIdx = _zoomLevels.indexOf(_zoom);
        if (currentIdx >= 0) {
          final nextIdx = isRight
              ? (currentIdx - 1).clamp(0, _zoomLevels.length - 1)
              : (currentIdx + 1).clamp(0, _zoomLevels.length - 1);
          _setZoom(_zoomLevels[nextIdx]);
        }
        break;

      case ProControlMode.exposure:
        final currentIdx = _exposureLevels.indexOf(_exposure);
        if (currentIdx >= 0) {
          final nextIdx = isRight
              ? (currentIdx - 1).clamp(0, _exposureLevels.length - 1)
              : (currentIdx + 1).clamp(0, _exposureLevels.length - 1);
          _setExposure(_exposureLevels[nextIdx]);
        }
        break;

      case ProControlMode.iso:
        final isoValues = caps.isoValues();
        if (isoValues.isEmpty) break;
        final currentIdx =
            _settings.proIso == null ? -1 : isoValues.indexOf(_settings.proIso!);
        int nextIdx;
        if (currentIdx < 0) {
          nextIdx = isRight ? isoValues.length - 1 : 0;
        } else {
          nextIdx = isRight
              ? (currentIdx - 1).clamp(0, isoValues.length - 1)
              : (currentIdx + 1).clamp(0, isoValues.length - 1);
        }
        _setIso(isoValues[nextIdx]);
        break;

      case ProControlMode.shutter:
        final shutters = caps.shutterSpeedsNs();
        if (shutters.isEmpty) break;
        final currentIdx = _settings.proShutterNs == null
            ? -1
            : shutters.indexOf(_settings.proShutterNs!);
        int nextIdx;
        if (currentIdx < 0) {
          nextIdx = isRight ? shutters.length - 1 : 0;
        } else {
          nextIdx = isRight
              ? (currentIdx - 1).clamp(0, shutters.length - 1)
              : (currentIdx + 1).clamp(0, shutters.length - 1);
        }
        _setShutter(shutters[nextIdx]);
        break;

      case ProControlMode.wb:
        if (_settings.whiteBalance == ProWhiteBalance.kelvin) {
          // In Kelvin mode: step temperature in 100K increments, clamped.
          final newK =
              (_settings.kelvin + (isRight ? -100 : 100)).clamp(2500, 8000);
          _settings.update(() => _settings.kelvin = newK);
          if (_proActive) _pushProControls();
          _showNotification('WB ${newK}K');
        } else {
          // Preset mode: exclude Kelvin so the cycle stays within named
          // presets — landing on Kelvin would flip the bar to raw numbers.
          final all = supportedWhiteBalances(caps);
          final wbOptions =
              all.where((w) => w != ProWhiteBalance.kelvin).toList();
          if (wbOptions.isEmpty) break;
          final currentIdx = wbOptions.indexOf(_settings.whiteBalance);
          final safeIdx = currentIdx < 0 ? 0 : currentIdx;
          final nextIdx = isRight
              ? (safeIdx - 1).clamp(0, wbOptions.length - 1)
              : (safeIdx + 1).clamp(0, wbOptions.length - 1);
          _setWhiteBalance(wbOptions[nextIdx]);
        }
        break;

      case ProControlMode.focus:
        final focusLevels = [0.0, 0.25, 0.5, 0.75, 1.0];
        final currentIdx = focusLevels
            .indexWhere((v) => (v - _settings.manualFocus).abs() < 0.01);
        if (currentIdx >= 0) {
          final nextIdx = isRight
              ? (currentIdx - 1).clamp(0, focusLevels.length - 1)
              : (currentIdx + 1).clamp(0, focusLevels.length - 1);
          _setManualFocus(focusLevels[nextIdx]);
        }
        break;

      case ProControlMode.metering:
        final modes = MeteringMode.values;
        final currentIdx = modes.indexOf(_settings.meteringMode);
        final nextIdx = isRight
            ? (currentIdx - 1).clamp(0, modes.length - 1)
            : (currentIdx + 1).clamp(0, modes.length - 1);
        _setMetering(modes[nextIdx]);
        break;
    }
  }

  void _cycleTemplate(int dir) {
    const v = StampTemplate.values;
    final i =
        (v.indexOf(_templates.config.template) + dir + v.length) % v.length;
    _templates.selectTemplate(v[i]);

    // Show template change notification
    final templateName = v[i].name[0].toUpperCase() + v[i].name.substring(1);
    _showNotification('Template: $templateName');
  }

  void _toggleMapSide(bool toLeft) {
    _templates.update((c) {
      c.mapSide = toLeft ? MapSide.left : MapSide.right;
    });
  }

  bool get _isFront =>
      _cameras.isNotEmpty &&
      _cameras[_camIndex].lensDirection == CameraLensDirection.front;

  /// Toggle between the back and front camera (dual-camera switch).
  Future<void> _flip() async {
    _onUserInteraction();
    // Native (Pro) backend: reopen the Camera2 session on the other facing.
    if (_proActive) {
      _proFront = !_proFront;
      await _proCam.close();
      _proActive = false;
      _proTextureId = null;
      final tex = await _proCam.open(width: 1920, height: 1080, front: _proFront);
      if (tex != null) {
        _proTextureId = tex;
        _proPreviewW = _proCam.previewWidth;
        _proPreviewH = _proCam.previewHeight;
        _proActive = true;
        await _pushProControls();
      }
      if (mounted) setState(() {});
      return;
    }
    if (_cameras.length < 2) {
      _toast('No second camera available');
      return;
    }
    final want = _isFront
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final target = _cameras.indexWhere((c) => c.lensDirection == want);
    _camIndex = target >= 0 ? target : (_camIndex + 1) % _cameras.length;
    final old = _cam;
    setState(() => _cam = null);
    await old?.dispose();
    await _setupController(_cameras[_camIndex]);
  }

  void _tapFocus(Offset local, Size box) {
    _onUserInteraction();
    if (_toolsOpen || _settingsOpen) {
      _dismissMenus();
      return;
    }
    final cam = _cam;
    setState(() => _focus = local);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focus = null);
    });
    if (cam != null && cam.value.isInitialized) {
      final p = Offset(
        (local.dx / box.width).clamp(0.0, 1.0),
        (local.dy / box.height).clamp(0.0, 1.0),
      );
      try {
        cam.setFocusPoint(p);
        cam.setExposurePoint(p);
      } catch (_) {}
    }
  }

  Future<void> _setExposure(double v) async {
    _onUserInteraction();
    final clamped = _maxExp > _minExp ? v.clamp(_minExp, _maxExp) : v;
    if (clamped == _exposure) return;
    setState(() => _exposure = clamped);
    try {
      await _cam?.setExposureOffset(clamped);
    } catch (_) {}
    if (_proActive) _pushProControls();
    final sign = clamped > 0 ? '+' : '';
    _showNotification('Exposure: $sign${clamped.toStringAsFixed(1)}');
  }

  Future<void> _setFocusLock(bool lock) async {
    _onUserInteraction();
    setState(() => _focusLocked = lock);
    try {
      await _cam?.setFocusMode(lock ? FocusMode.locked : FocusMode.auto);
    } catch (_) {}
  }

  void _cycleFlash() {
    _onUserInteraction();
    final next = switch (_settings.flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    _settings.update(() => _settings.flashMode = next);
    _applyFlashMode();
  }



  /// Step exposure through a few EV stops within the supported range.
  void _cycleExposure() {
    if (_maxExp <= _minExp) return;
    const steps = [0.0, 1.0, 2.0, -2.0, -1.0];
    final i = steps.indexWhere((s) => (s - _exposure).abs() < 0.05);
    final next = steps[(i < 0 ? 0 : i + 1) % steps.length]
        .clamp(_minExp, _maxExp)
        .toDouble();
    _setExposure(next);
  }

  void _toggleLevel() {
    _onUserInteraction();
    _settings.update(() => _settings.levelIndicator = !_settings.levelIndicator);
  }

  void _startLevelStream() {
    _accelSub?.cancel();
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen((e) {
          // Roll around the viewing axis: 0° when the phone is upright/level.
          final roll = math.atan2(e.x, e.y) * 180 / math.pi;
          if (mounted && (roll - _roll.value).abs() > 0.3) {
            _roll.value = roll; // repaints only the level overlay
          }
        });
  }

  // Histogram data now comes from the native Camera2 YUV reader via the
  // ProCamera2 event channel. _histogramStreaming gates whether incoming
  // histogram events are applied to state.
  Future<void> _startHistogramStream() async {
    if (_histogramStreaming) return;
    if (!(_settings.proMode && _settings.histogram && _proActive)) return;
    _histogramStreaming = true;
  }

  Future<void> _stopHistogramStream() async {
    if (!_histogramStreaming) return;
    _histogramStreaming = false;
    if (mounted) setState(() => _histogramData = null);
  }

  void _syncHistogramStream() {
    final showHistogram = _settings.proMode && _settings.histogram && _proActive;
    if (showHistogram && !_recording) {
      _startHistogramStream();
    } else if (!showHistogram) {
      _stopHistogramStream();
    }
  }

  void _applyProFocus() {
    final cam = _cam;
    if (!_settings.proMode || cam == null || !cam.value.isInitialized) return;
    final focus = _settings.manualFocus;
    try {
      cam.setFocusMode(focus <= 0 ? FocusMode.auto : FocusMode.locked);
    } catch (_) {}
  }

  String _getControlValueLabel() {
    final mode = _settings.proMode ? _activeProControl : (_isZoomMode ? ProControlMode.zoom : ProControlMode.exposure);
    switch (mode) {
      case ProControlMode.zoom:
        return '${_zoom.toStringAsFixed(1)}x';
      case ProControlMode.exposure:
        return '${_exposure > 0 ? '+' : ''}${_exposure.toStringAsFixed(1)}';
      case ProControlMode.iso:
        return _settings.proIso == null ? 'ISO Auto' : 'ISO ${_settings.proIso}';
      case ProControlMode.shutter:
        return _settings.proShutterNs == null ? 'S Auto' : 'S ${_formatShutter(_settings.proShutterNs!)}';
      case ProControlMode.wb:
        return 'WB ${_settings.whiteBalance.label}';
      case ProControlMode.focus:
        return _settings.manualFocus <= 0 ? 'Focus Auto' : 'MF ${_focusLabel(_settings.manualFocus)}';
      case ProControlMode.metering:
        return 'MTR ${_settings.meteringMode.label}';
    }
  }

  IconData _getModeSwitchIcon() {
    if (!_settings.proMode) {
      return _isZoomMode ? Icons.zoom_in : Icons.wb_sunny;
    }
    switch (_activeProControl) {
      case ProControlMode.zoom:
        return Icons.zoom_in;
      case ProControlMode.exposure:
        return Icons.wb_sunny;
      case ProControlMode.iso:
        return Icons.blur_circular;
      case ProControlMode.shutter:
        return Icons.shutter_speed;
      case ProControlMode.wb:
        return Icons.wb_cloudy_outlined;
      case ProControlMode.focus:
        return Icons.filter_center_focus;
      case ProControlMode.metering:
        return Icons.adjust;
    }
  }

  Future<void> _resetFocusExposure() async {
    _onUserInteraction();
    _focusTimer?.cancel();
    setState(() {
      _focus = null;
      _focusLocked = false;
    });
    
    // In Pro Mode, reset the currently selected pro parameter to auto/default
    if (_settings.proMode) {
      _settings.update(() {
        switch (_activeProControl) {
          case ProControlMode.zoom:
            _setZoom(1.0);
            _showNotification('Zoom reset to 1.0×');
            break;
          case ProControlMode.exposure:
            _setExposure(0.0);
            _showNotification('Exposure reset');
            break;
          case ProControlMode.iso:
            _settings.proIso = null;
            _showNotification('ISO Auto');
            break;
          case ProControlMode.shutter:
            _settings.proShutterNs = null;
            _showNotification('Shutter Auto');
            break;
          case ProControlMode.wb:
            _settings.whiteBalance = ProWhiteBalance.auto;
            _showNotification('White Balance Auto');
            break;
          case ProControlMode.focus:
            _settings.manualFocus = 0.0;
            _showNotification('Focus Auto');
            break;
          case ProControlMode.metering:
            _settings.meteringMode = MeteringMode.matrix;
            _showNotification('Metering Reset');
            break;
        }
      });
      // Push all controls to native camera so the reset takes effect immediately
      // (ISO/shutter/WB/focus resets only update settings — without this push
      // the camera keeps the old value until the next unrelated control change).
      if (_proActive) unawaited(_pushProControls());
      try {
        await _cam?.setFocusMode(FocusMode.auto);
      } catch (_) {}
    } else {
      // Non-Pro mode: reset whichever control is currently active.
      if (_isZoomMode) {
        _setZoom(1.0);
        _showNotification('Zoom reset to 1.0×');
      } else {
        try {
          await _cam?.setExposureOffset(0.0);
        } catch (_) {}
        if (mounted) setState(() => _exposure = 0.0.clamp(_minExp, _maxExp).toDouble());
        _showNotification('Exposure reset');
      }
      try {
        await _cam?.setFocusMode(FocusMode.auto);
      } catch (_) {}
    }
  }

  Future<void> _lockFocusExposure() async {
    _onUserInteraction();
    await _setFocusLock(true);
    _showNotification('AE/AF locked');
  }

  void _setProMode(bool enabled) {
    _onUserInteraction();
    _settings.update(() => _settings.proMode = enabled);
    _showNotification(enabled ? 'Pro mode' : 'Auto mode');
  }

  // Pro-control setters: each commits the new value (which notifies listeners
  // and rebuilds the scale) and surfaces the live value in the notification
  // banner, so every interaction — viewfinder swipe, scale swipe or tap — keeps
  // the scale and banner in sync.
  void _setIso(int? v) {
    _onUserInteraction();
    _settings.update(() => _settings.proIso = v);
    if (_proActive) _pushProControls();
    _showNotification(v == null ? 'ISO Auto' : 'ISO $v');
  }

  void _setShutter(int? v) {
    _onUserInteraction();
    _settings.update(() => _settings.proShutterNs = v);
    if (_proActive) _pushProControls();
    _showNotification(v == null ? 'Shutter Auto' : 'S ${_formatShutter(v)}');
  }

  void _setWhiteBalance(ProWhiteBalance v) {
    _onUserInteraction();
    _settings.update(() => _settings.whiteBalance = v);
    if (_proActive) _pushProControls();
    final label = v == ProWhiteBalance.kelvin ? '${_settings.kelvin}K' : v.label;
    _showNotification('WB $label');
  }

  void _setManualFocus(double v) {
    _onUserInteraction();
    _settings.update(() => _settings.manualFocus = v);
    if (_proActive) _pushProControls();
    _showNotification(v <= 0 ? 'Focus Auto' : 'MF ${_focusLabel(v)}');
  }

  void _setMetering(MeteringMode v) {
    _onUserInteraction();
    _settings.update(() => _settings.meteringMode = v);
    _showNotification('MTR ${v.label}');
  }

  /// Cycles the capture file type (JPEG → RAW → RAW+JPEG). Surfaced on the Pro
  /// Controls bar for quick access while shooting.
  void _cycleFileType() {
    _onUserInteraction();
    const modes = RawCaptureMode.values;
    _settings.update(() {
      _settings.rawCaptureMode =
          modes[(modes.indexOf(_settings.rawCaptureMode) + 1) % modes.length];
    });
    _showNotification(switch (_settings.rawCaptureMode) {
      RawCaptureMode.jpeg => 'JPEG',
      RawCaptureMode.raw => 'RAW',
      RawCaptureMode.rawJpeg => 'RAW + JPEG',
    });
  }

  // camera2 CONTROL_AWB_MODE constant for a preset.
  int _awbModeFor(ProWhiteBalance w) => switch (w) {
        ProWhiteBalance.auto => 1,
        ProWhiteBalance.incandescent => 2,
        ProWhiteBalance.fluorescent => 3,
        ProWhiteBalance.daylight => 5,
        ProWhiteBalance.cloudy => 6,
        ProWhiteBalance.shade => 8,
        ProWhiteBalance.kelvin => 0, // AWB_MODE_OFF — gains set via kelvin field
      };

  /// Maps the current Dart control state to the native pipeline. Negative
  /// sentinels reset an axis to auto.
  Future<void> _pushProControls() async {
    if (!_proActive) return;
    final caps = CameraCapabilityService.instance;
    double focus = -1;
    final mfd = caps.minFocusDistance;
    if (_settings.manualFocus > 0 && mfd != null && mfd > 0) {
      focus = _settings.manualFocus * mfd;
    }
    final evSteps = _evStep > 0 ? (_exposure / _evStep).round() : 0;
    try {
      await _proCam.setControls(
        iso: _settings.proIso ?? -1,
        exposureNs: _settings.proShutterNs ?? -1,
        awbMode: _awbModeFor(_settings.whiteBalance),
        kelvin: _settings.whiteBalance == ProWhiteBalance.kelvin
            ? _settings.kelvin
            : -1,
        focusDistance: focus,
        ev: evSteps,
        zoom: _zoom,
      );
    } catch (_) {}
  }

  /// Switches to the native Camera2 backend (Pro mode) so manual sensor controls
  /// apply to the live preview. The `camera` plugin can't, so we hand off the
  /// camera device entirely while Pro mode is active.
  Future<void> _enterProBackend() async {
    if (_proActive || _proSwitching) return;
    _proSwitching = true;
    // Start auto so the preview is never stuck dark from a stale manual ISO/
    // shutter; the user dials in manual values deliberately from there.
    _settings.proIso = null;
    _settings.proShutterNs = null;
    // Sync facing with the currently-active Flutter camera so the first flip
    // goes the correct direction.
    _proFront = _isFront;
    try {
      if (_histogramStreaming) await _stopHistogramStream();
      await _cam?.dispose();
      if (mounted) setState(() => _cam = null);
      final tex = await _proCam.open(width: 1920, height: 1080, front: _proFront);
      if (tex != null) {
        _proTextureId = tex;
        _proPreviewW = _proCam.previewWidth;
        _proPreviewH = _proCam.previewHeight;
        _proActive = true;
        await _pushProControls();
        _syncHistogramStream();
      }
    } catch (_) {
    } finally {
      _proSwitching = false;
      if (mounted) setState(() {});
    }
  }

  /// Returns to the `camera` plugin backend (Auto mode).
  Future<void> _exitProBackend() async {
    if (!_proActive) return;
    _proSwitching = true;
    try {
      await _proCam.close();
    } catch (_) {}
    _proActive = false;
    _proTextureId = null;
    _proPreviewW = 0;
    _proPreviewH = 0;
    _proSwitching = false;
    await _initCamera();
    if (mounted) setState(() {});
  }



  // ── Capture ────────────────────────────────────────────────────────────
  Future<void> _onShutter() async {
    _onUserInteraction();
    if (_mode == 1) return _toggleRecording();
    if (_busy) return;
    final t = _settings.timerSeconds;
    if (t > 0) {
      for (var s = t; s > 0; s--) {
        if (!mounted) return;
        setState(() => _countdown = s);
        await Future.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdown = 0);
    }
    await _capturePhoto();
  }

  Future<void> _capturePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);

    // If the camera was just woken from sleep and is still initialising, wait
    // rather than capturing into a blank frame.
    while (_initializing && mounted && !_pausedByLifecycle) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || (_cam == null && !_proActive)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final cam = _cam;
    String? rawShotPath; // native JPEG path (full-res); null in plugin-path auto mode

    // 1. Hardware capture — ~200–500 ms.
    // Pause the histogram stream before taking a picture; CameraX uses separate
    // use cases but the Flutter plugin may not allow concurrent streaming + capture.
    final wasStreaming = _histogramStreaming;
    if (wasStreaming) await _stopHistogramStream();

    try {
      if (_proActive) {
        // Native Camera2 full-res capture path.
        final dir = await getTemporaryDirectory();
        final rawPath =
            '${dir.path}/raw_${DateTime.now().millisecondsSinceEpoch}.jpg';
        if (_settings.hdrMode == HdrMode.multiFrame) {
          rawShotPath = await _proCam.captureHdr(rawPath);
        } else {
          rawShotPath = await _proCam.capture(rawPath);
        }
      } else if (cam != null && cam.value.isInitialized) {
        final shot = await cam.takePicture();
        rawShotPath = shot.path;
      }
    } catch (_) {
      // On error fall through with rawShotPath = null; the rasterized composite
      // is still saved so the stamp is preserved.
    }
    _frozenBg = null;

    // 2. Show the shutter flash.
    if (!mounted) return;
    setState(() {
      _showFreeze = true;
      _flash2 = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _flash2 = false);

    // 3. Start GPU rasterisation of the composite (stamp over live frame).
    //    In Pro mode we also grab just the stamp boundary for native compositing.
    final stampRatio = CameraCapabilityService.instance
        .resolutionAt(_settings.captureResolutionIndex)
        .stampPixelRatio;
    final boundary =
        _freezeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final stampBoundary = _proActive
        ? _stampRasterKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?
        : null;

    // toImage() snapshots the layer tree atomically before the next setState.
    final renderFuture = boundary != null
        ? CaptureService.instance.rasterize(boundary, pixelRatio: stampRatio)
        : Future<Uint8List?>.value(null);

    // 4. Unfreeze immediately so the user can shoot again.
    if (!mounted) return;
    setState(() {
      _showFreeze = false;
      _busy = false;
      _frozenBg = null;
    });

    // 5. Finish compositing and saving in the background.
    Uint8List? bytes;
    if (_proActive && rawShotPath != null && stampBoundary != null) {
      // Full-res path: composite stamp over the native sensor-resolution JPEG.
      bytes = await CaptureService.instance.compositeNativeWithStamp(
        rawShotPath,
        stampBoundary,
      );
    }
    // Fallback to preview-res rasterized composite (plugin mode, or native failed).
    bytes ??= await renderFuture;

    if (bytes != null) {
      _lastShot = bytes;
      CaptureService.instance.cacheLast(bytes);
      _templates.bumpPhotoNumber();
      final galleryRef = await CaptureService.instance.saveImageToGallery(bytes);
      await CaptureService.instance.saveLocalCapture(bytes, galleryRef: galleryRef);
      if (_settings.saveOriginal && rawShotPath != null) {
        await CaptureService.instance.saveRawToGallery(rawShotPath);
      }
      if (mounted) setState(() {}); // refresh thumbnail
    } else if (mounted) {
      _toast('Capture failed');
    }
    // Restart histogram stream if it was active before capture.
    if (wasStreaming && _settings.histogram && mounted) {
      unawaited(_startHistogramStream());
    }
  }

  Future<void> _toggleRecording() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      _toast('Recording needs a camera');
      return;
    }
    try {
      if (!_recording) {
        // Stop image stream — can't stream while recording on Android CameraX.
        await _stopHistogramStream();
        await cam.startVideoRecording();
        _recElapsed = Duration.zero;
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _recElapsed += const Duration(seconds: 1));
          }
        });
        setState(() => _recording = true);
      } else {
        _recTimer?.cancel();
        final file = await cam.stopVideoRecording();
        setState(() => _recording = false);
        await CaptureService.instance.saveVideoToGallery(file.path);
        // Resume histogram stream if enabled.
        if (_settings.histogram && mounted) unawaited(_startHistogramStream());
      }
    } catch (_) {
      _toast('Recording error');
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
        });
      }
    }
  }

  void _showNotification(String msg) {
    if (!mounted) return;
    _notificationTimer?.cancel();
    setState(() {
      _notificationMsg = msg;
    });
    _notificationTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _notificationMsg = null;
        });
      }
    });
  }

  void _toast(String msg) {
    _showNotification(msg);
  }

  // ── Navigation ──────────────────────────────────────────────────────────
  void _openGallery() {
    if (_lastShot != null) {
      setState(() => _showPreview = true);
    } else {
      CaptureService.instance.openGallery();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;
    final topY = topPad > 0 ? topPad + 8 : 16.0;

    return Scaffold(
      backgroundColor: Palette.ink,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Any pointer-down anywhere on screen dismisses an open menu.
        onTapDown: (_) => _dismissMenus(),
        child: LayoutBuilder(
        builder: (context, c) {
          final screenW = c.maxWidth;
          final screenH = c.maxHeight;
          // Available area is full screen since top and bottom bars are removed.
          final areaH = screenH;

          // Viewfinder box for the chosen aspect ratio (the capture region) —
          // always full width, true ratio height (capped to the area).
          final wh = _settings.captureRatio.portraitWH;
          double boxW = screenW, boxH = areaH;
          if (wh != null) {
            boxH = screenW / wh;
            if (boxH > areaH) {
              boxH = areaH;
            }
          }
          final boxSize = Size(boxW, boxH);
          // Center the viewfinder vertically in the full screen height.
          final viewfinderTop = (areaH - boxH) / 2;
          final controlBottom = bottomPad + Insets.sm;
          const stampInset = 14.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Ratio-aware viewfinder box — no animated positioning so the
              // frame doesn't drift when the aspect ratio changes.
              Positioned(
                top: viewfinderTop,
                left: 0,
                right: 0,
                height: boxH,
                child: _Viewfinder(
                  rasterKey: _freezeKey,
                  size: boxSize,
                  controller: _cam,
                  proTextureId: _proActive ? _proTextureId : null,
                  proWidth: _proPreviewW,
                  proHeight: _proPreviewH,
                  proSensorOrientation: _proCam.sensorOrientation,
                  proFront: _proFront,
                  frozen: _showFreeze ? _frozenBg : null,
                  grid: _settings.gridLines,
                  gridType: _settings.gridType,
                  mirror: _settings.mirror,
                  focus: _focus,
                  levelRoll: _settings.levelIndicator ? _roll : null,
                  histogram: _settings.proMode && _settings.histogram,
                  histogramData: _histogramData,
                  focusPeaking: _settings.focusPeaking &&
                      CameraCapabilityService.instance.manualFocus,
                  zebraStripes: _settings.zebraStripes,
                  // Live preview lifts the stamp above the control bar, but a
                  // capture always pins it to the bottom of the final image.
                  stampInset: _showFreeze ? 14.0 : stampInset,
                  stamp: ListenableBuilder(
                    listenable: Listenable.merge([_templates, _settings, _compassHeading]),
                    builder: (context, _) {
                      return Visibility(
                        visible: _settings.stampEnabled,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            _stampDragDx = 0;
                            _stampDragDy = 0;
                          },
                          onPanUpdate: (details) {
                            _stampDragDx += details.delta.dx;
                            _stampDragDy += details.delta.dy;
                          },
                          onPanEnd: (details) {
                            final absX = _stampDragDx.abs();
                            final absY = _stampDragDy.abs();
                            if (absY > absX * 1.3 && absY >= 40) {
                              _cycleTemplate(_stampDragDy < 0 ? 1 : -1);
                            } else if (absX > absY * 1.3 && absX >= 40) {
                              _toggleMapSide(_stampDragDx < 0);
                            }
                          },
                          child: RepaintBoundary(
                            key: _stampRasterKey,
                            child: GeoStamp(
                              geo: _stampGeo,
                              config: _templates.config,
                              settings: _settings,
                              onMapDoubleTap: () {
                                showMapZoomPopup(
                                  context,
                                  lat: _stampGeo.lat,
                                  lon: _stampGeo.lon,
                                  heading: _stampGeo.heading,
                                  kind: _settings.mapKind,
                                  initialZoom: _settings.mapZoom,
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapFocus: (local) => _tapFocus(local, boxSize),
                  onLongPress: _lockFocusExposure,
                  onDoubleTap: () {
                    _resetFocusExposure();
                  },
                ),
              ),

              // Camera sleep overlay: covers only the viewfinder background.
              // Controls remain visible and interactive above it.
              if (_cameraSleeping)
                Positioned(
                  top: viewfinderTop,
                  left: 0,
                  right: 0,
                  height: boxH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _wakeCamera,
                    child: ColoredBox(
                      color: Palette.ink,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 48,
                              color: Palette.textMid,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap to start camera',
                              style: AppText.bodyHi.copyWith(
                                color: Palette.textMid,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Top controls are fixed at the top of the screen.
              Positioned(
                top: topY,
                left: Insets.lg,
                right: Insets.md,
                child: Row(
                  children: [
                    // Camera settings toolbar (top-left)
                    CameraToolStrip(
                      alignLeft: true,
                      open: _toolsOpen,
                      onOpenChanged: (o) {
                        setState(() => _toolsOpen = o);
                        o ? _startMenuTimer() : _cancelMenuTimer();
                      },
                      flash: _settings.flashMode,
                      onFlash: _cycleFlash,
                      focusLocked: _focusLocked,
                      onFocus: () => _setFocusLock(!_focusLocked),
                      level: _level,
                      onLevel: _toggleLevel,
                      exposure: _exposure,
                      canExpose: _maxExp > _minExp,
                      onExposure: _cycleExposure,
                    ),
                    // Notification banner — floats between the two strips.
                    Expanded(
                      child: IgnorePointer(
                        child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                              child: child,
                            ),
                          ),
                          child: _notificationMsg == null
                              ? const SizedBox.shrink()
                              : FrostedChip(
                                  key: ValueKey<String>(_notificationMsg!),
                                  fill: const Color(0xEB070B14),
                                  stroke: Palette.glassStrokeSoft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 9,
                                  ),
                                  child: Text(
                                    _notificationMsg!,
                                    textAlign: TextAlign.center,
                                    style: AppText.bodyHi.copyWith(
                                      color: Palette.textHi,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      ),
                    ),
                    // App settings (top-right) — collapses while camera settings open.
                    if (!_toolsOpen)
                      AppSettingsStrip(
                        alignLeft: false,
                        open: _settingsOpen,
                        onOpenChanged: (o) {
                          setState(() => _settingsOpen = o);
                          o ? _startMenuTimer() : _cancelMenuTimer();
                        },
                      ),
                  ],
                ),
              ),

              if (_settings.proMode) ...[
                // Pro mode chips: selecting one switches the active control; its
                // value is adjusted by the horizontal viewfinder swipe (like
                // zoom). No separate scale bar under the stamp.
                Positioned(
                  left: Insets.md,
                  right: Insets.md,
                  bottom: controlBottom + 88 + Insets.sm,
                  child: ListenableBuilder(
                    listenable: _settings,
                    builder: (context, _) => _ProQuickPanel(
                      caps: CameraCapabilityService.instance,
                      settings: _settings,
                      exposure: _exposure,
                      canExpose: _maxExp > _minExp,
                      activeMode: _activeProControl,
                      onModeSelected: (mode) {
                        _onUserInteraction();
                        setState(() => _activeProControl = mode);
                      },
                      onFileType: _cycleFileType,
                    ),
                  ),
                ),
              ] else if (!_toolsOpen && !_settingsOpen) ...[
                // Non-Pro Mode: Zoom / Exposure toggle (right edge)
                // Hidden while any menu is open to avoid clutter.
                Positioned(
                  right: Insets.md,
                  top: viewfinderTop,
                  height: boxH,
                  child: Align(
                    alignment: const Alignment(0, -0.25),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Mode Switch Button
                        GlassIconButton(
                          icon: _getModeSwitchIcon(),
                          size: 38,
                          active: true,
                          hasBorder: false,
                          onTap: () {
                            _onUserInteraction();
                            setState(() => _isZoomMode = !_isZoomMode);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Slider Control
                        ProControlSelector(
                          mode: _isZoomMode ? ProControlMode.zoom : ProControlMode.exposure,
                          zoom: _zoom,
                          exposure: _exposure,
                          settings: _settings,
                          caps: CameraCapabilityService.instance,
                          zoomLevels: _zoomLevels,
                          exposureLevels: _exposureLevels,
                          onZoomChanged: _setZoom,
                          onExposureChanged: _setExposure,
                          onIsoChanged: _setIso,
                          onShutterChanged: _setShutter,
                          onWbChanged: _setWhiteBalance,
                          onFocusChanged: _setManualFocus,
                          onMeteringChanged: _setMetering,
                        ),
                        const SizedBox(height: 12),
                        // Value display
                        IgnorePointer(
                          child: GlassSurface(
                            radius: Corners.sm,
                            blur: Blurs.chip,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              _getControlValueLabel(),
                              style: AppText.mono.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Palette.accentMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Recording indicator.
              if (_recording)
                Positioned(
                  top: topY + 54,
                  left: 0,
                  right: 0,
                  child: Center(child: _RecPill(elapsed: _recElapsed)),
                ),

              // Self-timer countdown.
              if (_countdown > 0)
                Positioned(
                  top: viewfinderTop,
                  left: 0,
                  right: 0,
                  height: boxH,
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        '$_countdown',
                        style: const TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Bottom control bar (thumb · auto/pro · shutter · mode · flip).
              Positioned(
                left: Insets.md,
                right: Insets.md,
                bottom: controlBottom,
                child: _ControlBar(
                  mode: _mode,
                  busy: _busy,
                  lastShot: _lastShot,
                  proMode: _settings.proMode,
                  onProMode: () => _setProMode(!_settings.proMode),
                  onMode: (i) {
                    _onUserInteraction();
                    setState(() => _mode = i);
                  },
                  onShutter: _onShutter,
                  onFlip: _flip,
                  onGallery: _openGallery,
                ),
              ),

              // Shutter flash.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _flash2 ? 1 : 0,
                  duration: const Duration(milliseconds: 110),
                  child: Container(color: Colors.white),
                ),
              ),

              // In-app preview of the most recent capture. It sits above all
              // camera overlays so camera sleep never blocks gallery gestures.
              if (_showPreview && _lastShot != null)
                Positioned.fill(
                  child: _PreviewOverlay(
                    latestBytes: _lastShot!,
                    onClose: () => setState(() => _showPreview = false),
                    onOpenGallery: () => CaptureService.instance.openGallery(),
                  ),
                ),
            ],
          );
        },
        ),
      ),
    );
  }
}

/// Full-screen viewer for the most recent capture (pinch-zoomable), with a
/// close button and a shortcut to the phone's gallery.
/// Full-screen viewer for the local captures (pinch-zoomable, swipeable), with a
/// page indicator, close button, and a shortcut to the phone's gallery.
class _PreviewOverlay extends StatefulWidget {
  final Uint8List latestBytes;
  final VoidCallback onClose;
  final VoidCallback onOpenGallery;
  const _PreviewOverlay({
    required this.latestBytes,
    required this.onClose,
    required this.onOpenGallery,
  });

  @override
  State<_PreviewOverlay> createState() => _PreviewOverlayState();
}

class _PreviewOverlayState extends State<_PreviewOverlay> {
  List<File> _files = [];
  bool _loading = true;
  late final PageController _pageController;
  int _currentPage = 0;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final files = await CaptureService.instance.getLocalCaptures();
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
      _prefetchNeighbors(_currentPage);
    }
  }

  /// Warm the image cache for the pages on either side of [idx] so a swipe
  /// shows the next photo instantly instead of flashing while it decodes.
  /// Uses the same downscaled provider as the on-screen [Image.file] so the
  /// precache and the render share one cache entry.
  void _prefetchNeighbors(int idx) {
    if (!mounted || _files.isEmpty) return;
    final mq = MediaQuery.of(context);
    final cacheWidth = (mq.size.width * mq.devicePixelRatio).round();
    for (final i in [idx - 1, idx + 1]) {
      if (i < 0 || i >= _files.length) continue;
      precacheImage(
        ResizeImage(FileImage(_files[i]), width: cacheWidth),
        context,
      ).catchError((_) {});
    }
  }

  Future<void> _share() async {
    if (_files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(_files[_currentPage].path)]),
    );
  }

  Future<void> _delete() async {
    if (_files.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.ink2,
        title: Text(
          'Delete photo?',
          style: AppText.bodyHi.copyWith(color: Palette.textHi),
        ),
        content: Text(
          'Deletes the photo from your gallery and the in-app preview.',
          style: AppText.caption.copyWith(color: Palette.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Palette.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CaptureService.instance.deleteCapture(_files[_currentPage]);
    setState(() {
      _files.removeAt(_currentPage);
      if (_currentPage >= _files.length && _currentPage > 0) {
        _currentPage = _files.length - 1;
      }
    });
    if (_files.isEmpty && mounted) widget.onClose();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    // Intercept Android back button / swipe so it closes the overlay rather
    // than exiting the app (the overlay is a Stack child, not a Navigator route).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: ColoredBox(
        color: Palette.ink,
        child: Stack(
          children: [
            // Swipeable images or loading fallback
            Positioned.fill(
              child: _loading
                  ? Center(
                      child: Image.memory(
                        widget.latestBytes,
                        fit: BoxFit.contain,
                      ),
                    )
                  : _files.isEmpty
                  ? Center(
                      child: Image.memory(
                        widget.latestBytes,
                        fit: BoxFit.contain,
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      physics: _zoomed
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                      itemCount: _files.length,
                      onPageChanged: (idx) {
                        setState(() {
                          _currentPage = idx;
                          _zoomed = false;
                        });
                        _prefetchNeighbors(idx);
                      },
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        return _ZoomableGalleryPage(
                          key: ValueKey(file.path),
                          file: file,
                          onZoomChanged: (zoomed) {
                            if (_zoomed != zoomed && mounted) {
                              setState(() => _zoomed = zoomed);
                            }
                          },
                        );
                      },
                    ),
            ),
            // Top bar: back (left) · share (right)
            Positioned(
              top: topPad + 8,
              left: Insets.md,
              right: Insets.md,
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: widget.onClose,
                    blur: true,
                  ),
                  const Spacer(),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.share_outlined,
                      onTap: _share,
                      blur: true,
                    ),
                ],
              ),
            ),
            // Bottom bar: library (left) · delete (right)
            Positioned(
              left: Insets.md,
              right: Insets.md,
              bottom: mq.padding.bottom + 16,
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.photo_library_outlined,
                    onTap: widget.onOpenGallery,
                    blur: true,
                  ),
                  const Spacer(),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.delete_outline,
                      onTap: _delete,
                      blur: true,
                    ),
                ],
              ),
            ),
            // Page Indicator at the top center
            if (!_loading && _files.isNotEmpty)
              Positioned(
                top: topPad + 14,
                left: 0,
                right: 0,
                child: Center(
                  child: IgnorePointer(
                    child: GlassSurface(
                      radius: Corners.pill,
                      blur: Blurs.chip,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_currentPage + 1} of ${_files.length}',
                        style: AppText.caption.copyWith(
                          color: Palette.textHi,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ), // Stack
      ), // ColoredBox
    ); // PopScope
  }
}

class _ZoomableGalleryPage extends StatefulWidget {
  final File file;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomableGalleryPage({
    super.key,
    required this.file,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomableGalleryPage> createState() => _ZoomableGalleryPageState();
}

class _ZoomableGalleryPageState extends State<_ZoomableGalleryPage>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.6;
  late final TransformationController _transform = TransformationController();
  // Single long-lived controller re-used for every zoom/snap animation.
  // Avoids recreating it mid-callback (caused "multiple tickers" with SingleTickerProviderStateMixin).
  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  // Tracked so we can surgically remove the listener before reset(),
  // preventing the old CurvedAnimation from firing its stale listener.
  Animation<Matrix4>? _anim;
  VoidCallback? _animListener;
  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_reportZoom);
  }

  void _reportZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  void _animateTo(Matrix4 target) {
    _animCtrl.stop();
    // Remove the old listener before reset so the old CurvedAnimation can't
    // fire and snap the transform back to its old start position.
    if (_animListener != null) {
      _anim?.removeListener(_animListener!);
      _animListener = null;
      _anim = null;
    }

    final begin = _transform.value; // captured after stop, before reset
    _animCtrl.reset();

    _anim = Matrix4Tween(begin: begin, end: target).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animListener = () => _transform.value = _anim!.value;
    _anim!.addListener(_animListener!);

    _animCtrl.forward().whenComplete(() {
      _anim?.removeListener(_animListener!);
      _anim = null;
      _animListener = null;
    });
  }

  void _handleDoubleTap() {
    final currentScale = _transform.value.getMaxScaleOnAxis();
    if (currentScale > 1.02) {
      _animateTo(Matrix4.identity());
      return;
    }
    final tap = _doubleTapDetails?.localPosition ?? Offset.zero;
    final target = Matrix4.identity()
      ..translateByDouble(
        -tap.dx * (_doubleTapScale - 1),
        -tap.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    _animateTo(target);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (_transform.value.getMaxScaleOnAxis() <= 1.02) {
      _animateTo(Matrix4.identity());
    }
  }

  @override
  void dispose() {
    _anim?.removeListener(_animListener!);
    _animCtrl.dispose();
    _transform.removeListener(_reportZoom);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Decode the photo down to the device's pixel width rather than its full
    // sensor resolution — a multi-MB capture decodes ~8x smaller, keeping the
    // swipe viewer smooth and memory bounded. Off-screen pages are no longer
    // kept alive, so their bitmaps are released as you scroll away.
    final mq = MediaQuery.of(context);
    final cacheWidth = (mq.size.width * mq.devicePixelRatio).round();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1.0,
        maxScale: 5.5,
        // Zero margin: image cannot be panned beyond its own edges.
        boundaryMargin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        // Panning is disabled at 1x; single-finger swipes then pass through
        // to the parent PageView for image navigation.
        panEnabled: _isZoomed,
        scaleEnabled: true,
        // Higher friction = less runaway momentum after a fast pan.
        interactionEndFrictionCoefficient: 0.0005,
        onInteractionEnd: _onInteractionEnd,
        child: RepaintBoundary(
          child: Center(
            child: Image.file(
              widget.file,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: cacheWidth,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Viewfinder ───────────────────────────────────────────────────────────────
/// The ratio-aware capture region: live preview (or a frozen frame) with the
/// geostamp pinned to the bottom, wrapped in a [RepaintBoundary] so a capture
/// rasterises exactly what's framed. Pinch to zoom, tap to focus.
class _Viewfinder extends StatelessWidget {
  final GlobalKey rasterKey;
  final Size size;
  final CameraController? controller;
  final int? proTextureId;
  final int proWidth;
  final int proHeight;
  final int proSensorOrientation;
  final bool proFront;
  final ImageProvider? frozen;
  final bool grid;
  final GridType gridType;
  final bool mirror;
  final Offset? focus;
  final ValueListenable<double>? levelRoll;
  final bool histogram;
  final List<int>? histogramData;
  final bool focusPeaking;
  final bool zebraStripes;
  final double stampInset;
  final Widget stamp;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final ValueChanged<Offset> onTapFocus;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;

  const _Viewfinder({
    required this.rasterKey,
    required this.size,
    required this.controller,
    this.proTextureId,
    this.proWidth = 0,
    this.proHeight = 0,
    this.proSensorOrientation = 90,
    this.proFront = false,
    required this.frozen,
    required this.grid,
    required this.gridType,
    required this.mirror,
    required this.focus,
    required this.levelRoll,
    required this.histogram,
    this.histogramData,
    required this.focusPeaking,
    required this.zebraStripes,
    required this.stampInset,
    required this.stamp,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.onTapFocus,
    required this.onLongPress,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      onScaleEnd: onScaleEnd,
      onTapUp: (d) => onTapFocus(d.localPosition),
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
            RepaintBoundary(
              key: rasterKey,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: mirror
                            ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                            : Matrix4.identity(),
                        child: frozen != null
                            ? Image(image: frozen!, fit: BoxFit.cover)
                            : CameraLayer(
                                controller: controller,
                                proTextureId: proTextureId,
                                proWidth: proWidth,
                                proHeight: proHeight,
                                proSensorOrientation: proSensorOrientation,
                                proFront: proFront,
                              ),
                      ),
                    ),
                    if (grid)
                      Positioned.fill(
                        child: IgnorePointer(child: _GridOverlay(type: gridType)),
                      ),
                    if (zebraStripes)
                      const Positioned.fill(
                        child: IgnorePointer(child: _ZebraOverlay()),
                      ),
                    if (focusPeaking)
                      const Positioned.fill(
                        child: IgnorePointer(child: _FocusPeakingOverlay()),
                      ),
                    if (histogram)
                      Positioned(
                        left: 10,
                        top: 8,
                        child: IgnorePointer(
                          child: _HistogramOverlay(data: histogramData),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: stampInset,
                      child: stamp,
                    ),
                  ],
                ),
              ),
            ),
            if (levelRoll != null)
              ValueListenableBuilder<double>(
                valueListenable: levelRoll!,
                builder: (_, roll, _) => LevelOverlay(roll: roll),
              ),
            if (focus != null) _FocusReticle(at: focus!),
          ],
        ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  final int mode;
  final bool busy;
  final Uint8List? lastShot;
  final bool proMode;
  final VoidCallback onProMode;
  final ValueChanged<int> onMode;
  final VoidCallback onShutter;
  final VoidCallback onFlip;
  final VoidCallback onGallery;

  const _ControlBar({
    required this.mode,
    required this.busy,
    required this.lastShot,
    required this.proMode,
    required this.onProMode,
    required this.onMode,
    required this.onShutter,
    required this.onFlip,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: Corners.xl,
      blur: Blurs.sheet,
      fill: const Color(0xC2070B14),
      stroke: Palette.glassStrokeSoft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: GalleryThumb(
                  thumb: lastShot,
                  onTap: onGallery,
                  hasBorder: false,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _ProModeButton(active: proMode, onTap: onProMode),
              ),
            ),
            Expanded(
              child: Center(
                child: ShutterButton(
                  onTap: onShutter,
                  busy: busy,
                  video: mode == 1,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: GlassIconButton(
                  icon: mode == 0 ? Icons.photo_camera : Icons.videocam,
                  active: mode == 1,
                  size: 46,
                  hasBorder: false,
                  onTap: () => onMode(mode == 0 ? 1 : 0),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: GlassIconButton(
                  icon: Icons.cameraswitch_outlined,
                  size: 46,
                  hasBorder: false,
                  onTap: onFlip,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _ProQuickPanel extends StatelessWidget {
  final CameraCapabilityService caps;
  final SettingsController settings;
  final double exposure;
  final bool canExpose;
  final ProControlMode activeMode;
  final ValueChanged<ProControlMode> onModeSelected;
  final VoidCallback onFileType;

  const _ProQuickPanel({
    required this.caps,
    required this.settings,
    required this.exposure,
    required this.canExpose,
    required this.activeMode,
    required this.onModeSelected,
    required this.onFileType,
  });

  @override
  Widget build(BuildContext context) {
    // Each chip is gated on a real, runtime-detected hardware capability — an
    // unsupported control is hidden entirely rather than shown disabled. Mode
    // chips select the axis adjusted by the viewfinder swipe; toggle chips flip
    // a setting on tap (File Type / Peaking, kept here for quick shooting access).
    final chips = <({String label, String value, bool active, VoidCallback onTap})>[
      if (caps.manualSensor && caps.isoValues().isNotEmpty)
        (label: 'ISO', value: settings.proIso?.toString() ?? 'Auto', active: activeMode == ProControlMode.iso, onTap: () => onModeSelected(ProControlMode.iso)),
      if (caps.manualSensor && caps.shutterSpeedsNs().isNotEmpty)
        (label: 'S', value: settings.proShutterNs == null ? 'Auto' : _formatShutter(settings.proShutterNs!), active: activeMode == ProControlMode.shutter, onTap: () => onModeSelected(ProControlMode.shutter)),
      if (caps.whiteBalanceModes.isNotEmpty || caps.kelvinWhiteBalance)
        (
          label: 'WB',
          value: settings.whiteBalance == ProWhiteBalance.kelvin
              ? '${settings.kelvin}K'
              : settings.whiteBalance.shortLabel,
          active: activeMode == ProControlMode.wb,
          onTap: () => onModeSelected(ProControlMode.wb),
        ),
      if (caps.manualFocus)
        (label: 'MF', value: settings.manualFocus <= 0 ? 'Auto' : '${(settings.manualFocus * 100).round()}', active: activeMode == ProControlMode.focus, onTap: () => onModeSelected(ProControlMode.focus)),
      if (canExpose)
        (label: 'EV', value: '${exposure > 0 ? '+' : ''}${exposure.toStringAsFixed(1)}', active: activeMode == ProControlMode.exposure, onTap: () => onModeSelected(ProControlMode.exposure)),
      (label: 'MTR', value: settings.meteringMode.shortLabel, active: activeMode == ProControlMode.metering, onTap: () => onModeSelected(ProControlMode.metering)),
      if (caps.supportsRaw)
        (
          label: 'FILE',
          value: settings.rawCaptureMode == RawCaptureMode.jpeg
              ? 'JPEG'
              : (settings.rawCaptureMode == RawCaptureMode.raw ? 'RAW' : 'R+J'),
          active: settings.rawCaptureMode != RawCaptureMode.jpeg,
          onTap: onFileType,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    // Flat row of tiles, centered. Wrap falls back gracefully if chips overflow.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          _ProChip(
            label: chip.label,
            value: chip.value,
            active: chip.active,
            onTap: chip.onTap,
          ),
      ],
    );
  }
}

class _ProChip extends StatelessWidget {
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  const _ProChip({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Flat, container-less tile that mirrors the Camera Settings _ToolTile:
    // the active selection is conveyed purely by colour + weight (accent label
    // over a bright value), never by a fill or border. Soft shadows keep it
    // legible over the live camera feed without an outer surface.
    const shadows = [Shadow(color: Colors.black54, blurRadius: 4)];
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.caption.copyWith(
                fontSize: 9,
                letterSpacing: 0.2,
                color: active ? Palette.accentMuted : Palette.textMid,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                shadows: shadows,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: AppText.mono.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? Palette.textHi : Palette.textMid,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ── Overlays ────────────────────────────────────────────────────────────────
class _GridOverlay extends StatelessWidget {
  final GridType type;
  const _GridOverlay({required this.type});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter(type));
}

class _GridPainter extends CustomPainter {
  final GridType type;
  const _GridPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 0.7;
    switch (type) {
      case GridType.thirds:
        for (var i = 1; i < 3; i++) {
          final x = size.width * i / 3;
          final y = size.height * i / 3;
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case GridType.square:
        final step = size.shortestSide / 3;
        final left = (size.width - step * 3) / 2;
        final top = (size.height - step * 3) / 2;
        for (var i = 0; i <= 3; i++) {
          final x = left + step * i;
          final y = top + step * i;
          canvas.drawLine(Offset(x, top), Offset(x, top + step * 3), p);
          canvas.drawLine(Offset(left, y), Offset(left + step * 3, y), p);
        }
      case GridType.golden:
        const a = 0.382;
        const b = 0.618;
        for (final x in [size.width * a, size.width * b]) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (final y in [size.height * a, size.height * b]) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.type != type;
}

class _HistogramOverlay extends StatelessWidget {
  final List<int>? data;
  const _HistogramOverlay({this.data});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: Corners.sm,
      blur: Blurs.chip,
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        size: const Size(104, 48),
        painter: _HistogramPainter(data: data),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int>? data;
  const _HistogramPainter({this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final d = data;
    if (d != null && d.length == 256) {
      _paintReal(canvas, size, d);
    } else {
      _paintDemo(canvas, size);
    }
  }

  void _paintReal(Canvas canvas, Size size, List<int> d) {
    int maxVal = 1;
    for (final v in d) {
      if (v > maxVal) maxVal = v;
    }
    final scale = size.width / 256;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 256; i++) {
      if (d[i] == 0) continue;
      final barH = size.height * d[i] / maxVal;
      final shade = i / 255.0;
      paint.color = Color.fromRGBO(
        (shade * 220).round(),
        (shade * 220).round(),
        (shade * 220).round(),
        0.72,
      );
      canvas.drawRect(
        Rect.fromLTWH(i * scale, size.height - barH, scale + 0.3, barH),
        paint,
      );
    }
  }

  void _paintDemo(Canvas canvas, Size size) {
    final colors = [
      Palette.danger.withValues(alpha: 0.62),
      Palette.success.withValues(alpha: 0.62),
      Palette.accentMuted.withValues(alpha: 0.62),
    ];
    for (var channel = 0; channel < colors.length; channel++) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colors[channel];
      final path = Path();
      for (var i = 0; i <= 31; i++) {
        final x = size.width * i / 31;
        final wave = math.sin(i * 0.42 + channel) * 0.28 +
            math.sin(i * 0.17 + channel * 2) * 0.18;
        final y = size.height * (0.64 - wave).clamp(0.12, 0.92);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) => old.data != data;
}

class _ZebraOverlay extends StatelessWidget {
  const _ZebraOverlay();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ZebraPainter());
}

class _ZebraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    for (double x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FocusPeakingOverlay extends StatelessWidget {
  const _FocusPeakingOverlay();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FocusPeakingPainter());
}

class _FocusPeakingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Palette.accentMuted.withValues(alpha: 0.35);
    final center = Offset(size.width * 0.5, size.height * 0.42);
    canvas.drawOval(Rect.fromCenter(center: center, width: size.width * 0.34, height: size.height * 0.18), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.28, size.height * 0.56), width: size.width * 0.18, height: size.height * 0.10), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.72, size.height * 0.58), width: size.width * 0.20, height: size.height * 0.12), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatShutter(int ns) {
  final seconds = ns / 1000000000.0;
  if (seconds >= 1) {
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }
  return '1/${(1 / seconds).round()}';
}

String _focusLabel(double value) {
  if (value <= 0) return 'Auto';
  if (value <= 0.25) return 'Macro';
  if (value <= 0.5) return 'Near';
  if (value <= 0.75) return 'Mid';
  if (value < 1) return 'Far';
  return 'Infinity';
}

class _FocusReticle extends StatefulWidget {
  final Offset at;
  const _FocusReticle({required this.at});
  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.normal,
  )..forward();

  @override
  void didUpdateWidget(covariant _FocusReticle old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.at.dx - 38,
      top: widget.at.dy - 38,
      child: IgnorePointer(
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1.25,
            end: 1,
          ).animate(CurvedAnimation(parent: _c, curve: Motion.emphasized)),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.85).animate(_c),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Palette.accentMuted, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: Palette.accentMuted.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.center_focus_strong,
                  size: 18,
                  color: Palette.accentMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecPill extends StatelessWidget {
  final Duration elapsed;
  const _RecPill({required this.elapsed});

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)}';
    return FrostedChip(
      fill: const Color(0xCC2A0C12),
      stroke: Palette.danger.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulseDot(color: Palette.danger),
          const SizedBox(width: 8),
          Text(
            'REC  $t',
            style: AppText.metric.copyWith(
              color: Palette.textHi,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pro mode button ───────────────────────────────────────────────────────────

/// Tappable button that shows the custom camera+aperture icon.
/// Active state gets the brand gradient pill; inactive is plain.
class _ProModeButton extends StatelessWidget {
  final bool active;
  final VoidCallback? onTap;
  const _ProModeButton({required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    final icon = SizedBox(
      width: size,
      height: size,
      child: Icon(
        active ? Icons.tune_rounded : Icons.auto_awesome,
        size: 22,
        color: Palette.textHi,
      ),
    );

    Widget body;
    if (active) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: Palette.selectionGradient,
          border: Border.all(color: Palette.selectionStroke, width: 1),
        ),
        child: icon,
      );
    } else {
      body = icon;
    }

    return Pressable(
      onTap: onTap,
      child: body,
    );
  }
}
