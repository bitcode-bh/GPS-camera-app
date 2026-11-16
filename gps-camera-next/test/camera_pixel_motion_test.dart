import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_design.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_control_bar.dart';

Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async {
  final bytes = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return Uint8List.fromList(data!.buffer.asUint8List());
  });
  return bytes!;
}

List<int> sample(Uint8List data, int width, double x, double y) {
  final index = ((y * 4).floor() * width * 4 + (x * 4).floor()) * 4;
  return data.sublist(index, index + 4);
}

Widget surface(
  GlobalKey key,
  Widget child, {
  bool reduced = false,
  bool enabled = true,
}) => MaterialApp(
  home: Material(
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: enabled,
        child: Center(
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('capture grid paint stays inside the shutter ring', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      surface(
        key,
        SizedBox(
          width: 320,
          height: 160,
          child: CameraControlBar(
            mode: CameraMode.video,
            busy: false,
            lastShot: null,
            recording: true,
            animate: false,
            onMode: (_) {},
            onShutter: () {},
            onFlip: () {},
            onGallery: () {},
          ),
        ),
      ),
    );
    final data = await pixels(tester, key);
    expect(sample(data, 320, 196.5, 46), [255, 255, 255, 255]);
    expect(sample(data, 320, 201, 46)[3], 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final exposure in [1.0, -1.0, null]) {
    testWidgets(
      'only dark ${exposure == null ? 'zoom' : 'EV $exposure'} cells animate',
      (tester) async {
        final key = GlobalKey();
        final position = exposure == null ? .3010299957 : (exposure + 2) / 4;
        final baseline = exposure == null ? 0.0 : .5;
        await tester.pumpWidget(
          surface(
            key,
            CameraAdjustmentRail(
              label: exposure == null ? 'Zoom' : 'Exposure',
              value: exposure ?? 2,
              min: exposure == null ? 1 : -2,
              max: exposure == null ? 10 : 2,
              exposure: exposure != null,
              onChanged: (_) {},
            ),
          ),
        );
        final bounds = tester.getRect(find.byKey(key));
        final before = await pixels(tester, key);
        await tester.pump(const Duration(milliseconds: 2400));
        final after = await pixels(tester, key);
        expect(tester.getRect(find.byKey(key)), bounds);
        var changedDark = 0, filled = 0;
        for (var row = 0; row < 43; row++) {
          final along = 12.85 + row * 2.5;
          final active =
              along >= 11 + 110 * (position < baseline ? position : baseline) &&
              along <= 11 + 110 * (position > baseline ? position : baseline);
          for (var column = 0; column < 4; column++) {
            final a = sample(before, 54, 23.25 + column * 2.5, 132 - along);
            final b = sample(after, 54, 23.25 + column * 2.5, 132 - along);
            if (active) {
              expect(a, [255, 219, 85, 255]);
              expect(b, a);
              filled++;
            } else {
              // The thumb can cover a cell immediately beside the filled range.
              if (a[3] == 255) {
                expect(b, a);
                continue;
              }
              expect(a[3], lessThan(100));
              expect(b[3], lessThan(100));
              if (a[3] != b[3]) changedDark++;
            }
          }
        }
        expect(filled, greaterThan(0));
        expect(changedDark, greaterThan(10));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'recording grid keeps size and red majority while changing pixels',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        surface(
          key,
          const SizedBox.square(
            dimension: 62,
            child: CameraCaptureGrid(recording: true),
          ),
        ),
      );
      final before = await pixels(tester, key);
      var red = 0, yellow = 0;
      for (var row = 0; row < 25; row++) {
        for (var col = 0; col < 25; col++) {
          final x = 1 + col * 2.5, y = 1 + row * 2.5;
          if ((x - 31) * (x - 31) + (y - 31) * (y - 31) > 29 * 29) continue;
          final p = sample(before, 62, x, y);
          if (p[1] < 100) {
            red++;
          } else if (p[1] > 180) {
            yellow++;
          }
        }
      }
      expect(red / (red + yellow), inInclusiveRange(.72, .88));
      await tester.pump(const Duration(milliseconds: 2400));
      expect(await pixels(tester, key), isNot(orderedEquals(before)));
      expect(tester.getSize(find.byKey(key)), const Size(62, 62));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mode in ['reduced', 'hidden', 'idle', 'inactive']) {
    testWidgets('$mode pixels stop repainting', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        surface(
          key,
          SizedBox.square(
            dimension: 62,
            child: CameraCaptureGrid(recording: true, animate: mode != 'idle'),
          ),
          reduced: mode == 'reduced',
          enabled: mode != 'hidden',
        ),
      );
      if (mode == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await tester.pump();
      }
      final before = await pixels(tester, key);
      await tester.pump(const Duration(milliseconds: 2400));
      expect(await pixels(tester, key), orderedEquals(before));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
