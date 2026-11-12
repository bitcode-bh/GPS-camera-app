import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/transitions.dart';
import '../../models/capture_options.dart';
import '../../models/geo_data.dart';
import '../../models/template.dart';
import '../../services/camera_adjustments.dart';
import '../../services/capture_service.dart';
import '../../services/location_service.dart';
import '../../state/settings_controller.dart';
import '../../state/template_controller.dart';
import '../../widgets/geo_stamp.dart';
import '../../widgets/mini_map.dart';
import '../settings/app_settings.dart';
import '../templates/custom_template_editor.dart';
import '../templates/templates_screen.dart';
import 'widgets/camera_control_bar.dart';
import 'widgets/camera_design.dart';
import 'widgets/camera_chrome.dart';
import 'widgets/camera_layer.dart';
import 'video_library.dart';

enum _Adjustment { zoom, exposure, whiteBalance, reset }

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
  Uint8List? _lastShot;
  _Adjustment? _adjustment;
  int _minKelvin = 0, _maxKelvin = 0;
  int? _kelvin, _appliedKelvin;
  bool _editingWhiteBalance = false;
  bool get _whiteBalanceSupported => _maxKelvin > _minKelvin;
  int get _defaultKelvin => 5500.clamp(_minKelvin, _maxKelvin);
  int get _whiteBalance =>
      (_kelvin ?? _defaultKelvin).clamp(_minKelvin, _maxKelvin);
  _Adjustment get _leftAdjustment =>
      _editingWhiteBalance ? _Adjustment.whiteBalance : _Adjustment.exposure;
  bool _whiteBalancePending = false;
  Future<void> _cameraInterop = Future.value();
  bool _hasFlash = false;
  bool _flashPending = false;
  bool _flipping = false;
  bool _zoomPending = false;
  bool _exposurePending = false;
  double _appliedZoom = 1;
  double _appliedExposure = 0;

  _Adjustment? _gestureAdjustment;
  Timer? _gestureReadoutTimer;
  Offset _gestureOrigin = Offset.zero;
  int _gestureQuarterTurns = 0;
  double _gestureStartExposure = 0;
  int _gestureStartKelvin = 5500;
  bool _edgeGestureRejected = false;
  bool _hadPinch = false;
  final _viewfinderPointers = <int>{};

  StreamSubscription<AccelerometerEvent>? _orientationSub;
  int _iconQuarterTurns = 0;

  void _listenForOrientation() {
    _orientationSub ??= accelerometerEventStream().listen((event) {
      // Ignore flat positions and diagonal motion near an orientation boundary.
      final x = event.x.abs();
      final y = event.y.abs();
      if (math.max(x, y) < 6.5 || (x - y).abs() < 2) return;
      final target = x > y ? (event.x > 0 ? 1 : -1) : (event.y > 0 ? 0 : 2);
      final step = (target - _iconQuarterTurns + 2) % 4 - 2;
      if (step != 0 && mounted) {
        setState(() {
          _iconQuarterTurns += step;
          _gestureAdjustment = null;
          _edgeGestureRejected = _viewfinderPointers.isNotEmpty;
        });
      }
    }, onError: (Object _) {});
  }

  StreamSubscription<GeoData?>? _geoSub;
  GeoData? _geo;
  Timer? _fixExpiry;

  GeoData? get _freshGeo {
    final geo = _geo;
    return geo != null && geo.hasFreshFix(DateTime.now()) ? geo : null;
  }

  GeoData? get _usableGeo {
    final geo = _freshGeo;
    return geo != null && geo.accuracy <= _settings.gpsAccuracyLimit
        ? geo
        : null;
  }

  GeoData? _captureGeo;
  int _captureQuarterTurns = 0;
  bool _locationUnavailable = false;

  // Live magnetometer compass (GPS heading is only valid while moving).
  // Kept in a ValueNotifier so compass ticks only repaint the stamp widget
  // instead of rebuilding the entire camera screen at ~12 fps.
  StreamSubscription<CompassEvent>? _compassSub;
  final ValueNotifier<double?> _compassHeading = ValueNotifier(null);
  DateTime _lastCompassTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Geo snapshot with the live compass heading folded in (used by the stamp,
  /// mini-map pin and capture so the heading/compass update in real time).
  GeoData? get _stampGeo =>
      _usableGeo?.copyWith(heading: _compassHeading.value);

  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  String? _cameraError;
  bool _cameraPermissionError = false;

  bool get _cameraReady =>
      !_pausedByLifecycle && _cam?.value.isInitialized == true;

  bool _discoveringCameras = false;
  bool _initializing = false; // guard against concurrent controller inits
  bool _pausedByLifecycle = false;

  double _zoom = 1, _minZoom = 1, _maxZoom = 8, _baseZoom = 1;
  double _exposure = 0, _minExp = 0, _maxExp = 0, _evStep = 0;
  FlashMode _flash = FlashMode.off;
  bool _focusLocked = false;
  int _focusLockRevision = 0;
  int _countdown = 0; // self-timer countdown shown over the viewfinder

  bool _settingsOpen = false; // app settings strip expanded
  bool _showPreview = false; // in-app preview of the last capture
  double _stampDragDx = 0, _stampDragDy = 0;
  String? _notificationMsg;
  Timer? _notificationTimer;

  CameraMode _captureMode = CameraMode.photo;

  bool _busy = false;
  Future<void>? _recordingOperation;
  Future<void>? _cameraRelease;
  bool get _recordingBusy => _recording || _recordingOperation != null;
  bool _recording = false;
  final _recElapsed = ValueNotifier(Duration.zero);
  final _videoClock = Stopwatch();
  DateTime? _videoStartedAt;
  final _videoSamples = <Map<String, Object>>[];
  bool _stampRecording = false;
  bool _keepVideoOriginal = false;
  bool _videoClock24 = false;
  bool _videoExporting = false;
  Timer? _recTimer;

  bool _showFreeze = false;
  ImageProvider? _frozenBg;
  bool _flash2 = false; // white shutter flash

  Offset? _focus;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Settings changes (grid, map type, formats…) are infrequent and may affect
    // top-level chrome, so rebuild the screen when they change.
    _settings.addListener(_onSettings);
    _initCamera();
    _listenForOrientation();
    _startLocation();
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
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    _geoSub?.cancel();
    _gestureReadoutTimer?.cancel();
    _orientationSub?.cancel();
    _fixExpiry?.cancel();
    _recElapsed.dispose();
    _compassSub?.cancel();
    _recTimer?.cancel();
    _focusTimer?.cancel();
    _notificationTimer?.cancel();
    _cam?.dispose();
    _compassHeading.dispose();
    super.dispose();
  }

  void _dismissMenus() {
    if (!_settingsOpen) return;
    setState(() {
      _settingsOpen = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_pausedByLifecycle) {
        _geoSub?.cancel();
        _geoSub = null;
        _orientationSub?.cancel();
        _orientationSub = null;
        _fixExpiry?.cancel();
        _cameraRelease = _pauseCameraForLifecycle();
      }
    } else if (state == AppLifecycleState.resumed) {
      _pausedByLifecycle = false;
      _listenForOrientation();
      if (_geoSub == null) _startLocation();
      unawaited(_resumeCameraAfterLifecycle());
    }
  }

  void _startLocation() {
    _geoSub?.cancel();
    _fixExpiry?.cancel();
    setState(() {
      _geo = null;
      _locationUnavailable = false;
    });
    _geoSub = _location.watch().listen((geo) {
      if (!mounted) return;
      setState(() {
        _geo = geo;
        _locationUnavailable = geo == null;
      });
      _fixExpiry?.cancel();
      final fixTime = geo?.fixTime;
      if (fixTime != null) {
        final remaining = fixTime
            .add(GeoData.fixLifetime)
            .difference(DateTime.now());
        _fixExpiry = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          () {
            if (mounted) setState(() {});
          },
        );
      }
    });
  }

  Future<void> _openCameraSettings() async {
    try {
      if (await Geolocator.openAppSettings()) return;
    } catch (_) {}
    _toast('Open your device settings to allow camera access');
  }

  void _retryCamera() => unawaited(_initCamera());

  Future<void> _resumeCameraAfterLifecycle() async {
    await _cameraRelease;
    if (!mounted || _pausedByLifecycle) return;
    if (_cameras.isEmpty) {
      await _initCamera();
      return;
    }
    while (_initializing && mounted && !_pausedByLifecycle) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || _pausedByLifecycle || _cam != null) return;
    await _setupController(_cameras[_camIndex]);
  }

  Future<void> _pauseCameraForLifecycle() async {
    _pausedByLifecycle = true;
    final cam = _cam;
    _cam = null;
    if (mounted) setState(() {});
    if (cam == null) {
      await _cameraRelease;
      return;
    }
    await _recordingOperation;
    if (cam.value.isRecordingVideo) {
      try {
        await _stopAndSaveVideo(cam);
      } catch (_) {}
    }
    await cam.dispose();
  }

  // ── Camera setup ───────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (!mounted || _pausedByLifecycle || _discoveringCameras) return;
    _discoveringCameras = true;
    setState(() => _cameraError = null);
    try {
      final cams = await availableCameras();
      if (!mounted || _pausedByLifecycle) return;
      if (cams.isEmpty) {
        _setCameraError();
        return;
      }
      _cameras = cams;
      final back = cams.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _camIndex = back >= 0 ? back : 0;
      await _setupController(_cameras[_camIndex]);
    } catch (error) {
      _setCameraError(error);
    } finally {
      _discoveringCameras = false;
    }
  }

  void _setCameraError([Object? error]) {
    if (!mounted || _pausedByLifecycle) return;
    final code = switch (error) {
      CameraException() => error.code,
      PlatformException() => error.code,
      _ => '',
    };
    setState(() {
      _cameraPermissionError =
          code.startsWith('CameraAccess') ||
          code.startsWith('AudioAccess') ||
          code == 'camera_permission';
      _cameraError = code.startsWith('AudioAccess')
          ? 'Microphone access is required to start the camera.'
          : _cameraPermissionError
          ? 'Allow camera access to take photos.'
          : 'Camera unavailable';
    });
  }

  Future<void> _setupController(CameraDescription d) async {
    if (!mounted || _initializing || _pausedByLifecycle) return;
    _initializing = true;
    setState(() => _cameraError = null);
    final c = CameraController(
      d,
      ResolutionPreset.ultraHigh,
      enableAudio: true,
    );
    try {
      await c.initialize();
      final limits = await Future.wait([
        c.getMinZoomLevel(),
        c.getMaxZoomLevel(),
        c.getMinExposureOffset().catchError((_) => 0.0),
        c.getMaxExposureOffset().catchError((_) => 0.0),
        c.getExposureOffsetStepSize().catchError((_) => 0.0),
      ]);
      final features = await CameraAdjustments.features(d);
      _minZoom = limits[0];
      _maxZoom = limits[1];
      _minExp = limits[2];
      _maxExp = limits[3];
      _evStep = limits[4];
      final zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
      await c.setZoomLevel(zoom);
      var exposure = _exposure.clamp(_minExp, _maxExp).toDouble();
      try {
        if (exposure != 0) await c.setExposureOffset(exposure);
      } on CameraException {
        exposure = 0;
      }
      var flash = features.flash ? _flash : FlashMode.off;
      try {
        await c.setFlashMode(flash);
      } on CameraException {
        flash = FlashMode.off;
      }
      final minKelvin = features.whiteBalanceMin ?? 0;
      final maxKelvin = features.whiteBalanceMax ?? 0;
      int? appliedKelvin;
      final savedKelvin = _kelvin;
      if (maxKelvin > minKelvin && savedKelvin != null) {
        final target = savedKelvin.clamp(minKelvin, maxKelvin);
        try {
          await CameraAdjustments.setWhiteBalance(c, target);
          appliedKelvin = target;
        } on PlatformException {
          // Keep the saved setting so it can be retried on a supported lens.
        }
      }
      if (!mounted || _pausedByLifecycle) {
        await c.dispose();
        _initializing = false;
        return;
      }
      setState(() {
        _cam = c;
        _focusLocked = false;
        _zoom = _appliedZoom = zoom;
        _exposure = _appliedExposure = exposure;
        _hasFlash = features.flash;
        _flash = flash;
        _minKelvin = minKelvin;
        _maxKelvin = maxKelvin;
        _appliedKelvin = appliedKelvin;
        if (appliedKelvin != null) _kelvin = appliedKelvin;
        if (!_whiteBalanceSupported) _editingWhiteBalance = false;
      });
    } catch (error) {
      _setCameraError(error);
      await c.dispose();
    } finally {
      _initializing = false;
    }
  }

  // ── Controls ───────────────────────────────────────────────────────────
  Future<void> _setZoom(double value) async {
    final camera = _cam;
    if (!_cameraReady || camera == null) return;
    final target = value.clamp(_minZoom, _maxZoom).toDouble();
    if (target == _zoom) return;
    setState(() => _zoom = target);
    if (_zoomPending) return;
    _zoomPending = true;
    try {
      while (mounted && identical(camera, _cam) && _appliedZoom != _zoom) {
        final next = _zoom;
        await camera.setZoomLevel(next);
        if (identical(camera, _cam)) _appliedZoom = next;
      }
    } on CameraException {
      if (mounted && identical(camera, _cam)) {
        setState(() => _zoom = _appliedZoom);
        _toast('Zoom unavailable');
      }
    } finally {
      _zoomPending = false;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _zoom;
    _gestureStartExposure = _exposure;
    _gestureStartKelvin = _whiteBalance;
  }

  void _onViewfinderPointerDown(PointerDownEvent event) {
    if (_viewfinderPointers.isEmpty) {
      _gestureOrigin = event.localPosition;
      _gestureQuarterTurns = _iconQuarterTurns % 4;
      _edgeGestureRejected = false;
      _hadPinch = false;
    } else {
      _hadPinch = true;
    }
    _viewfinderPointers.add(event.pointer);
  }

  void _onViewfinderPointerEnd(PointerEvent event) {
    _viewfinderPointers.remove(event.pointer);
  }

  // Convert fixed portrait coordinates into the space the user is holding.
  Offset _heldPoint(Offset point, Size frame, int turns) => switch (turns) {
    1 => Offset(point.dy, frame.width - point.dx),
    2 => Offset(frame.width - point.dx, frame.height - point.dy),
    3 => Offset(frame.height - point.dy, point.dx),
    _ => point,
  };

  void _onScaleUpdate(ScaleUpdateDetails details, Size box) {
    if (!_cameraReady || _busy || _countdown > 0) return;
    if (details.pointerCount >= 2) {
      _hadPinch = true;
      if (_maxZoom > _minZoom) {
        _showGestureValue(_Adjustment.zoom);
        _setZoom(_baseZoom * details.scale);
      }
      return;
    }
    if (_hadPinch || _edgeGestureRejected) return;
    final heldSize = _gestureQuarterTurns.isOdd ? box.flipped : box;
    final origin = _heldPoint(_gestureOrigin, box, _gestureQuarterTurns);
    final delta =
        _heldPoint(details.localFocalPoint, box, _gestureQuarterTurns) - origin;
    final edgeWidth = math.min(64.0, heldSize.width * .22);
    final isZoom = origin.dx >= heldSize.width - edgeWidth;
    final isExposure = origin.dx <= edgeWidth;
    if ((!isZoom && !isExposure) ||
        origin.dy > heldSize.height - math.min(48.0, heldSize.height * .2) ||
        (delta.dx.abs() >= 12 && delta.dx.abs() >= delta.dy.abs())) {
      _edgeGestureRejected = true;
      return;
    }
    if (delta.dy.abs() < 12) return;
    if (isZoom && _maxZoom > _minZoom) {
      _showGestureValue(_Adjustment.zoom);
      _setZoom(_baseZoom * math.pow(2, -delta.dy / 90));
    } else if (isExposure && _editingWhiteBalance) {
      _showGestureValue(_Adjustment.whiteBalance);
      _setWhiteBalance(_gestureStartKelvin - delta.dy * 20);
    } else if (isExposure && _maxExp > _minExp) {
      _showGestureValue(_Adjustment.exposure);
      _setExposure(_gestureStartExposure - delta.dy / 56);
    }
  }

  void _showGestureValue(_Adjustment adjustment) {
    _gestureReadoutTimer?.cancel();
    if (_gestureAdjustment == adjustment) return;
    setState(() {
      _gestureAdjustment = adjustment;
      if (_adjustment != adjustment) _adjustment = null;
      _focus = null;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _fadeGestureValue();
  }

  void _resetAdjustments() {
    final camera = _cam;
    if (!_cameraReady ||
        camera == null ||
        _busy ||
        _countdown > 0 ||
        _showFreeze) {
      return;
    }
    setState(() {
      _editingWhiteBalance = false;
      _adjustment = null;
      _edgeGestureRejected = _viewfinderPointers.isNotEmpty;
    });
    _showGestureValue(_Adjustment.reset);
    _setZoom(1);
    _setWhiteBalance(null);
    _resetExposureMode(camera);
    _setExposure(0, unlockFocus: false);
    _fadeGestureValue();
  }

  Future<void> _resetExposureMode(CameraController camera) async {
    final revision = ++_focusLockRevision;
    try {
      await _applyCameraInterop(
        camera,
        () => camera.setExposureMode(ExposureMode.auto),
      );
      if (mounted &&
          identical(camera, _cam) &&
          revision == _focusLockRevision) {
        setState(
          () => _focusLocked = camera.value.focusMode == FocusMode.locked,
        );
      }
    } on CameraException {
      if (mounted && identical(camera, _cam)) {
        _toast('Auto exposure unavailable');
      }
    }
  }

  // CameraX can supersede an unfinished interop update when a second arrives.
  Future<void> _applyCameraInterop(
    CameraController camera,
    Future<void> Function() update,
  ) {
    final operation = _cameraInterop.then((_) async {
      if (mounted && identical(camera, _cam)) await update();
    });
    _cameraInterop = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void _fadeGestureValue() {
    if (_gestureAdjustment == null) return;
    _gestureReadoutTimer?.cancel();
    _gestureReadoutTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _gestureAdjustment = null);
    });
  }

  void _toggleAdjustment(_Adjustment adjustment) {
    setState(() {
      _gestureAdjustment = null;
      _adjustment = _adjustment == adjustment ? null : adjustment;
    });
  }

  void _selectLeftAdjustment(_Adjustment adjustment) {
    if (!_cameraReady || _busy || _countdown > 0) return;
    if (_leftAdjustment == adjustment) {
      _toggleAdjustment(adjustment);
      return;
    }
    setState(() {
      _editingWhiteBalance = adjustment == _Adjustment.whiteBalance;
      _adjustment = adjustment;
      _gestureAdjustment = null;
      _focus = null;
      _edgeGestureRejected = _viewfinderPointers.isNotEmpty;
    });
  }

  Future<void> _setWhiteBalance(double? value) async {
    final camera = _cam;
    if (!_cameraReady || camera == null || !_whiteBalanceSupported) return;
    final target = value?.round().clamp(_minKelvin, _maxKelvin);
    if (target == _kelvin &&
        (target == _appliedKelvin || _whiteBalancePending)) {
      return;
    }
    setState(() => _kelvin = target);
    if (_whiteBalancePending) return;
    setState(() => _whiteBalancePending = true);
    try {
      while (mounted && identical(camera, _cam) && _appliedKelvin != _kelvin) {
        final next = _kelvin;
        await _applyCameraInterop(
          camera,
          () => CameraAdjustments.setWhiteBalance(camera, next),
        );
        if (identical(camera, _cam)) _appliedKelvin = next;
      }
    } on PlatformException {
      if (mounted && identical(camera, _cam)) {
        setState(() => _kelvin = _appliedKelvin);
        _toast('White balance adjustment unavailable');
      }
    } finally {
      if (mounted) setState(() => _whiteBalancePending = false);
    }
  }

  void _cycleTemplate(int dir) {
    const v = StampTemplate.values;
    final i =
        (v.indexOf(_templates.config.template) + dir + v.length) % v.length;
    _templates.selectTemplate(v[i]);

    _toast(v[i].title);
  }

  void _toggleMapSide(bool toLeft) {
    _templates.update((c) {
      c.mapSide = toLeft ? MapSide.left : MapSide.right;
    });
  }

  bool get _isFront =>
      _cameras.isNotEmpty &&
      _cameras[_camIndex].lensDirection == CameraLensDirection.front;

  bool get _canFlip =>
      _cameraReady &&
      _cameras.any(
        (camera) =>
            camera.lensDirection ==
            (_isFront ? CameraLensDirection.back : CameraLensDirection.front),
      );

  /// Toggle between the back and front camera (dual-camera switch).
  Future<void> _flip() async {
    if (_cameraChangesLocked) return;
    if (!_cameraReady || _cameras.length < 2) return;
    final want = _isFront
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final target = _cameras.indexWhere((c) => c.lensDirection == want);
    if (target < 0) return;
    _camIndex = target;
    final old = _cam;
    setState(() {
      _cam = null;
      _flipping = true;
      _adjustment = null;
      _focus = null;
    });
    final release = old?.dispose();
    _cameraRelease = release;
    try {
      await release;
      await _setupController(_cameras[_camIndex]);
    } finally {
      if (mounted) setState(() => _flipping = false);
    }
  }

  void _tapViewfinder(Offset local, Size box) {
    final turns = _iconQuarterTurns % 4;
    final heldSize = turns.isOdd ? box.flipped : box;
    final point = _heldPoint(local, box, turns);
    if (_cameraReady &&
        !_busy &&
        _countdown == 0 &&
        !_showFreeze &&
        !_settingsOpen &&
        heldSize.height >= 174 &&
        (point.dy - heldSize.height / 2).abs() <= 64) {
      const touchWidth = CameraAdjustmentRail.touchWidth + 1;
      if (point.dx <= touchWidth &&
          (_editingWhiteBalance || _minExp < _maxExp)) {
        _toggleAdjustment(_leftAdjustment);
        return;
      }
      if (point.dx >= heldSize.width - touchWidth && _minZoom < _maxZoom) {
        _toggleAdjustment(_Adjustment.zoom);
        return;
      }
    }
    _tapFocus(local, box);
  }

  Future<void> _tapFocus(Offset local, Size box) async {
    if (_settingsOpen) {
      _dismissMenus();
      return;
    }
    final cam = _cam;
    if (!_cameraReady || cam == null) return;
    setState(() {
      _focus = local;
      _gestureAdjustment = null;
      _adjustment = null;
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _focus = null);
    });
    final preview = cam.value.previewSize;
    if (preview != null) {
      final source = preview.flipped;
      final scale = math.max(
        box.width / source.width,
        box.height / source.height,
      );
      final width = source.width * scale;
      final height = source.height * scale;
      final p = Offset(
        ((local.dx + (width - box.width) / 2) / width).clamp(0.0, 1.0),
        ((local.dy + (height - box.height) / 2) / height).clamp(0.0, 1.0),
      );
      if (_focusLocked) await _setFocusLock(false);
      if (!mounted || _cam != cam) return;
      try {
        await cam.setFocusPoint(p);
      } on CameraException {
        // Some lenses have fixed focus.
      }
      try {
        await cam.setExposurePoint(p);
      } on CameraException {
        // Some camera implementations expose compensation only.
      }
    }
  }

  Future<void> _setExposure(double value, {bool unlockFocus = true}) async {
    final camera = _cam;
    if (!_cameraReady || camera == null || _maxExp <= _minExp) return;
    final snapped = _evStep > 0 ? (value / _evStep).round() * _evStep : value;
    final target = snapped.clamp(_minExp, _maxExp).toDouble();
    if (target == _exposure) return;
    setState(() => _exposure = target);
    if (_exposurePending) return;
    _exposurePending = true;
    try {
      if (unlockFocus && _focusLocked) await _setFocusLock(false);
      while (mounted && identical(camera, _cam)) {
        final next = _exposure;
        await camera.setExposureOffset(next);
        if (!mounted || !identical(camera, _cam)) return;
        // CameraX returns a compensation index. Keep the displayed value in EV.
        _appliedExposure = next;
        if (_exposure == next) break;
      }
    } on CameraException {
      if (mounted && identical(camera, _cam)) {
        setState(() => _exposure = _appliedExposure);
        _toast('Exposure adjustment unavailable');
      }
    } finally {
      _exposurePending = false;
    }
  }

  Future<void> _setFocusLock(bool lock) async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      if (lock) _toast('AE/AF lock unavailable in this mode');
      return;
    }
    final revision = ++_focusLockRevision;
    try {
      await cam.setFocusMode(lock ? FocusMode.locked : FocusMode.auto);
    } on CameraException {
      // Focus and exposure support can differ on the same lens.
    }
    if (!mounted || _cam != cam || revision != _focusLockRevision) return;
    try {
      await _applyCameraInterop(cam, () async {
        if (revision == _focusLockRevision) {
          await cam.setExposureMode(
            lock ? ExposureMode.locked : ExposureMode.auto,
          );
        }
      });
    } on CameraException {
      // Keep the focus result if exposure lock is unsupported.
    }
    if (!mounted || _cam != cam || revision != _focusLockRevision) return;
    final af = cam.value.focusMode == FocusMode.locked;
    final ae = cam.value.exposureMode == ExposureMode.locked;
    setState(() => _focusLocked = af || ae);
    if (lock) {
      _toast(switch ((ae, af)) {
        (true, true) => 'AE/AF locked',
        (true, false) => 'Exposure locked',
        (false, true) => 'Focus locked',
        _ => 'AE/AF lock unavailable',
      });
    }
  }

  Future<void> _cycleFlash() async {
    final camera = _cam;
    if (!_cameraReady || camera == null || !_hasFlash || _flashPending) return;
    final next = switch (_flash) {
      FlashMode.off =>
        _captureMode == CameraMode.video ? FlashMode.torch : FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always || FlashMode.torch => FlashMode.off,
    };
    await _setFlash(camera, next);
  }

  Future<void> _setFlash(CameraController camera, FlashMode mode) async {
    setState(() => _flashPending = true);
    try {
      await camera.setFlashMode(mode);
      if (mounted && identical(camera, _cam)) setState(() => _flash = mode);
    } on CameraException {
      if (mounted && identical(camera, _cam)) _toast('Flash unavailable');
    } finally {
      if (mounted) setState(() => _flashPending = false);
    }
  }

  void _selectCaptureMode(CameraMode mode) {
    if (mode == _captureMode || _cameraChangesLocked) return;
    setState(() {
      _captureMode = mode;
      _adjustment = null;
    });
    final camera = _cam;
    if (camera != null && _flash != FlashMode.off) {
      _setFlash(camera, FlashMode.off);
    }
  }

  bool get _cameraChangesLocked =>
      _recordingBusy ||
      _flipping ||
      _flashPending ||
      _whiteBalancePending ||
      _discoveringCameras ||
      _initializing ||
      _busy ||
      _countdown > 0;

  Future<void> _onShutter() async {
    if (!_cameraReady ||
        _countdown > 0 ||
        _flashPending ||
        (_whiteBalancePending && !_recording)) {
      return;
    }
    if (_captureMode == CameraMode.video) {
      if (_recordingOperation != null) return;
      final operation = _toggleRecording();
      setState(() => _recordingOperation = operation);
      try {
        await operation;
      } finally {
        _recordingOperation = null;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_busy) return;
    final t = _settings.timerSeconds;
    if (t > 0) {
      for (var s = t; s > 0; s--) {
        if (!mounted || !_cameraReady) break;
        setState(() => _countdown = s);
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = 0);
    }
    await _capturePhoto();
  }

  Future<void> _capturePhoto() async {
    if (!mounted || _busy || !_cameraReady) return;
    final shutterTime = DateTime.now();
    final stampQuarterTurns = _iconQuarterTurns;
    final captureGeo = _settings.stampEnabled
        ? (_stampGeo?.copyWith(time: shutterTime) ??
              GeoData.withoutLocation(shutterTime))
        : null;
    final geotag = _settings.saveLocation ? _usableGeo : null;
    if ((_settings.stampEnabled || _settings.saveLocation) &&
        _usableGeo == null) {
      _toast('GPS unavailable. Coordinates omitted.');
    }
    final saveOriginal = _settings.saveOriginal;
    final cam = _cam!;
    setState(() {
      _busy = true;
      _adjustment = null;
    });

    String? rawShotPath;
    try {
      rawShotPath = (await cam.takePicture()).path;
    } on CameraException {
      // Handle a failed hardware capture below.
    }
    if (!mounted) return;
    if (rawShotPath == null) {
      setState(() => _busy = false);
      _toast('Capture failed. Try again.');
      return;
    }
    const stampRatio = 3.5;
    final image = ResizeImage.resizeIfNeeded(
      (MediaQuery.sizeOf(context).width * stampRatio).ceil(),
      null,
      FileImage(File(rawShotPath)),
    );
    var decoded = true;
    await precacheImage(image, context, onError: (_, _) => decoded = false);
    if (!mounted) return;
    if (!decoded) {
      setState(() => _busy = false);
      _toast('Could not read the captured photo');
      return;
    }

    // 2. Show the shutter flash.
    if (!mounted) return;
    setState(() {
      _frozenBg = image;
      _captureGeo = captureGeo;
      _captureQuarterTurns = stampQuarterTurns;
      _showFreeze = true;
      _flash2 = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _flash2 = false);

    // 3. Start GPU rasterisation of the composite (stamp over live frame).
    final boundary =
        _freezeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    // toImage() snapshots the layer tree atomically before the next setState.
    final renderFuture = boundary != null
        ? CaptureService.instance.rasterize(boundary, pixelRatio: stampRatio)
        : Future<Uint8List?>.value(null);

    // 4. Restore the live preview while saving.
    if (!mounted) return;
    setState(() {
      _showFreeze = false;
      _captureGeo = null;
      _frozenBg = null;
    });

    // 5. Finish compositing and saving in the background.
    try {
      var bytes = await renderFuture;

      if (bytes != null) {
        final captures = CaptureService.instance;
        final tagged = await captures.setPhotoLocation(
          bytes,
          sourcePath: rawShotPath,
          latitude: geotag?.lat,
          longitude: geotag?.lon,
        );
        if (tagged == null && geotag != null) {
          _toast('Photo saved without a GPS geotag');
        }
        bytes = tagged ?? bytes;
        await captures.cacheLast(bytes);
        _templates.bumpPhotoNumber();
        final galleryRef = await captures.saveImageToGallery(bytes);
        final localCapture = await captures.saveLocalCapture(
          bytes,
          galleryRef: galleryRef,
        );
        if (mounted) setState(() => _lastShot = bytes);
        if (galleryRef == null) {
          _toast(
            localCapture == null
                ? 'Could not save the photo'
                : 'Photo available in the app gallery only',
          );
        }
        if (saveOriginal) {
          final saved = await captures.saveOriginalToGallery(
            rawShotPath,
            localCapture: localCapture,
            latitude: geotag?.lat,
            longitude: geotag?.lon,
          );
          if (!saved) _toast('Could not save the original photo');
        }
      } else if (mounted) {
        _toast('Capture failed');
      }
    } catch (_) {
      _toast('Could not finish saving the photo');
    } finally {
      if (mounted) setState(() => _busy = false);
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
        await cam.startVideoRecording();
        _videoStartedAt = DateTime.now();
        _stampRecording = _settings.stampEnabled;
        _keepVideoOriginal = _settings.saveOriginal;
        _videoClock24 = _settings.clock24;
        _videoSamples.clear();
        _videoClock
          ..reset()
          ..start();
        _sampleVideoLocation(0);
        if (!mounted || _pausedByLifecycle) return;
        _recElapsed.value = Duration.zero;
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            _sampleVideoLocation(_videoClock.elapsedMilliseconds);
            _recElapsed.value = _videoClock.elapsed;
          }
        });
        setState(() => _recording = true);
      } else {
        await _stopAndSaveVideo(cam);
      }
    } catch (_) {
      _toast('Recording error');
      if (mounted) {
        setState(() {
          _recording = false;
        });
      }
    }
  }

  void _sampleVideoLocation(int atMs) {
    if (!_stampRecording) return;
    final geo = _usableGeo;
    final config = _templates.config;
    final location = geo == null
        ? 'GPS unavailable'
        : [
            if (config.has(StampField.latLong))
              '${geo.lat.toStringAsFixed(6)}, ${geo.lon.toStringAsFixed(6)}',
            if (config.has(StampField.accuracy))
              geo.accuracyStr(_settings.unitSystem),
          ].join('  ');
    if (_videoSamples.isEmpty || _videoSamples.last['label'] != location) {
      _videoSamples.add({'atMs': atMs, 'label': location});
    }
  }

  Future<void> _stopAndSaveVideo(CameraController cam) async {
    _recTimer?.cancel();
    _videoClock.stop();
    try {
      final file = await cam.stopVideoRecording();
      if (mounted) setState(() => _videoExporting = true);
      unawaited(_exportVideo(file.path));
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _exportVideo(String path) async {
    final service = CaptureService.instance;
    final startedAt = _videoStartedAt;
    String? stamped;
    try {
      if (_stampRecording && startedAt != null) {
        _toast('Rendering video stamp…');
        stamped = await service.stampVideo(
          path,
          startedAt: startedAt,
          samples: List.of(_videoSamples),
          clock24: _videoClock24,
        );
      }
      final saved = await service.saveVideoToGallery(stamped ?? path);
      if (!saved) {
        _toast('Could not save video to the gallery');
      } else if (_stampRecording && stamped == null) {
        _toast('Original video saved without a stamp.');
      } else if (stamped != null &&
          _keepVideoOriginal &&
          !await service.saveVideoToGallery(path)) {
        _toast('Stamped video saved. Could not save the original.');
      } else {
        _toast(stamped == null ? 'Video saved' : 'Stamped video saved');
      }
      if (stamped != null && saved) await File(stamped).delete();
    } catch (_) {
      _toast('Could not finish video export');
    } finally {
      if (mounted) setState(() => _videoExporting = false);
    }
  }

  void _toast(String msg) {
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

  // ── Navigation ──────────────────────────────────────────────────────────
  void _openGallery() {
    if (_captureMode == CameraMode.video) {
      showVideoLibrary(context);
    } else if (_lastShot != null) {
      setState(() => _showPreview = true);
    } else {
      CaptureService.instance.openGallery();
    }
  }

  void _openStampSettings() {
    setState(() {
      _settingsOpen = true;
    });
  }

  void _openStampDesigns() {
    _dismissMenus();
    Navigator.of(context).push(SheetRoute(page: const TemplatesScreen()));
  }

  void _openStampEditor() {
    _dismissMenus();
    Navigator.of(context).push(SheetRoute(page: const CustomTemplateEditor()));
  }

  void _cycleRatio() {
    if (_cameraChangesLocked) return;
    _settings.update(() {
      const ratios = [
        CaptureRatio.r4_3,
        CaptureRatio.r16_9,
        CaptureRatio.r1_1,
        CaptureRatio.full,
      ];
      _settings.captureRatio =
          ratios[(ratios.indexOf(_settings.captureRatio) + 1) % ratios.length];
    });
  }

  void _cycleTimer() {
    _settings.update(() {
      const values = [0, 3, 10];
      _settings.timerSeconds =
          values[(values.indexOf(_settings.timerSeconds) + 1) % values.length];
    });
  }

  Widget _topBar({required bool canShowRails}) {
    final canAdjustPhoto =
        _captureMode == CameraMode.photo && !_cameraChangesLocked;
    final timerOn = _settings.timerSeconds != 0;
    final zoomSelected =
        _adjustment == _Adjustment.zoom ||
        _gestureAdjustment == _Adjustment.zoom;
    final exposureSelected =
        !_editingWhiteBalance &&
        (_adjustment == _Adjustment.exposure ||
            _gestureAdjustment == _Adjustment.exposure ||
            _exposure != 0);
    final turns = _iconQuarterTurns / 4;
    final flashIcon = switch (_flash) {
      FlashMode.auto => Icons.flash_auto_outlined,
      FlashMode.always => Icons.flash_on_outlined,
      FlashMode.torch => Icons.highlight_outlined,
      FlashMode.off => Icons.flash_off_outlined,
    };
    Text value(String text, {bool selected = false, bool enabled = true}) =>
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: !enabled
                ? Colors.white38
                : (selected ? cameraYellow : Colors.white),
          ),
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (_hasFlash)
            CameraAction(
              label:
                  '${_captureMode == CameraMode.video ? 'Torch' : 'Flash'} ${_flash == FlashMode.torch ? 'on' : _flash.name}',
              icon: flashIcon,
              plain: true,
              iconTurns: turns,
              selected: _flash != FlashMode.off,
              onTap: _flashPending ? null : _cycleFlash,
            ),
          CameraAction(
            label: 'Timer, ${timerOn ? '${_settings.timerSeconds}s' : 'off'}',
            icon: Icons.timer_off_outlined,
            plain: true,
            iconTurns: turns,
            selected: timerOn,
            onTap: canAdjustPhoto ? _cycleTimer : null,
            child: timerOn
                ? value(
                    '${_settings.timerSeconds}s',
                    selected: true,
                    enabled: canAdjustPhoto,
                  )
                : null,
          ),
          CameraAction(
            label: 'Aspect ratio, ${_settings.captureRatio.label}',
            plain: true,
            iconTurns: turns,
            onTap: canAdjustPhoto ? _cycleRatio : null,
            child: value(_settings.captureRatio.label, enabled: canAdjustPhoto),
          ),
          if (_whiteBalanceSupported && canShowRails)
            CameraAction(
              label:
                  'White balance, ${_kelvin == null ? 'Auto' : '$_whiteBalance K'}',
              plain: true,
              iconTurns: turns,
              selected: _editingWhiteBalance,
              onTap: () => _selectLeftAdjustment(_Adjustment.whiteBalance),
              child: value('WB', selected: _editingWhiteBalance),
            ),
          if (_maxExp > _minExp && canShowRails)
            CameraAction(
              label: 'Exposure ${_exposure.toStringAsFixed(1)} EV',
              icon: Icons.exposure_outlined,
              plain: true,
              iconTurns: turns,
              selected: exposureSelected,
              onTap: () => _selectLeftAdjustment(_Adjustment.exposure),
            ),
          if (_maxZoom > _minZoom && canShowRails)
            CameraAction(
              label: 'Zoom ${formatCameraZoom(_zoom)}',
              plain: true,
              iconTurns: turns,
              selected: zoomSelected,
              onTap: () => _toggleAdjustment(_Adjustment.zoom),
              child: value(formatCameraZoom(_zoom), selected: zoomSelected),
            ),
        ],
      ),
    );
  }

  Widget _adjustmentGrip(_Adjustment adjustment) {
    final zoom = adjustment == _Adjustment.zoom;
    final whiteBalance = adjustment == _Adjustment.whiteBalance;
    final label = zoom ? 'Zoom' : (whiteBalance ? 'WB' : 'EV');
    final name = whiteBalance ? 'White balance' : (zoom ? 'Zoom' : 'Exposure');
    final pinned = _adjustment == adjustment;
    final expanded = pinned || _gestureAdjustment == adjustment;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Positioned(
      left: zoom ? null : 1,
      right: zoom ? 1 : null,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: zoom ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox(
          width: CameraAdjustmentRail.touchWidth,
          height: 174,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: duration,
                reverseDuration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    for (final child in previous)
                      IgnorePointer(child: ExcludeSemantics(child: child)),
                    ?current,
                  ],
                ),
                child: expanded
                    ? IgnorePointer(
                        key: ValueKey(adjustment),
                        ignoring: !pinned,
                        child: GestureDetector(
                          onDoubleTap: _resetAdjustments,
                          child: CameraAdjustmentRail(
                            label: '$name adjustment',
                            value: whiteBalance
                                ? _whiteBalance.toDouble()
                                : (zoom ? _zoom : _exposure),
                            min: whiteBalance
                                ? _minKelvin.toDouble()
                                : (zoom ? _minZoom : _minExp),
                            max: whiteBalance
                                ? _maxKelvin.toDouble()
                                : (zoom ? _maxZoom : _maxExp),
                            exposure: !zoom && !whiteBalance,
                            whiteBalance: whiteBalance,
                            autoWhiteBalance: whiteBalance && _kelvin == null,
                            baseline: whiteBalance
                                ? _defaultKelvin.toDouble()
                                : null,
                            onChanged: (value) {
                              if (!zoom && adjustment != _leftAdjustment) {
                                return;
                              }
                              _showGestureValue(adjustment);
                              if (zoom) {
                                _setZoom(value);
                              } else if (whiteBalance) {
                                _setWhiteBalance(value);
                              } else {
                                _setExposure(value);
                              }
                            },
                            onChangeEnd: (_) => _fadeGestureValue(),
                          ),
                        ),
                      )
                    : Semantics(
                        key: ValueKey('camera-$label-hint'),
                        label: 'Show ${name.toLowerCase()} adjustment',
                        button: true,
                        onTap: () => _toggleAdjustment(adjustment),
                        child: IgnorePointer(
                          child: SizedBox(
                            width: CameraAdjustmentRail.touchWidth,
                            height: 128,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < 6; i++)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 2),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xCCFFFFFF),
                                        boxShadow: [
                                          BoxShadow(
                                            offset: Offset(0, 1),
                                            color: Colors.black,
                                          ),
                                        ],
                                      ),
                                      child: SizedBox.square(dimension: 2),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              if (whiteBalance && expanded)
                Positioned(
                  left: 46,
                  top: 158,
                  child: IgnorePointer(
                    child: Text(
                      '$_minKelvin–$_maxKelvin K',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                top: expanded ? 158 : 110,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuHandle() => Semantics(
    label: 'Close camera menu',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissMenus,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 80) _dismissMenus();
      },
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white54,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _stampMenu() => ListenableBuilder(
    listenable: Listenable.merge([_settings, _templates]),
    builder: (context, _) => CameraGlass(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _menuHandle(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'GPS Stamp',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _stampRow(
            'Burn into capture',
            _settings.stampEnabled ? 'On' : 'Off',
            () => _settings.update(
              () => _settings.stampEnabled = !_settings.stampEnabled,
            ),
          ),
          _stampRow(
            'Template',
            _templates.config.template.title,
            _openStampDesigns,
          ),
          for (final name in _templates.savedNames)
            _stampRow(
              'Saved design',
              name,
              () => _templates.applySavedTemplate(name),
            ),
          if (_templates.config.showsMap)
            _stampRow(
              'Map side',
              _templates.config.mapSide == MapSide.left ? 'Left' : 'Right',
              () => _toggleMapSide(_templates.config.mapSide != MapSide.left),
            ),
          _stampRow('Edit stamp', 'Customize', _openStampEditor),
          _stampRow(
            'Save original',
            _settings.saveOriginal ? 'On' : 'Off',
            () => _settings.update(
              () => _settings.saveOriginal = !_settings.saveOriginal,
            ),
          ),
          if (_captureMode == CameraMode.photo)
            _stampRow(
              'Embed GPS in photo metadata',
              _settings.saveLocation ? 'On' : 'Off',
              () => _settings.update(
                () => _settings.saveLocation = !_settings.saveLocation,
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'On the stamp, swipe up or down to switch designs. Swipe sideways to move the map. Hold to browse designs.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          _stampRow('Display & units', 'Settings', () {
            _dismissMenus();
            showSettingsCategory(context, SettingsCat.display);
          }),
          if (_locationUnavailable)
            _stampRow('Location unavailable', 'Retry', _startLocation),
        ],
      ),
    ),
  );

  Widget _stampRow(String label, String value, VoidCallback action) =>
      TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(double.infinity, 48),
          foregroundColor: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(color: cameraYellow),
              ),
            ),
          ],
        ),
      );

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;

    return PopScope(
      canPop: !_settingsOpen && !_showPreview && _adjustment == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showPreview) {
          setState(() => _showPreview = false);
        } else if (_settingsOpen) {
          _dismissMenus();
        } else {
          setState(() => _adjustment = null);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, c) {
            final screenW = c.maxWidth;
            final screenH = c.maxHeight;
            final controlBottom = bottomPad + 8;
            final dockTop = controlBottom + CameraControlBar.height;
            final headerBottom = topPad + 64;
            final areaH = math.max(1.0, screenH - headerBottom - dockTop);
            final wh = _captureMode == CameraMode.photo
                ? _settings.captureRatio.portraitWH
                : 9 / 16;
            final boxH = wh == null ? areaH : math.min(screenW / wh, areaH);
            final boxW = wh == null ? screenW : math.min(screenW, boxH * wh);
            final viewfinderLeft = (screenW - boxW) / 2;
            final viewfinderRight = viewfinderLeft;
            final boxSize = Size(boxW, boxH);
            final viewfinderTop = headerBottom + (areaH - boxH) / 2;
            const stampInset = 14.0;
            final heldHeight = _iconQuarterTurns.isOdd ? boxW : boxH;
            final canShowRails = heldHeight >= 174;
            final showControls = _cameraReady && !_showFreeze && !_settingsOpen;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Ratio-aware viewfinder box — no animated positioning so the
                // frame doesn't drift when the aspect ratio changes.
                Positioned(
                  top: viewfinderTop,
                  left: viewfinderLeft,
                  width: boxW,
                  height: boxH,
                  child: _Viewfinder(
                    rasterKey: _freezeKey,
                    controller: _cam,
                    frozen: _showFreeze ? _frozenBg : null,
                    focus: _focus,
                    stamp: ListenableBuilder(
                      listenable: Listenable.merge([
                        _templates,
                        _settings,
                        _compassHeading,
                      ]),
                      builder: (context, _) {
                        final geo = _showFreeze
                            ? _captureGeo
                            : (_settings.stampEnabled
                                  ? (_stampGeo ??
                                        GeoData.withoutLocation(DateTime.now()))
                                  : null);
                        if (geo == null) return const SizedBox.shrink();
                        return Positioned.fill(
                          child: RotatedBox(
                            quarterTurns: _showFreeze
                                ? _captureQuarterTurns
                                : _iconQuarterTurns,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  0,
                                  10,
                                  stampInset,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: _recordingBusy || _busy
                                      ? null
                                      : _openStampDesigns,
                                  onPanStart: (details) {
                                    _stampDragDx = 0;
                                    _stampDragDy = 0;
                                  },
                                  onPanUpdate: (details) {
                                    _stampDragDx += details.delta.dx;
                                    _stampDragDy += details.delta.dy;
                                  },
                                  onPanEnd: (details) {
                                    if (_recordingBusy || _busy) return;
                                    final absX = _stampDragDx.abs();
                                    final absY = _stampDragDy.abs();
                                    if (absY > absX * 1.3 && absY >= 40) {
                                      _cycleTemplate(_stampDragDy < 0 ? 1 : -1);
                                    } else if (absX > absY * 1.3 &&
                                        absX >= 40) {
                                      _toggleMapSide(_stampDragDx < 0);
                                    }
                                  },
                                  child: RepaintBoundary(
                                    child: GeoStamp(
                                      geo: geo,
                                      forCapture: _showFreeze,
                                      config: _templates.config,
                                      settings: _settings,
                                      onMapTap: _recordingBusy || _busy
                                          ? null
                                          : () {
                                              showMapZoomPopup(
                                                context,
                                                lat: geo.lat,
                                                lon: geo.lon,
                                                heading: geo.heading,
                                                kind: _settings.mapKind,
                                                initialZoom: _settings.mapZoom,
                                              );
                                            },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    onPointerDown: _onViewfinderPointerDown,
                    onPointerEnd: _onViewfinderPointerEnd,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: (details) =>
                        _onScaleUpdate(details, boxSize),
                    onScaleEnd: _onScaleEnd,
                    onTapFocus: (local) => _tapViewfinder(local, boxSize),
                    onDoubleTap: showControls ? _resetAdjustments : null,
                    onLongPress: (local) async {
                      if (_settingsOpen) {
                        _dismissMenus();
                        return;
                      }
                      await _tapFocus(local, boxSize);
                      if (mounted) await _setFocusLock(true);
                    },
                  ),
                ),

                if (_cameraError != null)
                  Positioned(
                    top: viewfinderTop,
                    left: 0,
                    right: 0,
                    height: boxH,
                    child: ColoredBox(
                      color: Palette.ink,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _cameraError!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _retryCamera,
                                    child: const Text('Retry'),
                                  ),
                                  if (_cameraPermissionError)
                                    TextButton(
                                      onPressed: _openCameraSettings,
                                      child: const Text('Open Settings'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (showControls)
                  Positioned(
                    top: topPad + 4,
                    left: 0,
                    right: 0,
                    height: 56,
                    child: _topBar(canShowRails: canShowRails),
                  ),
                if (showControls)
                  Positioned(
                    left: viewfinderLeft,
                    top: viewfinderTop,
                    width: boxW,
                    height: boxH,
                    child: RotatedBox(
                      quarterTurns: _iconQuarterTurns,
                      child: Stack(
                        children: [
                          if (canShowRails &&
                              (_editingWhiteBalance || _minExp < _maxExp))
                            _adjustmentGrip(_leftAdjustment),
                          if (canShowRails && _minZoom < _maxZoom)
                            _adjustmentGrip(_Adjustment.zoom),
                          for (final adjustment in _Adjustment.values)
                            Center(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  key: ValueKey(
                                    'camera-${adjustment.name}-readout',
                                  ),
                                  opacity: _gestureAdjustment == adjustment
                                      ? 1
                                      : 0,
                                  duration:
                                      mq.disableAnimations ||
                                          _gestureAdjustment != null
                                      ? Duration.zero
                                      : const Duration(milliseconds: 140),
                                  child: ExcludeSemantics(
                                    excluding: _gestureAdjustment != adjustment,
                                    child: Text(
                                      switch (adjustment) {
                                        _Adjustment.zoom => formatCameraZoom(
                                          _zoom,
                                        ),
                                        _Adjustment.exposure =>
                                          '${_exposure > 0 ? '+' : ''}${_exposure.toStringAsFixed(1)} EV',
                                        _Adjustment.whiteBalance =>
                                          _kelvin == null
                                              ? 'AWB'
                                              : '$_whiteBalance K',
                                        _Adjustment.reset =>
                                          '${formatCameraZoom(_zoom)}  ·  ${_exposure == 0 ? '0' : _exposure.toStringAsFixed(1)} EV  ·  ${_kelvin == null ? 'AWB' : '$_whiteBalance K'}',
                                      },
                                      style: AppText.metric.copyWith(
                                        color: Colors.white,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w600,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_notificationMsg != null && !_settingsOpen && !_recording)
                  Positioned(
                    top: viewfinderTop + 10,
                    left: viewfinderLeft + 16,
                    right: viewfinderRight + 16,
                    child: IgnorePointer(
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _notificationMsg!,
                            textAlign: TextAlign.center,
                            style: AppText.bodyHi.copyWith(
                              color: Colors.white,
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Recording indicator.
                if (_recording)
                  Positioned(
                    top: viewfinderTop + 10,
                    left: viewfinderLeft,
                    right: viewfinderRight,
                    child: Center(
                      child: ValueListenableBuilder(
                        valueListenable: _recElapsed,
                        builder: (context, elapsed, _) =>
                            _RecPill(elapsed: elapsed),
                      ),
                    ),
                  ),

                // Self-timer countdown.
                if (_countdown > 0)
                  Positioned(
                    top: viewfinderTop,
                    left: viewfinderLeft,
                    right: viewfinderRight,
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

                // Separate capture controls from the swipeable navigation row.
                Positioned(
                  left: Insets.xs,
                  right: Insets.xs,
                  bottom: controlBottom,
                  child: CameraControlBar(
                    mode: _captureMode,
                    iconTurns: _iconQuarterTurns / 4,
                    busy:
                        _busy ||
                        _recordingOperation != null ||
                        (_captureMode == CameraMode.video && _videoExporting),
                    lastShot: _lastShot,
                    onMode: _selectCaptureMode,
                    onShutter:
                        _cameraReady &&
                            _countdown == 0 &&
                            !_flashPending &&
                            (!_whiteBalancePending || _recording)
                        ? _onShutter
                        : null,
                    recording: _recording,
                    lockCameraChanges: _cameraChangesLocked,
                    onFlip: _canFlip ? _flip : null,
                    onGallery:
                        _recordingBusy ||
                            _busy ||
                            (_captureMode == CameraMode.video &&
                                _videoExporting)
                        ? null
                        : _openGallery,
                    onStamp: _recordingBusy || _busy
                        ? null
                        : _openStampSettings,
                  ),
                ),

                if (_settingsOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _dismissMenus,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: bottomPad + 8,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: screenH - topPad - bottomPad - 72,
                      ),
                      child: BlockSemantics(
                        child: SingleChildScrollView(child: _stampMenu()),
                      ),
                    ),
                  ),
                ],

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
                      onDeleted: () async {
                        final bytes = await CaptureService.instance.loadLast();
                        if (mounted) setState(() => _lastShot = bytes);
                      },
                      onOpenGallery: () =>
                          CaptureService.instance.openGallery(),
                      onOpenVideos: () => showVideoLibrary(context),
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

/// Full-screen viewer for the local captures (pinch-zoomable, swipeable), with a
/// page indicator, close button, and a shortcut to the phone's gallery.
class _PreviewOverlay extends StatefulWidget {
  final Uint8List latestBytes;
  final VoidCallback onClose;
  final Future<void> Function() onDeleted;
  final VoidCallback onOpenGallery;
  final VoidCallback onOpenVideos;
  const _PreviewOverlay({
    required this.latestBytes,
    required this.onClose,
    required this.onDeleted,
    required this.onOpenGallery,
    required this.onOpenVideos,
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
  bool _deleting = false;

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

  Future<void> _comparePhoto() async {
    if (_files.isEmpty || _deleting) return;
    final stamped = _files[_currentPage];
    final original = CaptureService.instance.originalFor(stamped);
    final hasOriginal = await original.exists();
    if (!mounted) return;
    var showOriginal = true;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            hasOriginal
                ? (showOriginal ? 'Original photo' : 'Stamped photo')
                : 'Original unavailable',
          ),
          content: hasOriginal
              ? Image.file(
                  showOriginal ? original : stamped,
                  fit: BoxFit.contain,
                )
              : const Text(
                  'Enable Save Original before taking a photo to compare both versions here.',
                ),
          actions: [
            if (hasOriginal)
              TextButton(
                onPressed: () =>
                    setDialogState(() => showOriginal = !showOriginal),
                child: Text(showOriginal ? 'Show stamped' : 'Show original'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMetadata() async {
    if (_files.isEmpty || _deleting) return;
    final data = await CaptureService.instance.photoMetadata(
      _files[_currentPage],
    );
    if (!mounted) return;
    final lat = data?['latitude'] as double?;
    final lon = data?['longitude'] as double?;
    final settings = SettingsController.instance;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo details'),
        content: data == null
            ? const Text('Photo metadata unavailable.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${data['width']} × ${data['height']} px'),
                  Text(
                    'Saved ${DateTime.fromMillisecondsSinceEpoch(data['modifiedMs'] as int).toLocal().toString().split('.').first}',
                  ),
                  const SizedBox(height: Insets.xs),
                  if (lat != null && lon != null)
                    Text('${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}')
                  else
                    const Text('No embedded GPS location'),
                ],
              ),
        actions: [
          if (lat != null && lon != null)
            TextButton(
              onPressed: () => showMapZoomPopup(
                context,
                lat: lat,
                lon: lon,
                heading: 0,
                kind: settings.mapKind,
                initialZoom: settings.mapZoom,
              ),
              child: const Text('Map'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    if (_files.isEmpty || _deleting) return;
    final file = _files[_currentPage];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.ink2,
        title: Text(
          'Delete photo?',
          style: AppText.bodyHi.copyWith(color: Palette.textHi),
        ),
        content: Text(
          'Removes this photo from the app and deletes its linked device gallery copy, if present.',
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
    final onDeleted = widget.onDeleted;
    setState(() => _deleting = true);
    try {
      await CaptureService.instance.deleteCapture(file);
      if (mounted) {
        setState(() {
          _files.remove(file);
          if (_currentPage >= _files.length && _currentPage > 0) {
            _currentPage = _files.length - 1;
          }
        });
        if (_files.isEmpty) {
          widget.onClose();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(_currentPage);
            }
          });
        }
      }
      await onDeleted();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not finish deleting the photo. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
    return BlockSemantics(
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
                      physics: _zoomed || _deleting
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
                    label: 'Close photo viewer',
                    onTap: widget.onClose,
                    blur: true,
                  ),
                  const Spacer(),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.info_outline,
                      label: 'Photo details',
                      onTap: _deleting ? null : _showMetadata,
                      blur: true,
                    ),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.share_outlined,
                      label: 'Share photo',
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
                    label: 'Open device gallery',
                    onTap: widget.onOpenGallery,
                    blur: true,
                  ),
                  if (Platform.isAndroid)
                    GlassIconButton(
                      icon: Icons.video_library_outlined,
                      label: 'Open video library',
                      onTap: widget.onOpenVideos,
                      blur: true,
                    ),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.compare_outlined,
                      label: 'Compare original photo',
                      onTap: _deleting ? null : _comparePhoto,
                      blur: true,
                    ),
                  const Spacer(),
                  if (!_loading && _files.isNotEmpty)
                    GlassIconButton(
                      icon: Icons.delete_outline,
                      label: 'Delete photo',
                      onTap: _deleting ? null : _delete,
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

    _anim = Matrix4Tween(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
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
/// rasterises exactly what's framed. Pinch to zoom, tap to focus, double-tap
/// to reset adjustments.
class _Viewfinder extends StatelessWidget {
  final GlobalKey rasterKey;
  final CameraController? controller;
  final ImageProvider? frozen;
  final Offset? focus;
  final Widget stamp;
  final PointerDownEventListener onPointerDown;
  final void Function(PointerEvent) onPointerEnd;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final ValueChanged<Offset> onTapFocus;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset> onLongPress;

  const _Viewfinder({
    required this.rasterKey,
    required this.controller,
    required this.frozen,
    required this.focus,
    required this.stamp,
    required this.onPointerDown,
    required this.onPointerEnd,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.onTapFocus,
    required this.onDoubleTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: onPointerDown,
      onPointerUp: onPointerEnd,
      onPointerCancel: onPointerEnd,
      child: GestureDetector(
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        onScaleEnd: onScaleEnd,
        onTapUp: (d) => onTapFocus(d.localPosition),
        onDoubleTap: onDoubleTap,
        onLongPressStart: (details) => onLongPress(details.localPosition),
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
                      child: frozen != null
                          ? Image(image: frozen!, fit: BoxFit.cover)
                          : RepaintBoundary(
                              child: CameraLayer(controller: controller),
                            ),
                    ),
                    stamp,
                  ],
                ),
              ),
            ),
            if (focus != null) _FocusReticle(key: ObjectKey(focus), at: focus!),
          ],
        ),
      ),
    );
  }
}

class _FocusReticle extends StatefulWidget {
  final Offset at;
  const _FocusReticle({super.key, required this.at});

  @override
  State<_FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<_FocusReticle>
    with SingleTickerProviderStateMixin {
  AnimationController? _animation;

  @override
  void dispose() {
    _animation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 54.0;
    const reticle = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        key: ValueKey('camera-focus-outline'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          border: Border.fromBorderSide(
            BorderSide(color: cameraYellow, width: 1.5),
          ),
        ),
      ),
    );
    final animation = MediaQuery.disableAnimationsOf(context)
        ? null
        : _animation ??= (AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 820),
          )..forward());
    return Positioned(
      left: widget.at.dx - size / 2,
      top: widget.at.dy - size / 2,
      child: IgnorePointer(
        child: animation != null
            ? FadeTransition(
                opacity: animation.drive(
                  Tween(
                    begin: 1.0,
                    end: 0.0,
                  ).chain(CurveTween(curve: const Interval(.82, 1))),
                ),
                child: ScaleTransition(
                  scale: animation.drive(
                    Tween(begin: 1.08, end: 1.0).chain(
                      CurveTween(
                        curve: const Interval(0, .16, curve: Curves.easeOut),
                      ),
                    ),
                  ),
                  child: reticle,
                ),
              )
            : reticle,
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
