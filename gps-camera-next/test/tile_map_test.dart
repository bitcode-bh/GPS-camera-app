import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/widgets/tile_map.dart';

void main() {
  test('projection round-trips and matches the tile grid', () {
    const delhi = GeoPoint(28.6139, 77.209);
    final back = Mercator.unproject(Mercator.project(delhi, 12), 12);
    expect(back.lat, closeTo(delhi.lat, 1e-9));
    expect(back.lon, closeTo(delhi.lon, 1e-9));
    // (0, 0) is the centre of the world at any zoom.
    expect(Mercator.project(const GeoPoint(0, 0), 3), const Offset(1024, 1024));
    // Zoom 16 tile containing Delhi in the standard XYZ grid.
    final px = Mercator.project(delhi, 16);
    expect((px.dx / 256).floor(), 46823);
    expect((px.dy / 256).floor(), 27327);
  });

  test('fit frames every point inside the padded view', () {
    final controller = TileMapController(maxZoom: 19);
    const points = [GeoPoint(28.5, 77.0), GeoPoint(28.7, 77.4)];
    const size = Size(400, 800);
    const padding = EdgeInsets.fromLTRB(48, 100, 48, 200);
    controller.fit(points, size, padding: padding, maxZoom: 16);
    final centre = Mercator.project(controller.center, controller.zoom);
    for (final p in points) {
      final at =
          Mercator.project(p, controller.zoom) -
          centre +
          size.center(Offset.zero);
      expect(
        at.dx,
        inInclusiveRange(padding.left - .5, size.width - padding.right + .5),
      );
      expect(
        at.dy,
        inInclusiveRange(padding.top - .5, size.height - padding.bottom + .5),
      );
    }
    // Never closer than the cap, even for one spot.
    controller.fit(const [GeoPoint(28.6, 77.2)], size, maxZoom: 16);
    expect(controller.zoom, 16);
  });

  test('tile URLs fill in level, column and row', () {
    const source = TileSource('https://t.example/{z}/{y}/{x}.png');
    expect(source.url(5, 22, 13), 'https://t.example/5/13/22.png');
  });

  testWidgets('markers sit on their place and taps reach them', (tester) async {
    var tapped = 0;
    final controller = TileMapController(
      center: const GeoPoint(10, 20),
      zoom: 10,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: TileMap(
            controller: controller,
            sources: const [],
            markers: [
              MapMarker(
                at: const GeoPoint(10, 20),
                size: const Size.square(20),
                child: GestureDetector(
                  onTap: () => tapped++,
                  child: const ColoredBox(
                    key: ValueKey('dot'),
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final dot = tester.getCenter(find.byKey(const ValueKey('dot')));
    final map = tester.getCenter(find.byType(TileMap));
    expect(dot, map);
    await tester.tap(find.byKey(const ValueKey('dot')));
    // The map also listens for double-taps, so a single tap is confirmed
    // after the double-tap window.
    await tester.pump(const Duration(milliseconds: 350));
    expect(tapped, 1);
    // Dragging pans: the marker follows the finger once the gesture passes
    // Flutter's touch slop (~18 px).
    await tester.drag(find.byType(TileMap), const Offset(80, 0));
    await tester.pump();
    final moved =
        tester.getCenter(find.byKey(const ValueKey('dot'))).dx - dot.dx;
    expect(moved, inInclusiveRange(55, 80));
    await tester.pump(const Duration(milliseconds: 350));
  });
}
