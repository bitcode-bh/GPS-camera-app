import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_control_bar.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_design.dart';

void main() {
  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('bottom bar taps and swipes at ${width.toInt()} dp', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final actions = <String>[];
      var mode = CameraMode.photo;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: StatefulBuilder(
                  builder: (context, setState) => CameraControlBar(
                    mode: mode,
                    busy: false,
                    lastShot: null,
                    recording: false,
                    onMode: (value) {
                      if (value == mode) return;
                      actions.add(value.name);
                      setState(() => mode = value);
                    },
                    onShutter: () => actions.add('shutter'),
                    onFlip: () => actions.add('flip'),
                    onGallery: () => actions.add('gallery'),
                    onStamp: () => actions.add('stamp'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Finder stop(String label) => find.bySemanticsLabel(label);
      expect(stop('Pro'), findsNothing);

      for (final label in [
        'Open gallery',
        'Take photo',
        'Video',
        'Start recording',
        'Open video library',
        'Photo',
        'Take photo',
        'Switch camera',
        'GPS stamp settings',
      ]) {
        final target = tester.getRect(stop(label));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        await tester.tapAt(target.topLeft + const Offset(2, 2));
        await tester.pumpAndSettle();
      }

      expect(actions, [
        'gallery',
        'shutter',
        'video',
        'shutter',
        'gallery',
        'photo',
        'shutter',
        'flip',
        'stamp',
      ]);
      actions.clear();

      expect(tester.getCenter(stop('Take photo')).dx, closeTo(width / 2, 0.1));
      expect(
        tester.getCenter(stop('Take photo')).dy,
        lessThan(tester.getCenter(stop('Photo')).dy),
      );

      var current = 'Photo';
      for (final label in ['Video', 'Photo']) {
        final start = tester.getCenter(stop(current));
        final end = tester.getCenter(stop(label));
        await tester.timedDragFrom(
          start,
          end - start,
          const Duration(milliseconds: 600),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(stop(label)),
          matchesSemantics(
            label: label,
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        current = label;
      }
      expect(actions, ['video', 'photo']);
    });
  }

  testWidgets('recording keeps camera changes locked and Stop tappable', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraControlBar(
            mode: CameraMode.video,
            busy: false,
            lastShot: null,
            recording: true,
            lockCameraChanges: true,
            onMode: (_) => actions.add('mode'),
            onShutter: () => actions.add('stop'),
            onFlip: () => actions.add('flip'),
            onGallery: () => actions.add('gallery'),
          ),
        ),
      ),
    );

    for (final label in ['Photo', 'Switch camera']) {
      await tester.tapAt(tester.getCenter(find.bySemanticsLabel(label)));
      await tester.pumpAndSettle();
    }
    await tester.drag(
      find.bySemanticsLabel('Video'),
      tester.getCenter(find.bySemanticsLabel('Photo')) -
          tester.getCenter(find.bySemanticsLabel('Video')),
    );
    await tester.pumpAndSettle();
    expect(actions, isEmpty);

    await tester.tap(find.bySemanticsLabel('Stop recording'));
    expect(actions, ['stop']);
  });

  for (final exposure in [false, true]) {
    testWidgets(
      'vertical ${exposure ? 'exposure' : 'zoom'} follows upward drags',
      (tester) async {
        double value = exposure ? 0 : 1;
        final minimum = exposure ? -2.0 : .5;
        final maximum = exposure ? 2.0 : 5.0;
        final values = <double>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => CameraAdjustmentRail(
                    label: exposure ? 'Exposure' : 'Zoom',
                    value: value,
                    min: minimum,
                    max: maximum,
                    exposure: exposure,
                    onChanged: (next) {
                      values.add(next);
                      setState(() => value = next);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        final slider = find.byType(Slider);
        final bounds = tester.getRect(slider);
        final start = Offset(bounds.center.dx, bounds.bottom - 30);
        await tester.timedDragFrom(
          start,
          const Offset(0, -65),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();
        expect(values.length, greaterThan(2));
        expect(values.last, greaterThan(values.first));
        expect(values.every((v) => v >= minimum && v <= maximum), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
