import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/theme.dart';
import 'package:gps_camera_next/screens/templates/custom_template_editor.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/state/template_controller.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('custom text expands smoothly and keeps edits at $width dp', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = Prefs.memory();
      SettingsController.instance.attach(prefs);
      final templates = TemplateController.instance..attach(prefs);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const CustomTemplateEditor()),
      );
      await tester.pumpAndSettle();
      final section = find.byType(ExpansionTile);
      final heading = find.text('CUSTOM TEXT');
      await tester.scrollUntilVisible(heading, 200);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      final collapsedHeight = tester.getSize(section).height;
      expect(collapsedHeight, greaterThanOrEqualTo(48));
      await tester.tap(heading);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final midHeight = tester.getSize(section).height;
      await tester.pumpAndSettle();
      expect(midHeight, greaterThan(collapsedHeight));
      expect(midHeight, lessThan(tester.getSize(section).height));
      expect(find.byType(TextField), findsNWidgets(6));
      final title = find.widgetWithText(TextField, 'Project / Title');
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Site inspection');
      expect(templates.config.projectTitle, 'Site inspection');
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(heading);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Site inspection'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
