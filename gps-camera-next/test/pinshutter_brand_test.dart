import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/screens/camera/widgets/camera_layer.dart';
import 'package:gps_camera_next/screens/library/library_screen.dart';
import 'package:gps_camera_next/services/media_library.dart';
import 'package:gps_camera_next/widgets/pinshutter_brand.dart';

import 'support/fake_media.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('brand fits loading and library at $width dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CameraLayer())),
      );
      await tester.pump();
      expect(find.byType(PinShutterLoading), findsOneWidget);
      expect(find.bySemanticsLabel('PinShutter'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final library = MediaLibrary(gateway: FakeGateway(), index: tempIndex());
      await tester.runAsync(library.refresh);
      await tester.pumpWidget(
        MaterialApp(home: LibraryScreen(library: library)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PinShutterWordmark), findsOneWidget);
      final mark = tester.getRect(find.byType(PinShutterWordmark));
      final libraryTab = tester.getRect(find.text('Library'));
      final mapTab = tester.getRect(find.text('Map'));
      expect(mark.bottom, lessThan(libraryTab.top));
      expect(mark.bottom, lessThan(mapTab.top));
      final navigation = tester.getRect(
        find.byKey(const ValueKey('library-bottom-navigation')),
      );
      expect(libraryTab.top, greaterThan(568 - 96));
      expect(mapTab.top, greaterThan(568 - 96));
      expect(libraryTab.bottom, lessThanOrEqualTo(navigation.bottom));
      expect(find.byTooltip('Back to camera'), findsOneWidget);
      expect(find.byTooltip('Open device gallery'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Map'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PinShutterWordmark)), mark);
      expect(tester.getRect(find.text('Map')), mapTab);
      expect(
        tester.getRect(find.byKey(const ValueKey('library-bottom-navigation'))),
        navigation,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      library.dispose();
    });
  }
}
