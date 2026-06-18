// Basic smoke coverage for pure model/formatting logic (no plugins required).
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_pro/models/coordinates.dart';

void main() {
  test('coordinate formats render without throwing', () {
    for (final f in CoordFormat.values) {
      final s = Coordinates.format(f, 28.6273, 77.3721);
      expect(s, isNotEmpty);
    }
  });

  test('decimal format includes hemisphere', () {
    expect(Coordinates.decimal(28.6, 77.3), contains('N'));
    expect(Coordinates.decimal(-28.6, -77.3), contains('S'));
  });
}
