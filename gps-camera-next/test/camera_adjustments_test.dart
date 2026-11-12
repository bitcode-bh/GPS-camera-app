import 'dart:async';
import 'dart:math';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/screens/camera/camera_screen.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_design.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_layer.dart';
import 'package:gps_camera_next/screens/library/library_screen.dart';
import 'package:gps_camera_next/widgets/geo_stamp.dart';

class _Camera extends CameraPlatform {
  final ready = StreamController<CameraInitializedEvent>.broadcast();
  final zooms = <double>[];
  final exposures = <double>[];
  final exposureModes = <ExposureMode>[];
  final flashes = <FlashMode>[];
  Point<double>? focus;
  int focusCalls = 0;
  final lenses = <CameraLensDirection>[];
  int sessions = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    ),
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? mediaSettings,
  ) async {
    lenses.add(description.lensDirection);
    return ++sessions;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      ready.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    ready.add(
      CameraInitializedEvent(
        cameraId,
        1920,
        1080,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Future<double> getMinZoomLevel(int cameraId) async => .5;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 5;

  @override
  Future<double> getMinExposureOffset(int cameraId) async => -2;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 2;

  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => .5;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {
    zooms.add(zoom);
  }

  @override
  Future<double> setExposureOffset(int cameraId, double offset) async {
    exposures.add(offset);
    return offset / .5; // CameraX reports the compensation index.
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {
    exposureModes.add(mode);
  }

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    flashes.add(mode);
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    focus = point;
    focusCalls++;
  }

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.blueGrey);

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    testWidgets(
      'viewfinder controls drive one camera at ${size.width.toInt()} dp',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final originalPlatform = CameraPlatform.instance;
        final camera = _Camera();
        CameraPlatform.instance = camera;
        addTearDown(() {
          CameraPlatform.instance = originalPlatform;
          unawaited(camera.ready.close());
        });
        final messenger = tester.binding.defaultBinaryMessenger;
        final wb = <int?>[];
        for (final name in [
          'hemanthraj/flutter_compass',
          'dev.fluttercommunity.plus/sensors/method',
          'dev.fluttercommunity.plus/sensors/accelerometer',
          'flutter.baseflow.com/geolocator',
          'plugins.flutter.io/path_provider',
        ]) {
          final channel = MethodChannel(name);
          messenger.setMockMethodCallHandler(channel, (_) async => null);
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        }
        const adjustments = MethodChannel(
          'com.gpscamera.gps_camera_next/adjustments',
        );
        messenger.setMockMethodCallHandler(adjustments, (call) async {
          if (call.method == 'features') {
            return {
              'flash': true,
              'whiteBalanceMin': 2500,
              'whiteBalanceMax': 9000,
            };
          }
          expect(call.method, 'setWhiteBalance');
          wb.add(call.arguments['kelvin'] as int?);
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(adjustments, null),
        );

        // The Library reads MediaStore through this channel.
        const library = MethodChannel('com.gpscamera.gps_camera_next/library');
        messenger.setMockMethodCallHandler(library, (call) async {
          return switch (call.method) {
            'ensureAccess' => 'granted',
            'list' => [
              {
                'id': 42,
                'kind': 'video',
                'name': 'GPS_stamped_123.mp4',
                'takenMs': 1794308733000,
                'durationMs': 4200,
              },
            ],
            _ => null,
          };
        });
        addTearDown(() => messenger.setMockMethodCallHandler(library, null));

        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pumpAndSettle();
        final controls = find.byType(CameraAdjustmentRail);
        expect(controls, findsNothing);
        Finder control(String label) => find.bySemanticsLabel(RegExp(label));
        final topBar = tester.getRect(control(r'^White balance,'));
        final finder = tester.getRect(find.byType(CameraLayer));
        expect(topBar.bottom, lessThan(finder.top));
        final evHint = find.byKey(const ValueKey('camera-EV-hint'));
        final zoomHint = find.byKey(const ValueKey('camera-Zoom-hint'));
        expect(tester.getRect(evHint).left, closeTo(finder.left + 1, .1));
        expect(tester.getRect(zoomHint).right, closeTo(finder.right - 1, .1));
        expect(tester.getCenter(zoomHint).dy, closeTo(finder.center.dy, .1));
        Future<void> rotate(double x, double y) async {
          await messenger.handlePlatformMessage(
            'dev.fluttercommunity.plus/sensors/accelerometer',
            const StandardMethodCodec().encodeSuccessEnvelope([x, y, 0.0, 0.0]),
            (_) {},
          );
          await tester.pumpAndSettle();
        }

        await rotate(9.8, 0);
        expect(tester.getRect(evHint).top, closeTo(finder.top + 1, .1));
        expect(tester.getRect(zoomHint).bottom, closeTo(finder.bottom - 1, .1));
        expect(tester.getCenter(evHint).dx, closeTo(finder.center.dx, .1));
        final wbIcon = find.descendant(
          of: control(r'^White balance,'),
          matching: find.byType(AnimatedRotation),
        );
        expect(tester.widget<AnimatedRotation>(wbIcon).turns, .25);
        expect(tester.getRect(control(r'^White balance,')), topBar);
        await rotate(0, 9.8);
        expect(tester.widget<AnimatedRotation>(wbIcon).turns, 0);
        expect(
          tester.getRect(find.byType(GeoStamp)).bottom,
          closeTo(finder.bottom - 14, .1),
        );
        await tester.tapAt(finder.center);
        await tester.pump(kDoubleTapTimeout);
        expect(camera.focus, isNotNull);
        expect(zoomHint, findsOneWidget);

        expect(control(r'^Zoom 1×$'), findsOneWidget);
        final zoomGrip = tester.getCenter(zoomHint);
        await tester.tapAt(zoomGrip);
        await tester.pump(kDoubleTapTimeout);
        await tester.pump(const Duration(milliseconds: 220));
        expect(zoomHint, findsNothing);
        expect(controls, findsOneWidget);
        await tester.tapAt(
          tester.getCenter(find.byType(Slider)) - const Offset(0, 20),
        );
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(camera.zooms.last, greaterThan(1));

        await tester.tap(control('^Exposure 0.0 EV'));
        await tester.pumpAndSettle();
        expect(controls, findsOneWidget);
        await tester.tapAt(
          tester.getCenter(find.byType(Slider)) - const Offset(0, 20),
        );
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(camera.exposures.last, greaterThan(0));
        expect(camera.exposures.last % .5, 0);
        expect(
          control('^Exposure ${camera.exposures.last.toStringAsFixed(1)} EV'),
          findsOneWidget,
        );

        await tester.tapAt(finder.center);
        await tester.pump(kDoubleTapTimeout);
        await tester.pump(const Duration(milliseconds: 220));
        expect(controls, findsNothing);
        expect(camera.focus, isNotNull);
        final savedEv = camera.exposures.last;
        final wbButton = control(r'^White balance,');
        final evButton = control(r'^Exposure [-0-9]');
        final evButtonPosition = tester.getCenter(evButton);
        await tester.tap(wbButton);
        await tester.pumpAndSettle();
        expect(control(r'^White balance, Auto$'), findsOneWidget);
        expect(tester.getCenter(evButton), evButtonPosition);
        expect(find.text('2500–9000 K'), findsOneWidget);
        expect(find.text('Auto'), findsOneWidget);
        expect(wb, isEmpty);

        await tester.tapAt(finder.center);
        await tester.pump(kDoubleTapTimeout);
        await tester.pump(const Duration(milliseconds: 220));
        await tester.dragFrom(
          Offset(finder.left + 26, finder.center.dy),
          const Offset(0, -62),
        );
        await tester.pump();
        final adjustedKelvin = wb.last!;
        expect(adjustedKelvin, greaterThan(5500));
        expect(camera.exposures.last, savedEv);
        final wbReadout = find.byKey(
          const ValueKey('camera-whiteBalance-readout'),
        );
        expect(tester.widget<AnimatedOpacity>(wbReadout).opacity, 1);

        await tester.tap(evButton);
        await tester.pumpAndSettle();
        expect(tester.widget<CameraAdjustmentRail>(controls).exposure, isTrue);
        await tester.tap(wbButton);
        await tester.pumpAndSettle();
        expect(wb, [adjustedKelvin]);

        // AE can be locked even when EV compensation has already been set.
        await tester.longPressAt(finder.center);
        await tester.pumpAndSettle();
        expect(camera.exposureModes.last, ExposureMode.locked);
        await tester.tap(wbButton);
        await tester.pumpAndSettle();
        final railCenter = tester.getCenter(find.byType(Slider));
        await tester.tapAt(railCenter);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(railCenter);
        await tester.pump();
        expect(camera.zooms.last, 1);
        expect(wb.last, isNull);
        expect(camera.exposures.last, 0);
        expect(camera.exposureModes.last, ExposureMode.auto);
        expect(find.text('1×  ·  0 EV  ·  AWB'), findsOneWidget);
        expect(control(r'^White balance, Auto$'), findsOneWidget);
        expect(control(r'^Exposure 0.0 EV$'), findsOneWidget);

        await rotate(9.8, 0);
        await tester.tap(wbButton);
        await tester.pumpAndSettle();
        await tester.tap(wbButton);
        await tester.pumpAndSettle();
        await tester.dragFrom(
          Offset(finder.center.dx, finder.top + 26),
          const Offset(54, 0),
        );
        await tester.pump();
        expect(wb.last!, greaterThan(5500));
        expect(camera.exposures.last, 0);
        await rotate(0, 9.8);

        await tester.tap(evButton);
        await tester.pumpAndSettle();
        await tester.tapAt(finder.center);
        await tester.pump(kDoubleTapTimeout);
        await tester.pump(const Duration(milliseconds: 220));
        final focusOutline = find.byKey(const ValueKey('camera-focus-outline'));
        final outline =
            tester.widget<DecoratedBox>(focusOutline).decoration
                as BoxDecoration;
        expect(outline.boxShadow, isNull);
        expect(outline.border, isNotNull);
        expect(tester.getCenter(focusOutline), finder.center);

        double opacity(String name) => tester
            .widget<AnimatedOpacity>(
              find.byKey(ValueKey('camera-$name-readout')),
            )
            .opacity;
        final firstZoom = camera.zooms.last;
        final firstEv = camera.exposures.last;
        final right = Offset(finder.right - 26, finder.center.dy);
        final left = Offset(finder.left + 26, finder.center.dy);
        final focusBefore = camera.focus;
        await tester.dragFrom(right, const Offset(0, -52));
        await tester.pump();
        expect(camera.zooms.last, greaterThan(firstZoom));
        expect(camera.exposures.last, firstEv);
        expect(camera.focus, focusBefore);
        expect(opacity('zoom'), 1);
        expect(controls, findsOneWidget);
        expect(focusOutline, findsNothing);
        expect(
          (tester.getCenter(find.byKey(const ValueKey('camera-zoom-readout'))) -
                  finder.center)
              .distance,
          closeTo(0, .1),
        );
        await tester.dragFrom(left, const Offset(0, 52));
        await tester.pump();
        expect(camera.exposures.last, lessThan(firstEv));
        expect(opacity('exposure'), 1);
        expect(opacity('zoom'), 0);
        expect(
          tester.getCenter(
            find.byKey(const ValueKey('camera-exposure-readout')),
          ),
          finder.center,
        );
        final adjusted = camera.exposures.last;
        await tester.dragFrom(left, const Offset(50, 5));
        await tester.pump(const Duration(seconds: 1));
        expect(camera.exposures.last, adjusted);
        expect(opacity('exposure'), 0);
        await tester.pump(const Duration(milliseconds: 220));
        expect(controls, findsNothing);
        expect(evHint, findsOneWidget);
        final centerDrag = await tester.startGesture(finder.center);
        await centerDrag.moveTo(right);
        await centerDrag.moveBy(const Offset(0, -60));
        await centerDrag.up();
        await tester.pump();
        expect(camera.zooms.last, greaterThan(firstZoom));
        expect(opacity('zoom'), 0);
        await tester.tapAt(right);
        await tester.pump(kDoubleTapTimeout);
        expect(camera.focus, focusBefore);
        expect(controls, findsOneWidget);
        await tester.tapAt(finder.center);
        await tester.pump(kDoubleTapTimeout);
        await tester.pump(const Duration(milliseconds: 220));
        expect(controls, findsNothing);

        await rotate(9.8, 0);
        expect(
          tester.getRect(find.byType(GeoStamp)).left,
          closeTo(finder.left + 14, .1),
        );
        final landscapeZoom = camera.zooms.last;
        final landscapeEv = camera.exposures.last;
        final heldRight = Offset(finder.center.dx, finder.bottom - 26);
        final heldLeft = Offset(finder.center.dx, finder.top + 26);
        await tester.dragFrom(heldRight, const Offset(-48, 0));
        await tester.pump();
        expect(camera.zooms.last, lessThan(landscapeZoom));
        expect(camera.exposures.last, landscapeEv);
        expect(opacity('zoom'), 1);
        expect(
          (tester.getCenter(find.byKey(const ValueKey('camera-zoom-readout'))) -
                  finder.center)
              .distance,
          closeTo(0, .1),
        );
        await tester.dragFrom(heldLeft, const Offset(48, 0));
        await tester.pump();
        expect(camera.exposures.last, greaterThan(landscapeEv));
        expect(opacity('exposure'), 1);

        await rotate(-9.8, 0);
        expect(
          tester.getRect(find.byType(GeoStamp)).right,
          closeTo(finder.right - 14, .1),
        );
        final oppositeZoom = camera.zooms.last;
        final oppositeEv = camera.exposures.last;
        await tester.dragFrom(heldLeft, const Offset(-48, 0));
        await tester.pump();
        expect(camera.zooms.last, greaterThan(oppositeZoom));
        expect(camera.exposures.last, oppositeEv);
        await tester.dragFrom(heldRight, const Offset(48, 0));
        await tester.pump();
        expect(camera.exposures.last, lessThan(oppositeEv));

        final focusCalls = camera.focusCalls;
        final resetPoint = finder.center + const Offset(25, 16);
        await tester.tapAt(resetPoint);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(resetPoint);
        await tester.pump();
        expect(camera.zooms.last, 1);
        expect(camera.exposures.last, 0);
        expect(camera.focusCalls, focusCalls);
        expect(opacity('reset'), 1);
        expect(wb.last, isNull);
        final resetReadout = find.text('1×  ·  0 EV  ·  AWB');
        expect(
          (tester.getCenter(resetReadout) - finder.center).distance,
          closeTo(0, .1),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(opacity('reset'), 0);

        final pinchStart = await tester.startGesture(
          finder.center - const Offset(24, 0),
        );
        final pinchEnd = await tester.startGesture(
          finder.center + const Offset(24, 0),
        );
        for (var i = 0; i < 3; i++) {
          await pinchStart.moveBy(const Offset(-20, 0));
          await pinchEnd.moveBy(const Offset(20, 0));
        }
        await pinchStart.up();
        await pinchEnd.up();
        await tester.pump();
        expect(camera.zooms.last, greaterThan(1));
        expect(camera.exposures.last, 0);
        expect(camera.focusCalls, focusCalls);
        expect(opacity('reset'), 0);

        await rotate(0, -9.8);
        expect(
          tester.getRect(find.byType(GeoStamp)).top,
          closeTo(finder.top + 14, .1),
        );
        await rotate(0, 9.8);
        await tester.tapAt(right);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(right);
        await tester.pump();
        expect(camera.zooms.last, 1);
        expect(opacity('reset'), 1);
        expect(camera.focusCalls, focusCalls);
        await tester.pump(const Duration(seconds: 1));

        final timer = control(r'^Timer, off$');
        final ratio = control(r'^Aspect ratio,');
        expect(tester.getRect(timer).bottom, lessThan(finder.top));
        expect(tester.getRect(ratio).bottom, lessThan(finder.top));
        await tester.tap(timer);
        await tester.pumpAndSettle();
        expect(control(r'^Timer, 3s$'), findsOneWidget);
        await tester.tap(control(r'^Timer, 3s$'));
        await tester.pumpAndSettle();
        expect(control(r'^Timer, 10s$'), findsOneWidget);
        await tester.tap(control(r'^Timer, 10s$'));
        await tester.pumpAndSettle();
        expect(timer, findsOneWidget);
        const ratios = ['4:3', '16:9', '1:1', 'Full'];
        for (final value in ratios) {
          final action = control('^Aspect ratio, $value\$');
          expect(action, findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
        }
        expect(control(r'^Aspect ratio, 4:3$'), findsOneWidget);

        await tester.tap(control('^Flash off'));
        await tester.pumpAndSettle();
        expect(camera.flashes.last, FlashMode.auto);
        await tester.tap(control('^Video'));
        await tester.pumpAndSettle();
        expect(camera.sessions, 1);
        expect(tester.getRect(control(r'^White balance,')), topBar);
        expect(camera.flashes.last, FlashMode.off);
        await tester.tap(control('^Torch off'));
        await tester.pumpAndSettle();
        expect(camera.flashes.last, FlashMode.torch);
        // The Library covers the camera, which is released until it closes.
        await tester.tap(control('^Open video library'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryScreen), findsOneWidget);
        expect(control(r'^Video, 0:04'), findsOneWidget);
        await tester.tap(find.byTooltip('Back to camera'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryScreen), findsNothing);
        expect(camera.sessions, 2);
        expect(control('^Start recording'), findsOneWidget);
        expect(control(r'^Pro$'), findsNothing);
        await tester.tap(control('^Switch camera'));
        await tester.pumpAndSettle();
        expect(camera.lenses, [
          CameraLensDirection.back,
          CameraLensDirection.back, // Reopened after the Library closed.
          CameraLensDirection.front,
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
