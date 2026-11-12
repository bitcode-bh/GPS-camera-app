import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/models/template.dart';
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
}
