import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/design/palette.dart';
import 'package:gps_camera_next/core/theme.dart';
import 'package:gps_camera_next/core/widgets/controls.dart';
import 'package:gps_camera_next/screens/settings/app_settings.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/state/template_controller.dart';

void main() {
  testWidgets('switch row toggles once, keeps its bounds and uses yellow ON', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => GlassSwitchTile(
              label: 'Save original',
              value: value,
              onChanged: (next) => update(() {
                value = next;
                changes++;
              }),
            ),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byType(GlassSwitchTile));
    final control = tester.getRect(find.byType(Switch));
    expect(row.height, greaterThanOrEqualTo(56));
    // The full 56 dp row is the tap target, including its label.
    expect(
      tester.getSize(find.byType(Switch)).height,
      greaterThanOrEqualTo(48),
    );
    final scale = tester.widget<Transform>(
      find.ancestor(of: find.byType(Switch), matching: find.byType(Transform)),
    );
    expect(scale.transform.storage[0], .6);
    expect(scale.transform.storage[5], .6);
    expect(scale.transformHitTests, isFalse);
    final node = tester.getSemantics(find.bySemanticsLabel('Save original'));
    expect(
      node.getSemanticsData().flagsCollection.isToggled,
      ui.Tristate.isFalse,
    );
    expect(node.rect.height, greaterThanOrEqualTo(56));
    final theme = SwitchTheme.of(tester.element(find.byType(Switch)));
    expect(theme.trackColor!.resolve({}), Palette.ink2);
    expect(
      theme.trackColor!.resolve({WidgetState.selected}),
      Palette.accentYellow,
    );
    expect(
      Theme.of(tester.element(find.byType(Switch))).colorScheme.primary,
      Palette.accentYellow,
    );
    await tester.tap(find.text('Save original'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(value, isTrue);
    expect(changes, 1);
    expect(tester.getRect(find.byType(GlassSwitchTile)), row);
    expect(tester.getRect(find.byType(Switch)), control);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    expect(changes, 2);
    // The row remains one keyboard target even though the paint is smaller.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(changes, 3);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'display time switch persists without changing formats at $width dp',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final preferences = Prefs.memory();
        final settings = SettingsController.instance..attach(preferences);
        TemplateController.instance.attach(preferences);
        final map = settings.mapKind;
        final coordinates = settings.coordFormat;
        final units = settings.unitSystem;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showSettingsCategory(context, SettingsCat.display),
                  child: const Text('Display'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Display'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('24-hour time'));
        await tester.tap(find.text('24-hour time'));
        await tester.pumpAndSettle();
        expect(settings.clock24, isTrue);
        expect(preferences.getBool('clock24'), isTrue);
        expect(settings.mapKind, map);
        expect(settings.coordFormat, coordinates);
        expect(settings.unitSystem, units);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
