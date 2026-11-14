import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/map_kind.dart';
import 'package:gps_camera_next/models/template.dart';
import 'package:gps_camera_next/state/template_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards for the Google Play compliance fixes (docs/publishing).
void main() {
  test('without a key, only debug builds draw the public Esri tiles', () {
    // Tests run in debug mode with no ESRI_API_KEY.
    expect(MapTiles.authenticated, isFalse);
    expect(MapTiles.available, isTrue);
    for (final kind in MapKind.values) {
      expect(kind.tileUrl, startsWith('https://server.arcgisonline.com/'));
      expect(kind.tileDimension, 256);
      expect(kind.dataCredit, contains('Esri'));
    }
    expect(MapKind.hybrid.overlayUrl, isNotNull);
    expect(MapKind.normal.overlayUrl, isNull);
  });

  test('the weather template and fields are not offered', () {
    expect(offeredTemplates, isNot(contains(StampTemplate.weather)));
    expect(offeredTemplates, hasLength(StampTemplate.values.length - 1));
    expect(unsupportedFields, contains(StampField.temperature));
  });

  test('a saved weather stamp falls back to a supported template', () async {
    final weather = TemplateConfig.forTemplate(StampTemplate.weather);
    SharedPreferences.setMockInitialValues({
      'templateConfig': weather.encode(),
    });
    final controller = TemplateController.instance
      ..attach(await SharedPreferences.getInstance());
    expect(controller.config.template, isNot(StampTemplate.weather));
    expect(controller.config.fields.intersection(unsupportedFields), isEmpty);
  });

  test('no public geocoder or hard-coded competitor branding in the app', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(source, isNot(contains('nominatim.openstreetmap.org')));
    expect(source, isNot(contains('reference app')));
  });
}
