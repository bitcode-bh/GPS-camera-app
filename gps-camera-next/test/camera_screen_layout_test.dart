import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/screens/camera/camera_screen.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/state/template_controller.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    testWidgets('stamp settings fit ${size.width.toInt()} dp', (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'next-camera-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = Prefs.memory();
      SettingsController.instance.attach(preferences);
      TemplateController.instance.attach(preferences);
      final messenger = tester.binding.defaultBinaryMessenger;
      for (final name in [
        'com.gpscamera.gps_camera_next/heading',
        'com.gpscamera.gps_camera_next/gravity',
        'com.gpscamera.gps_camera_next/gallery',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (_) async => [],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.gpscamera.gps_camera_next/location'),
        (call) async => call.method == 'status'
            ? {'service': false, 'permission': 'granted'}
            : false,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.gpscamera.gps_camera_next/platform'),
        (call) async => call.method == 'dirs'
            ? {'support': directory.path, 'documents': directory.path}
            : null,
      );
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.bySemanticsLabel('GPS stamp settings')).dx,
        greaterThan(tester.getCenter(find.bySemanticsLabel('Take photo')).dx),
      );
      await tester.tap(find.bySemanticsLabel('GPS stamp settings'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Burn into capture'), findsOneWidget);
      await tester.tap(find.text('Template'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Stamp designs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Advanced'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel('GPS stamp settings'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Burn into capture'));
      await tester.pump();
      expect(SettingsController.instance.stampEnabled, isFalse);
      await tester.tap(find.bySemanticsLabel('Close camera menu'));
      await tester.pump();
      expect(find.text('Burn into capture'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
