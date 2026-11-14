import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/transitions.dart';
import '../../models/capture_options.dart';
import '../../models/geo_data.dart';
import '../../models/media_item.dart';
import '../../models/template.dart';
import '../../services/camera_adjustments.dart';
import '../../services/capture_service.dart';
import '../../services/location_service.dart';
import '../../services/media_image.dart';
import '../../services/media_library.dart';
import '../../services/native.dart';
import '../../services/native_location.dart';
import '../../state/settings_controller.dart';
import '../../state/state_machine.dart';
import '../../state/template_controller.dart';
import '../../widgets/geo_stamp.dart';
import '../../widgets/mini_map.dart';
import '../library/library_screen.dart';
import '../settings/app_settings.dart';
import '../templates/custom_template_editor.dart';
import '../templates/templates_screen.dart';
import 'widgets/camera_control_bar.dart';
import 'widgets/camera_design.dart';
import 'widgets/camera_chrome.dart';
import 'widgets/camera_layer.dart';

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
  final _library = MediaLibrary.instance;
  final _freezeKey = GlobalKey();
  final _stampKey = GlobalKey(); // The stamp alone, for video frames.
  final _stampSpaceKey = GlobalKey(); // The stamp's upright frame.
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

  StreamSubscription<List<double>>? _orientationSub;
  int _iconQuarterTurns = 0;

  void _listenForOrientation() {
    _orientationSub ??= Native.gravity().listen((g) {
      // Ignore flat positions and diagonal motion near an orientation boundary.
      final x = g[0].abs();
      final y = g[1].abs();
      if (math.max(x, y) < 6.5 || (x - y).abs() < 2) return;
      final target = x > y ? (g[0] > 0 ? 1 : -1) : (g[1] > 0 ? 0 : 2);
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

  StreamSubscription<GpsStatus>? _geoSub;
  GpsStatus _gps = const GpsStatus(GpsState.acquiring);
  GeoData? get _geo => _gps.fix;
  Timer? _fixExpiry;

  GeoData? get _freshGeo {
    final geo = _geo;
    return geo != null && geo.hasFreshFix(DateTime.now()) ? geo : null;
  }

  /// The newest fix within the accuracy limit that is still fresh. A weak
  /// fix in between (common indoors) does not blank the stamp while a good
  /// one from the last minute exists.
  GeoData? get _usableGeo {
    final now = DateTime.now();
    final geo = _freshGeo;
    if (geo != null && geo.accuracy <= _settings.gpsAccuracyLimit) return geo;
    final good = _lastGoodGeo;
    return good != null &&
            good.hasFreshFix(now) &&
            good.accuracy <= _settings.gpsAccuracyLimit
        ? good
        : null;
  }

  GeoData? _lastGoodGeo;

  GeoData? _captureGeo;
  int _captureQuarterTurns = 0;

  // Live magnetometer compass (GPS heading is only valid while moving).
  // Kept in a ValueNotifier so compass ticks only repaint the stamp widget
  // instead of rebuilding the entire camera screen at ~12 fps.
  StreamSubscription<double>? _compassSub;
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

  /// False once the microphone was refused. Photos and silent video still work.
  bool _audioEnabled = true;

  /// What the hardware session is doing. The single source of truth for
  /// whether the shutter, lens switch and mode changes are available.
  final _machine = CameraMachine();
  CameraPhase get _phase => _machine.state;

  bool get _cameraReady =>
      _machine.hasPreview && _cam?.value.isInitialized == true;
  bool get _capturing => _phase == CameraPhase.capturing;
  bool get _shooting => _capturing || _phase == CameraPhase.countdown;

  // The two reasons to hold the camera: the app is visible and nothing covers
  // this screen. Everything else follows from them in [_syncSession].
  bool _appVisible = true;
  bool _covered = false;
  bool get _wantCamera => mounted && _appVisible && !_covered;

  /// Opening, closing and switching run one at a time, in order.
  Future<void> _session = Future.value();
  Future<void>? _recordingOp;

  double _zoom = 1, _minZoom = 1, _maxZoom = 8, _baseZoom = 1;
  double _exposure = 0, _minExp = 0, _maxExp = 0, _evStep = 0;
  FlashMode _flash = FlashMode.off;
  bool _focusLocked = false;
  int _focusLockRevision = 0;
  int _countdown = 0; // self-timer countdown shown over the viewfinder
  int _countdownRun = 0;

  bool _settingsOpen = false; // app settings strip expanded
  double _stampDragDx = 0, _stampDragDy = 0;
  String? _notificationMsg;
  Timer? _notificationTimer;

  CameraMode _captureMode = CameraMode.photo;

  final _recElapsed = ValueNotifier(Duration.zero);
  final _videoClock = Stopwatch();
  _VideoJob? _video; // The recording in progress.
  bool _videoExporting = false;
  Timer? _recTimer;
  Future<void> _saves = Future.value(); // Photo saves, in shutter order.

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
    _library.addListener(_onSettings);
    _machine.addListener(_onSettings);
    _syncSession();
    unawaited(
      CaptureService.instance.migrateLegacyCaptures().then(
        (_) => _library.refresh(),
      ),
    );
  }

  void _onCompass(double h) {
    if (!mounted) return;
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
    _library.removeListener(_onSettings);
    _machine
      ..removeListener(_onSettings)
      ..go(CameraPhase.released);
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
    _machine.dispose();
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
    // A dialog or the notification shade leaves the app visible, so the
    // preview keeps running. Only leaving the screen releases the camera.
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible == _appVisible) return;
    _appVisible = visible;
    _syncSession();
  }

  /// Runs the camera, GPS and sensors only while this screen is in front.
  void _syncSession() {
    if (_wantCamera) {
      _listenForOrientation();
      _compassSub ??= Native.heading().listen(
        _onCompass,
        onError: (Object _) {},
      );
      unawaited(_openCamera());
    } else {
      _stopLocation();
      _orientationSub?.cancel();
      _orientationSub = null;
      _compassSub?.cancel();
      _compassSub = null;
      unawaited(_closeCamera());
    }
  }

  bool _locationStarting = false;

  /// Explains why location is needed before Android asks for it, so the user
  /// knows coordinates are sent to the map and address services.
  Future<void> _beginLocation() async {
    if (_locationStarting) return;
    _locationStarting = true;
    try {
      var ask = true;
      if ((await NativeLocation.access()).permit == LocationPermit.denied) {
        if (!mounted) return;
        ask = await _explainLocation();
      }
      if (mounted && _wantCamera) _startLocation(ask: ask);
    } catch (_) {
      if (mounted && _wantCamera) _startLocation();
    } finally {
      _locationStarting = false;
    }
  }

  Future<bool> _explainLocation() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.surfaceSolid,
        title: const Text('Location for your stamp'),
        content: const Text(
          'Location is used while the app is open to add coordinates, an '
          'address and a small map to your photos and videos. To draw the map '
          'and find the address, your position is sent to our map provider '
          '(Esri) and your phone\'s address service. We don\'t store or sell '
          'your location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _startLocation({bool ask = true}) {
    _stopLocation();
    setState(() => _gps = const GpsStatus(GpsState.acquiring));
    _geoSub = _location.watch(ask: ask).listen((status) {
      if (!mounted) return;
      final fix = status.fix;
      setState(() {
        _gps = status;
        if (fix != null && fix.accuracy <= _settings.gpsAccuracyLimit) {
          _lastGoodGeo = fix;
        }
      });
      _fixExpiry?.cancel();
      final fixTime = status.fix?.fixTime;
      if (fixTime != null) {
        // Rebuild when the fix ages out so it stops being shown as current.
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

  void _stopLocation() {
    _geoSub?.cancel();
    _geoSub = null;
    _fixExpiry?.cancel();
  }

  Future<void> _openCameraSettings() async {
    try {
      if (await NativeLocation.openAppSettings()) return;
    } catch (_) {}
    _toast('Open your device settings to allow camera access');
  }

  void _retryCamera() => unawaited(_openCamera());

  Future<void> _enqueue(Future<void> Function() operation) {
    final run = _session.then((_) => operation());
    _session = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // ── Camera session ─────────────────────────────────────────────────────
  Future<void> _openCamera() => _enqueue(() async {
    if (!_wantCamera || _cam != null) return;
    if (!_machine.go(CameraPhase.initializing)) return;
    setState(() => _cameraError = null);
    try {
      if (_cameras.isEmpty) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          _failCamera();
          return;
        }
        _cameras = cameras;
        final back = cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _camIndex = back >= 0 ? back : 0;
      }
      await _startController(_cameras[_camIndex]);
    } catch (error) {
      _failCamera(error);
    } finally {
      // After the camera's own permission prompts, so dialogs never overlap.
      if (_wantCamera && _geoSub == null) unawaited(_beginLocation());
    }
  });

  Future<void> _closeCamera() => _enqueue(() async {
    if (_wantCamera) return; // Back in front before the release ran.
    await _finishRecording();
    final camera = _cam;
    _cam = null;
    if (_phase != CameraPhase.released) _machine.go(CameraPhase.suspended);
    await camera?.dispose();
  });

  /// A recording is always finalized and saved before the camera is released.
  Future<void> _finishRecording() async {
    try {
      await _recordingOp;
    } catch (_) {}
    final camera = _cam;
    if (camera == null || !camera.value.isRecordingVideo) return;
    _machine.go(CameraPhase.stoppingRecording);
    try {
      await _stopAndSaveVideo(camera);
    } catch (_) {}
  }

  void _failCamera([Object? error]) {
    if (!mounted) return;
    if (!_wantCamera) {
      _machine.go(CameraPhase.suspended);
      return;
    }
    final code = switch (error) {
      CameraException() => error.code,
      PlatformException() => error.code,
      _ => '',
    };
    setState(() {
      _cameraPermissionError =
          code.startsWith('CameraAccess') || code == 'camera_permission';
      _cameraError = _cameraPermissionError
          ? 'Allow camera access to take photos.'
          : 'Camera unavailable';
    });
    _machine.go(CameraPhase.error);
  }

  /// Opens [d] and applies the saved zoom, exposure, flash and white balance.
  /// Called with the phase already at [CameraPhase.initializing].
  Future<void> _startController(CameraDescription d) async {
    // `max` lets each use case take the sensor's native best. A fixed video
    // preset forces stills to 16:9, which crops 4:3 photos and, on some
    // devices, returns JPEGs with a padded green edge.
    final c = CameraController(
      d,
      ResolutionPreset.max,
      enableAudio: _audioEnabled,
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
      if (!_wantCamera) {
        await c.dispose();
        if (mounted) _machine.go(CameraPhase.suspended);
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
      _machine.go(CameraPhase.previewing);
    } catch (error) {
      await c.dispose();
      final code = error is CameraException ? error.code : '';
      if (code.startsWith('AudioAccess') && _audioEnabled) {
        // The camera does not need the microphone. Carry on without sound.
        _audioEnabled = false;
        _toast('Microphone is off. Videos will record without sound.');
        return _startController(d);
      }
      _failCamera(error);
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
    if (!_cameraReady || _shooting) return;
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
    if (!_cameraReady || camera == null || _shooting || _showFreeze) return;
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
    if (!_cameraReady || _shooting) return;
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
    const v = offeredTemplates;
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
    if (_cameraChangesLocked || !_cameraReady || _cameras.length < 2) return;
    final want = _isFront
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final target = _cameras.indexWhere((c) => c.lensDirection == want);
    if (target < 0 || !_machine.go(CameraPhase.switching)) return;
    setState(() {
      _adjustment = null;
      _focus = null;
    });
    await _enqueue(() async {
      final old = _cam;
      _cam = null;
      if (mounted) setState(() {});
      await old?.dispose();
      _camIndex = target;
      if (!_wantCamera) {
        if (mounted) _machine.go(CameraPhase.suspended);
        return;
      }
      _machine.go(CameraPhase.initializing);
      try {
        await _startController(_cameras[_camIndex]);
      } catch (error) {
        _failCamera(error);
      }
    });
  }

  void _tapViewfinder(Offset local, Size box) {
    final turns = _iconQuarterTurns % 4;
    final heldSize = turns.isOdd ? box.flipped : box;
    final point = _heldPoint(local, box, turns);
    if (_cameraReady &&
        !_shooting &&
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
      !_machine.canReconfigure || _flashPending || _whiteBalancePending;

  Future<void> _onShutter() async {
    if (!_cameraReady || _flashPending) return;
    if (_phase == CameraPhase.countdown) {
      // A second press cancels the self-timer.
      _countdownRun++;
      _machine.go(CameraPhase.previewing);
      setState(() => _countdown = 0);
      return;
    }
    if (_captureMode == CameraMode.video) {
      if (_recordingOp != null) return;
      if (_whiteBalancePending && !_machine.isRecording) return;
      final operation = _toggleRecording();
      _recordingOp = operation;
      try {
        await operation;
      } finally {
        _recordingOp = null;
      }
      return;
    }
    if (_phase != CameraPhase.previewing || _whiteBalancePending) return;
    final seconds = _settings.timerSeconds;
    if (seconds > 0) {
      if (!_machine.go(CameraPhase.countdown)) return;
      final run = ++_countdownRun;
      for (var s = seconds; s > 0; s--) {
        setState(() => _countdown = s);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        // Cancelled, or the camera was released while counting.
        if (run != _countdownRun || _phase != CameraPhase.countdown) {
          if (run == _countdownRun) setState(() => _countdown = 0);
          return;
        }
      }
      setState(() => _countdown = 0);
    }
    await _capturePhoto();
  }

  void _endCapture() {
    if (_capturing) _machine.go(CameraPhase.previewing);
  }

  Future<void> _capturePhoto() async {
    final cam = _cam;
    if (!mounted || cam == null || !_cameraReady) return;
    if (!_machine.go(CameraPhase.capturing)) return;
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
    setState(() => _adjustment = null);

    String? rawShotPath;
    try {
      rawShotPath = (await cam.takePicture()).path;
    } on CameraException {
      // Handle a failed hardware capture below.
    }
    if (!mounted) return;
    if (rawShotPath == null) {
      _endCapture();
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
      _endCapture();
      _toast('Could not read the captured photo');
      return;
    }

    // Freeze the frame under the stamp and flash the shutter.
    setState(() {
      _frozenBg = image;
      _captureGeo = captureGeo;
      _captureQuarterTurns = stampQuarterTurns;
      _showFreeze = true;
      _flash2 = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _flash2 = false);

    // The snapshot captures the layer tree now, before the preview returns.
    final boundary =
        _freezeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final snapshot = boundary == null
        ? Future<ui.Image?>.value()
        : CaptureService.instance.snapshot(boundary, pixelRatio: stampRatio);

    setState(() {
      _showFreeze = false;
      _captureGeo = null;
      _frozenBg = null;
    });
    // The camera is free for the next shot. Saving continues in order.
    _endCapture();
    final raw = rawShotPath;
    _saves = _saves.then(
      (_) => _savePhoto(
        raw,
        snapshot,
        taken: shutterTime,
        geotag: geotag,
        quarterTurns: stampQuarterTurns,
        saveOriginal: saveOriginal,
      ),
    );
  }

  /// Encode, tag, write, then publish to the Library. Each step runs only
  /// after the one before it succeeded.
  Future<void> _savePhoto(
    String rawShotPath,
    Future<ui.Image?> snapshot, {
    required DateTime taken,
    required GeoData? geotag,
    required int quarterTurns,
    required bool saveOriginal,
  }) async {
    final captures = CaptureService.instance;
    try {
      final frame = await snapshot;
      var bytes = frame == null ? null : await captures.encodeJpeg(frame);
      if (bytes == null) {
        _toast('Capture failed');
        return;
      }
      final tagged = await captures.setPhotoLocation(
        bytes,
        sourcePath: rawShotPath,
        latitude: geotag?.lat,
        longitude: geotag?.lon,
        quarterTurns: quarterTurns,
      );
      if (tagged == null && geotag != null) {
        _toast('Photo saved without a GPS geotag');
      }
      bytes = tagged ?? bytes;
      final uri = await captures.saveImageToGallery(bytes, taken: taken);
      if (uri == null) {
        _toast('Could not save the photo');
        return;
      }
      _templates.bumpPhotoNumber();
      String? originalKey;
      if (saveOriginal) {
        final original = await captures.saveOriginalToGallery(
          rawShotPath,
          taken: taken,
          latitude: geotag?.lat,
          longitude: geotag?.lon,
        );
        if (original == null) _toast('Could not save the original photo');
        originalKey = CaptureService.mediaKey(original, video: false);
      }
      final location = geotag == null
          ? null
          : MediaLocation(geotag.lat, geotag.lon, place: geotag.place);
      final key = CaptureService.mediaKey(uri, video: false);
      if (key != null) {
        await _library.index.recordCapture(
          key,
          location: location,
          originalKey: originalKey,
        );
      }
      if (originalKey != null) {
        await _library.index.recordCapture(originalKey, location: location);
      }
      unawaited(_library.refresh());
    } catch (_) {
      _toast('Could not finish saving the photo');
    } finally {
      await _deleteQuietly(rawShotPath);
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _toggleRecording() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    if (_machine.isRecording) {
      _machine.go(CameraPhase.stoppingRecording);
      try {
        await _stopAndSaveVideo(cam);
      } catch (_) {
        _toast('Recording error');
      } finally {
        if (_phase == CameraPhase.stoppingRecording) {
          _machine.go(CameraPhase.previewing);
        }
      }
      return;
    }
    if (_videoExporting || !_machine.go(CameraPhase.startingRecording)) return;
    try {
      await cam.startVideoRecording();
    } catch (_) {
      _toast('Recording error');
      if (_phase == CameraPhase.startingRecording) {
        _machine.go(CameraPhase.previewing);
      }
      return;
    }
    final geo = _settings.saveLocation ? _usableGeo : null;
    _video = _VideoJob(
      startedAt: DateTime.now(),
      quarterTurns: _iconQuarterTurns,
      stamp: _settings.stampEnabled,
      keepOriginal: _settings.saveOriginal,
      clock24: _settings.clock24,
      location: geo == null
          ? null
          : MediaLocation(geo.lat, geo.lon, place: geo.place),
    );
    _videoClock
      ..reset()
      ..start();
    _sampleVideoLocation(0);
    _recElapsed.value = Duration.zero;
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _sampleVideoLocation(_videoClock.elapsedMilliseconds);
        _recElapsed.value = _videoClock.elapsed;
      }
    });
    _machine.go(CameraPhase.recording);
  }

  void _sampleVideoLocation(int atMs) {
    final job = _video;
    if (job == null || !job.stamp) return;
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
    if (job.samples.isEmpty || job.samples.last['label'] != location) {
      job.samples.add({'atMs': atMs, 'label': location});
    }
    // ~11 m steps, so GPS jitter alone never re-renders the stamp.
    final frameLabel = geo == null
        ? ''
        : '${geo.place}|${geo.lat.toStringAsFixed(4)},'
              '${geo.lon.toStringAsFixed(4)}';
    if (frameLabel != job.frameLabel) {
      job.frameLabel = frameLabel;
      job.frameDue = true;
    }
    if (job.frameDue &&
        (job.lastFrameMs < 0 || atMs - job.lastFrameMs >= 10000)) {
      job.frameDue = false;
      job.lastFrameMs = atMs;
      unawaited(_captureStampFrame(job, atMs));
    }
  }

  /// Saves a picture of the stamp exactly as it is drawn on screen.
  Future<void> _captureStampFrame(_VideoJob job, int atMs) async {
    final stamp = _stampKey.currentContext?.findRenderObject();
    // Measured inside the rotated stamp layer, so a sideways recording places
    // the stamp in the upright (landscape) frame, as a sideways photo does.
    final frame = _stampSpaceKey.currentContext?.findRenderObject();
    if (stamp is! RenderRepaintBoundary || frame is! RenderBox) return;
    if (!stamp.hasSize || !frame.hasSize || frame.size.isEmpty) return;
    try {
      final origin = stamp.localToGlobal(Offset.zero, ancestor: frame);
      final size = frame.size;
      job.stampRect ??= [
        origin.dx / size.width,
        (size.height - origin.dy - stamp.size.height) / size.height,
        stamp.size.width / size.width,
      ];
      final image = await stamp.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;
      final file = File(
        '${Directory.systemTemp.path}/stamp_'
        '${job.startedAt.millisecondsSinceEpoch}_$atMs.png',
      );
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      job.frames.add({'atMs': atMs, 'path': file.path});
    } catch (_) {
      // The text stamp is the fallback when no picture exists.
    }
  }

  Future<void> _stopAndSaveVideo(CameraController cam) async {
    _recTimer?.cancel();
    _videoClock.stop();
    final job = _video;
    _video = null;
    final file = await cam.stopVideoRecording();
    if (job == null) return;
    if (mounted) setState(() => _videoExporting = true);
    unawaited(_exportVideo(file.path, job));
  }

  /// Stamp, write, then publish. The recording stays in the cache until its
  /// gallery copy exists.
  Future<void> _exportVideo(String path, _VideoJob job) async {
    final service = CaptureService.instance;
    String? stamped;
    try {
      if (job.stamp) {
        _toast('Rendering video stamp…');
        stamped = await service.stampVideo(
          path,
          startedAt: job.startedAt,
          samples: job.samples,
          clock24: job.clock24,
          frames: job.frames,
          stampRect: job.stampRect,
          quarterTurns: job.quarterTurns,
        );
      }
      final uri = await service.saveVideoToGallery(
        stamped ?? path,
        taken: job.startedAt,
        stamped: stamped != null,
      );
      if (uri == null) {
        _toast('Could not save video to the gallery');
        return;
      }
      String? original;
      var message = stamped != null
          ? 'Stamped video saved'
          : (job.stamp
                ? 'Original video saved without a stamp.'
                : 'Video saved');
      if (stamped != null && job.keepOriginal) {
        original = await service.saveVideoToGallery(path, taken: job.startedAt);
        if (original == null) {
          message = 'Stamped video saved. Could not save the original.';
        }
      }
      for (final saved in [uri, original]) {
        final key = CaptureService.mediaKey(saved, video: true);
        if (key != null) {
          await _library.index.recordCapture(key, location: job.location);
        }
      }
      _toast(message);
      await _deleteQuietly(path);
      if (stamped != null) await _deleteQuietly(stamped);
      for (final frame in job.frames) {
        await _deleteQuietly(frame['path']! as String);
      }
      unawaited(_library.refresh());
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
  /// The Library covers this screen, so the camera and GPS rest meanwhile.
  Future<void> _openLibrary() async {
    if (_covered) return;
    _covered = true;
    _syncSession();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));
    _covered = false;
    if (mounted) _syncSession();
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
          _stampRow('Display & units', 'Settings', () {
            _dismissMenus();
            showSettingsCategory(context, SettingsCat.display);
          }),
          // Privacy, open-source licences, map credits and version.
          _stampRow('About', 'Privacy & licences', () {
            _dismissMenus();
            showSettingsCategory(context, SettingsCat.about);
          }),
          if (_gpsNotice() case (final label, final action, final onTap))
            _stampRow(label, action, onTap),
        ],
      ),
    ),
  );

  /// Why there is no usable position, and the one action that helps.
  (String, String, VoidCallback)? _gpsNotice() {
    Future<void> appSettings() => NativeLocation.openAppSettings();
    final accuracy = _freshGeo?.accuracy;
    return switch (_gps.stateAt(DateTime.now())) {
      GpsState.permissionRequired => (
        'Location permission needed',
        'Allow',
        _beginLocation,
      ),
      GpsState.permissionDenied => (
        'Location permission is off',
        'Open Settings',
        appSettings,
      ),
      GpsState.disabled => (
        'Location is turned off',
        'Turn on',
        NativeLocation.openLocationSettings,
      ),
      GpsState.acquiring => ('GPS', 'Searching…', () {}),
      GpsState.stale ||
      GpsState.unavailable => ('No GPS signal', 'Retry', _startLocation),
      GpsState.fix when _gps.approximate => (
        'Approximate location only',
        'Open Settings',
        appSettings,
      ),
      GpsState.fix when accuracy != null && _usableGeo == null => (
        'Weak GPS signal',
        '±${accuracy.round()} m',
        () {},
      ),
      GpsState.fix => null,
    };
  }

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
      canPop: !_settingsOpen && _adjustment == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_settingsOpen) {
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
            // Video fills the width at 9:16, like the system camera, and runs
            // under the shutter dock instead of shrinking between black bars.
            final fullWidthVideo = _captureMode == CameraMode.video;
            final double boxH;
            final double boxW;
            final double viewfinderTop;
            if (fullWidthVideo) {
              boxW = screenW;
              boxH = screenW / (wh ?? 9 / 16);
              viewfinderTop = boxH <= screenH - headerBottom
                  ? headerBottom
                  : math.max(0.0, screenH - boxH);
            } else {
              boxH = wh == null ? areaH : math.min(screenW / wh, areaH);
              boxW = wh == null ? screenW : math.min(screenW, boxH * wh);
              viewfinderTop = headerBottom + (areaH - boxH) / 2;
            }
            final viewfinderLeft = (screenW - boxW) / 2;
            final viewfinderRight = viewfinderLeft;
            final boxSize = Size(boxW, boxH);
            // Keep the stamp clear of the dock that overlaps the frame.
            final dockOverlap = math.max(
              0.0,
              viewfinderTop + boxH - (screenH - dockTop),
            );
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
                        final turns =
                            (_showFreeze
                                ? _captureQuarterTurns
                                : _iconQuarterTurns) %
                            4;
                        // The dock covers the physical bottom of the frame; in
                        // the rotated stamp layer that is a different edge.
                        final clear = EdgeInsets.fromLTRB(
                          turns == 3 ? dockOverlap : 0,
                          turns == 2 ? dockOverlap : 0,
                          turns == 1 ? dockOverlap : 0,
                          turns == 0 ? dockOverlap : 0,
                        );
                        return Positioned.fill(
                          child: RotatedBox(
                            quarterTurns: turns,
                            child: Align(
                              key: _stampSpaceKey,
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      stampInset,
                                    ) +
                                    clear,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress:
                                      _machine.recordingBusy || _capturing
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
                                    if (_machine.recordingBusy || _capturing) {
                                      return;
                                    }
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
                                    key: _stampKey,
                                    child: GeoStamp(
                                      geo: geo,
                                      forCapture: _showFreeze,
                                      recording: _machine.recordingBusy,
                                      config: _templates.config,
                                      settings: _settings,
                                      onMapTap:
                                          _machine.recordingBusy || _capturing
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

                if (_phase == CameraPhase.error && _cameraError != null)
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
                if (_notificationMsg != null &&
                    !_settingsOpen &&
                    !_machine.isRecording)
                  Positioned(
                    top: viewfinderTop + 10,
                    left: viewfinderLeft + 16,
                    right: viewfinderRight + 16,
                    child: IgnorePointer(
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          // A plain, solid notice that reads on any scene.
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Palette.surfaceSolid,
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                _notificationMsg!,
                                textAlign: TextAlign.center,
                                style: AppText.bodyHi.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Recording indicator.
                if (_machine.isRecording)
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
                if (_phase == CameraPhase.countdown && _countdown > 0)
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
                        _capturing ||
                        _phase == CameraPhase.startingRecording ||
                        _phase == CameraPhase.stoppingRecording ||
                        (_captureMode == CameraMode.video && _videoExporting),
                    lastShot: switch (_library.items.firstOrNull) {
                      final MediaItem newest => MediaThumbnail(newest),
                      null => null,
                    },
                    onMode: _selectCaptureMode,
                    onShutter:
                        _cameraReady &&
                            !_flashPending &&
                            (!_whiteBalancePending || _machine.isRecording)
                        ? _onShutter
                        : null,
                    recording: _machine.isRecording,
                    lockCameraChanges: _cameraChangesLocked,
                    onFlip: _canFlip ? _flip : null,
                    onGallery: _machine.recordingBusy || _capturing
                        ? null
                        : _openLibrary,
                    onStamp: _machine.recordingBusy || _capturing
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
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What a recording needs once it stops, fixed when it starts so a later
/// recording or settings change cannot alter it.
class _VideoJob {
  _VideoJob({
    required this.startedAt,
    required this.quarterTurns,
    required this.stamp,
    required this.keepOriginal,
    required this.clock24,
    required this.location,
  });

  final DateTime startedAt;
  final int quarterTurns; // How the phone was held when recording began.
  final bool stamp;
  final bool keepOriginal;
  final bool clock24;
  final MediaLocation? location;
  final samples = <Map<String, Object>>[];

  /// Pictures of the on-screen stamp, so the video carries the same stamp
  /// as a photo. A new one is taken when the place changes.
  final frames = <Map<String, Object>>[];
  List<double>? stampRect; // left, bottom gap, width: fractions of the frame
  int lastFrameMs = -1;
  String? frameLabel;
  bool frameDue = false;
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
