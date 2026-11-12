import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/template.dart';
import 'package:gps_camera_next/state/template_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('custom field values and visibility survive template serialization', () {
    final config = TemplateConfig.forTemplate(StampTemplate.reporting)
      ..siteId = 'A-12'
      ..remarks = 'North access'
      ..width = 0.9
      ..mapSize = StampSize.small
      ..fieldOrder = [StampField.siteId, StampField.dateTime];
    final restored = TemplateConfig.decode(config.encode());
    expect(restored.siteId, 'A-12');
    expect(restored.remarks, 'North access');
    expect(restored.width, 0.9);
    expect(restored.mapSize, StampSize.small);
    expect(restored.orderedDetails.take(2), [
      StampField.siteId,
      StampField.dateTime,
    ]);
    expect(restored.has(StampField.siteId), isTrue);
  });

  test('named templates persist and keep the current photo number', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = TemplateController.instance..attach(preferences);
    controller.update((config) => config.siteId = 'A-12');
    controller.saveTemplate('Survey A');
    controller.resetTemplate();
    controller.bumpPhotoNumber();
    final number = controller.config.photoNumber;
    controller.attach(preferences);
    expect(controller.savedNames, ['Survey A']);
    controller.applySavedTemplate('Survey A');
    expect(controller.config.siteId, 'A-12');
    expect(controller.config.photoNumber, number);
  });
}
