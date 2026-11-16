import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/models/location_integrity.dart';
import 'package:gps_camera_next/models/template.dart';
import 'package:gps_camera_next/widgets/mini_map.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/widgets/geo_stamp.dart';

void main() {
  Widget stamp(GeoData geo, TemplateConfig config) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: GeoStamp(
            geo: geo,
            config: config,
            settings: SettingsController.instance,
            realMap: false,
            preview: true,
            live: false,
          ),
        ),
      ),
    ),
  );

  testWidgets('every preset lays out at a narrow preview width', (
    tester,
  ) async {
    for (final template in StampTemplate.values) {
      final config = TemplateConfig.forTemplate(template)
        ..width = 0.75
        ..mapSize = StampSize.large;
      await tester.pumpWidget(stamp(GeoData.demo(), config));
      expect(tester.takeException(), isNull, reason: template.name);
    }
  });

  testWidgets('weak or missing GPS renders a stamp without coordinates', (
    tester,
  ) async {
    final geo = GeoData.withoutLocation(DateTime.utc(2026, 11, 9));
    final config = TemplateConfig.forTemplate(StampTemplate.advance);
    await tester.pumpWidget(stamp(geo, config));
    expect(find.text('GPS unavailable'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GeoStamp),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('GPS unavailable')).style?.shadows,
      isNotEmpty,
    );
    expect(
      find.text(geo.coords(SettingsController.instance.coordFormat)),
      findsNothing,
    );
    expect(find.textContaining('09 Nov 2026'), findsOneWidget);
  });

  testWidgets(
    'integrity is burned in for every template, even with fields hidden',
    (tester) async {
      for (final integrity in [
        LocationIntegrity.lowAccuracy,
        LocationIntegrity.suspectedMock,
        LocationIntegrity.suspectedSpoofing,
      ]) {
        for (final template in StampTemplate.values) {
          final config = TemplateConfig.forTemplate(template)..fields.clear();
          final geo = GeoData.demo().copyWith(integrity: integrity);
          await tester.pumpWidget(stamp(geo, config));
          expect(
            find.textContaining(integrity.warning),
            findsOneWidget,
            reason: '${template.name}: ${integrity.name}',
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('stamp text and map consume the identical coordinate snapshot', (
    tester,
  ) async {
    final geo = GeoData.demo();
    final config = TemplateConfig.forTemplate(StampTemplate.advance);
    await tester.pumpWidget(stamp(geo, config));
    final map = tester.widget<MiniMap>(find.byType(MiniMap));
    expect(map.lat, geo.lat);
    expect(map.lon, geo.lon);
    expect(
      find.textContaining(geo.coords(SettingsController.instance.coordFormat)),
      findsOneWidget,
    );
  });

  testWidgets('GPS warning sits above the stamp without changing its layout', (
    tester,
  ) async {
    final geo = GeoData.demo();
    final config = TemplateConfig.forTemplate(StampTemplate.advance);
    await tester.pumpWidget(stamp(geo, config));
    final bounds = tester.getRect(find.byType(GeoStamp));
    final map = tester.getRect(find.byType(MiniMap));
    final coords = tester.getRect(
      find.textContaining(geo.coords(SettingsController.instance.coordFormat)),
    );
    await tester.pumpWidget(
      stamp(
        geo.copyWith(
          integrity: LocationIntegrity.suspectedMock,
          locationNote: 'Android mock provider',
        ),
        config,
      ),
    );
    await tester.pumpAndSettle();
    final warning = find.textContaining('Mock Location');
    expect(tester.getRect(warning).bottom, lessThanOrEqualTo(map.top));
    expect(tester.getRect(find.byType(GeoStamp)), bounds);
    expect(tester.getRect(find.byType(MiniMap)), map);
    expect(
      tester.getRect(
        find.textContaining(
          geo.coords(SettingsController.instance.coordFormat),
        ),
      ),
      coords,
    );
    await tester.pumpWidget(stamp(geo, config));
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    expect(tester.getRect(find.byType(MiniMap)), map);
  });
}
