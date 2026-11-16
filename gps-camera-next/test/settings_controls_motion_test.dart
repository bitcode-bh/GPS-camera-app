import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/theme.dart';
import 'package:gps_camera_next/core/widgets/controls.dart';

Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return Uint8List.fromList(data!.buffer.asUint8List());
  }))!;
}

void main() {
  for (final labels in [
    const ['Video', 'Photo'],
    const ['Library', 'Map'],
  ]) {
    testWidgets('$labels indicator reverses without jumps or resizing', (
      tester,
    ) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, update) => GlassSegmented<int>(
                    options: [
                      for (var i = 0; i < labels.length; i++)
                        (value: i, label: labels[i]),
                    ],
                    selected: selected,
                    onChanged: (value) => update(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final indicator = find.byKey(const ValueKey('segment-indicator'));
      final start = tester.getRect(indicator);
      final labelBounds = [
        for (final label in labels) tester.getRect(find.text(label)),
      ];
      await tester.tap(find.text(labels.last));
      await tester.pump();
      expect(tester.getRect(indicator), start);
      await tester.pump(const Duration(milliseconds: 70));
      final mid = tester.getRect(indicator);
      expect(mid.size, start.size);
      expect(mid.left, greaterThan(start.left));
      await tester.tap(find.text(labels.first));
      await tester.pump();
      expect(tester.getRect(indicator), mid);
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getRect(indicator).left, lessThan(mid.left));
      expect(tester.getRect(indicator).size, start.size);
      await tester.pumpAndSettle();
      expect(tester.getRect(indicator), start);
      expect([
        for (final label in labels) tester.getRect(find.text(label)),
      ], labelBounds);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('segments respect reduced motion, RTL and larger text', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, update) => GlassSegmented<int>(
                      options: const [
                        (value: 0, label: 'Library'),
                        (value: 1, label: 'Map'),
                      ],
                      selected: selected,
                      onChanged: (value) => update(() => selected = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final indicator = find.byKey(const ValueKey('segment-indicator'));
    final start = tester.getRect(indicator);
    await tester.tap(find.text('Map'));
    await tester.pump();
    final end = tester.getRect(indicator);
    expect(end.left, lessThan(start.left));
    expect(end.size, start.size);
    expect(end.center.dx, tester.getCenter(find.text('Map')).dx);
    expect(tester.takeException(), isNull);
  });

  for (final toggle in [false, true]) {
    testWidgets(
      '${toggle ? 'toggle' : 'setting'} ripple stays inside its row',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 160));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey();
        var taps = 0;
        final target = toggle
            ? GlassSwitchTile(
                label: 'Setting',
                value: false,
                onChanged: (_) => taps++,
              )
            : SettingsTap(
                onTap: () => taps++,
                child: const SizedBox(
                  height: 56,
                  child: Center(child: Text('Setting')),
                ),
              );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: Center(child: SizedBox(width: 240, child: target)),
              ),
            ),
          ),
        );
        final bounds = tester.getRect(find.byWidget(target));
        final before = await pixels(tester, key);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Setting')),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 80));
        final after = await pixels(tester, key);
        var changed = 0;
        for (var y = 0; y < 160; y++) {
          for (var x = 0; x < 320; x++) {
            final i = (y * 320 + x) * 4;
            final differs = List.generate(
              4,
              (channel) => before[i + channel] != after[i + channel],
            ).any((v) => v);
            if (differs) {
              expect(
                bounds.contains(Offset(x + .5, y + .5)),
                isTrue,
                reason: 'Ink escaped at $x, $y',
              );
              changed++;
            }
          }
        }
        expect(changed, greaterThan(0));
        expect(tester.getRect(find.byWidget(target)), bounds);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
