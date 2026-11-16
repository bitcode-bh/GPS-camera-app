import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/map_kind.dart';
import 'package:gps_camera_next/models/media_item.dart';
import 'package:gps_camera_next/services/map_attribution.dart';
import 'package:gps_camera_next/screens/library/media_map.dart';
import 'package:gps_camera_next/services/media_library.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/widgets/tile_map.dart';

import 'support/fake_media.dart';

void main() {
  late MapAttribution previousAttribution;
  setUp(() {
    previousAttribution = MapAttribution.instance;
    MapAttribution.instance = MapAttribution(
      fetch: (_) async =>
          '{"copyrightText":"Esri, Regional imagery and label partners, © OpenStreetMap contributors"}',
    );
  });
  tearDown(() => MapAttribution.instance = previousAttribution);
  const delhi = MediaLocation(28.6139, 77.2090);
  const nextDoor = MediaLocation(28.61391, 77.20901); // About a metre away.
  const mumbai = MediaLocation(19.0760, 72.8777);

  MediaLocation? Function(MediaItem) at(Map<int, MediaLocation> places) =>
      (item) => places[item.id];

  test('items at the same place share a marker and stay reachable', () {
    final items = [photo(1), video(2), photo(3)];
    final groups = groupMarkers(
      items,
      at({1: delhi, 2: delhi, 3: nextDoor}),
      15,
    );
    expect(groups, hasLength(1));
    expect(
      [for (final item in groups.single.items) item.key],
      ['image:1', 'video:2', 'image:3'],
    );
  });

  test('distant items get their own markers', () {
    final groups = groupMarkers(
      [photo(1), photo(2)],
      at({1: delhi, 2: mumbai}),
      5,
    );
    expect(groups, hasLength(2));
  });

  test('zooming in separates neighbours that overlap when zoomed out', () {
    const across = MediaLocation(28.6239, 77.2190); // About 1.5 km away.
    final items = [photo(1), photo(2)];
    final places = at({1: delhi, 2: across});
    expect(groupMarkers(items, places, 8), hasLength(1));
    expect(groupMarkers(items, places, 16), hasLength(2));
  });

  test('each item appears in exactly one marker', () {
    final items = [for (var i = 0; i < 20; i++) photo(i)];
    final places = at({
      for (var i = 0; i < 20; i++)
        i: MediaLocation(28.6 + (i % 4) * .00001, 77.2 + (i ~/ 4) * .5),
    });
    for (final zoom in [2.0, 6.0, 12.0, 18.0]) {
      final keys = [
        for (final group in groupMarkers(items, places, zoom))
          for (final item in group.items) item.key,
      ];
      expect(keys, hasLength(20));
      expect(keys.toSet(), hasLength(20));
    }
  });

  test('items without a location never get a marker', () {
    final groups = groupMarkers([photo(1), photo(2)], at({1: delhi}), 10);
    expect(groups.single.items.single.key, 'image:1');
    expect(groupMarkers([photo(2)], at({}), 10), isEmpty);
  });

  test('a selection drops deleted media and clears when none is left', () {
    expect(reconcileSelection(null, {'image:1'}), isNull);
    expect(reconcileSelection(['image:1', 'video:2'], {'image:1'}), [
      'image:1',
    ]);
    // The marker's only item was deleted: nothing stays selected.
    expect(reconcileSelection(['image:1'], {'image:9'}), isNull);
  });

  test('the map phase follows the library and the selection', () {
    expect(mapPhase(LibraryStatus.idle, 0, false), MapPhase.uninitialized);
    expect(mapPhase(LibraryStatus.loading, 0, false), MapPhase.loadingMedia);
    expect(mapPhase(LibraryStatus.error, 0, false), MapPhase.error);
    expect(mapPhase(LibraryStatus.empty, 0, false), MapPhase.empty);
    expect(
      mapPhase(LibraryStatus.permissionRestricted, 0, false),
      MapPhase.empty,
    );
    // Media exists but none of it is geotagged.
    expect(mapPhase(LibraryStatus.loaded, 0, false), MapPhase.empty);
    expect(mapPhase(LibraryStatus.loaded, 3, false), MapPhase.ready);
    expect(
      mapPhase(LibraryStatus.refreshing, 3, true),
      MapPhase.markerSelected,
    );
    // A selection cannot outlive its markers.
    expect(mapPhase(LibraryStatus.loaded, 0, true), MapPhase.empty);
  });

  testWidgets(
    'gallery map switches and saves tiles without moving the viewport',
    (tester) async {
      final prefs = Prefs.memory();
      final settings = SettingsController.instance..attach(prefs);
      late MediaLibrary library;
      await tester.runAsync(() async {
        library = MediaLibrary(
          gateway: FakeGateway([photo(1)]),
          index: tempIndex(),
        );
        await library.index.recordCapture('image:1', location: delhi);
        await library.refresh();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaMap(
              library: library,
              onOpen: (_) {},
              topPadding: 56,
              bottomPadding: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TileMap>(find.byType(TileMap))
          .controller;
      const center = GeoPoint(28.62, 77.22);
      controller.move(center, 13);
      await tester.pump();
      for (final kind in MapKind.values) {
        await tester.tap(
          find.byTooltip('Map style: ${settings.mapKind.label}'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is CheckedPopupMenuItem<MapKind> && widget.value == kind,
          ),
        );
        await tester.pumpAndSettle();
        final map = tester.widget<TileMap>(find.byType(TileMap));
        expect(settings.mapKind, kind);
        expect(prefs.getString('mapKind'), kind.name);
        expect(map.sources.first.urlTemplate, kind.tileUrl);
        expect(map.sources.length, kind == MapKind.hybrid ? 2 : 1);
        expect(map.controller, same(controller));
        expect(controller.center, center);
        expect(controller.zoom, 13);
        expect(map.markers, hasLength(1));
      }
      await tester.tap(find.text('Powered by Esri · Map credits'));
      await tester.pumpAndSettle();
      expect(find.text('Map credits'), findsOneWidget);
      expect(
        find.textContaining('Regional imagery and label partners'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(controller.center, center);
      expect(controller.zoom, 13);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      library.dispose();
      settings.attach(Prefs.memory());
    },
  );
}
