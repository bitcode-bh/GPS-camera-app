import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/screens/library/media_grid.dart';
import 'package:gps_camera_next/services/media_library.dart';

import 'support/fake_media.dart';

void main() {
  group('layout', () {
    test('levels suit the width and tiles never overlap', () {
      for (final width in [320.0, 390.0, 600.0, 900.0]) {
        final levels = GridDensity.levelsFor(width);
        expect(levels, orderedEquals([...levels]..sort()));
        for (final columns in levels) {
          final layout = GridLayout(width: width, columns: columns);
          expect(layout.cell, greaterThan(40), reason: '$width / $columns');
          expect(
            layout.cell * columns + GridLayout.spacing * (columns - 1),
            closeTo(width, .001),
          );
        }
      }
    });

    test('renders the next denser level while between levels', () {
      const levels = [2, 3, 4, 6];
      expect(GridDensity.renderLevel(levels, 3), 3);
      expect(GridDensity.renderLevel(levels, 3.2), 4);
      expect(GridDensity.renderLevel(levels, 4.01), 6);
      expect(GridDensity.renderLevel(levels, 9), 6);
      // The drawn layout is scaled up, never down, inside the level range.
      for (var e = 2.0; e <= 6; e += .1) {
        expect(
          GridDensity.renderLevel(levels, e) / e,
          greaterThanOrEqualTo(1 - 1e-9),
        );
      }
    });

    test('a released pinch settles on the nearest level', () {
      const levels = [2, 3, 4, 6];
      expect(GridDensity.snapLevel(levels, 2.3), 2);
      expect(GridDensity.snapLevel(levels, 2.6), 3);
      expect(GridDensity.snapLevel(levels, 5.2), 6);
      expect(GridDensity.snapLevel(levels, 40), 6);
      expect(GridDensity.snapLevel(levels, .5), 2);
    });

    test('the anchored item returns to the focal point at every level', () {
      const count = 500;
      const focal = Offset(200, 420);
      final from = GridLayout(width: 390, columns: 3, topPadding: 80);
      final anchor = from.anchorAt(Offset(focal.dx, 6000 + focal.dy), count);
      for (final columns in [2, 3, 4, 6]) {
        final to = GridLayout(width: 390, columns: columns, topPadding: 80);
        final scroll = to.scrollFor(anchor.index, anchor.rowFraction, focal.dy);
        final again = to.anchorAt(Offset(focal.dx, scroll + focal.dy), count);
        // Same row of the same item, at the same height on screen.
        expect(again.index ~/ columns, anchor.index ~/ columns);
        expect(again.rowFraction, closeTo(anchor.rowFraction, .001));
      }
    });

    test('anchors stay inside the list', () {
      final layout = GridLayout(width: 390, columns: 3);
      expect(layout.anchorAt(const Offset(380, 99999), 10).index, 9);
      expect(layout.anchorAt(const Offset(0, -50), 10).index, 0);
      expect(layout.anchorAt(Offset.zero, 0).index, 0);
    });
  });

  group('widget', () {
    late FakeGateway gateway;
    final opened = <int>[];
    final saved = <int>[];

    Future<void> pumpGrid(WidgetTester tester, {int? columns}) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      gateway = FakeGateway([
        for (var i = 0; i < 300; i++)
          i % 7 == 0 ? video(i, minute: i % 60) : photo(i, minute: i % 60),
      ]);
      MediaLibrary.instance = MediaLibrary(
        gateway: gateway,
        index: tempIndex(),
      );
      opened.clear();
      saved.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid(
              items: gateway.items,
              initialColumns: columns,
              onOpen: opened.add,
              onColumnsChanged: saved.add,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    int columnsOf(WidgetTester tester) =>
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount;

    double scrollOf(WidgetTester tester) =>
        tester.widget<GridView>(find.byType(GridView)).controller!.offset;

    List<double> zoomScales(WidgetTester tester) => [
      for (final transform in tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(MediaGrid),
          matching: find.byType(Transform),
        ),
      ))
        transform.transform.getMaxScaleOnAxis(),
    ];

    Future<void> pinch(
      WidgetTester tester, {
      required double from,
      required double to,
      Offset center = const Offset(195, 400),
    }) async {
      final a = await tester.startGesture(center - Offset(from / 2, 0));
      final b = await tester.startGesture(
        center + Offset(from / 2, 0),
        pointer: 9,
      );
      const steps = 8;
      for (var i = 1; i <= steps; i++) {
        final span = from + (to - from) * i / steps;
        await a.moveTo(center - Offset(span / 2, 0));
        await b.moveTo(center + Offset(span / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
        // Mid-pinch, scaled layers stand in for the grid, and the top one
        // always fills the viewport.
        final scales = zoomScales(tester);
        expect(scales, isNotEmpty);
        expect(scales.last, greaterThanOrEqualTo(.79));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    testWidgets('starts at the default density and opens a tapped item', (
      tester,
    ) async {
      await pumpGrid(tester);
      expect(columnsOf(tester), 3);
      expect(find.bySemanticsLabel(RegExp('^Video, 0:12')), findsWidgets);
      await tester.tap(find.byType(MediaTile).at(4));
      expect(opened, [4]);
    });

    testWidgets('restores the saved density', (tester) async {
      await pumpGrid(tester, columns: 6);
      expect(columnsOf(tester), 6);
    });

    testWidgets('pinching in adds columns and pinching out removes them', (
      tester,
    ) async {
      await pumpGrid(tester);
      await pinch(tester, from: 200, to: 110);
      expect(columnsOf(tester), greaterThan(3));
      expect(saved.last, columnsOf(tester));
      final dense = columnsOf(tester);
      await pinch(tester, from: 100, to: 260);
      expect(columnsOf(tester), lessThan(dense));
      expect(saved.last, columnsOf(tester));
      // Settled: the real grid is back, drawn at its natural size.
      expect(columnsOf(tester), isPositive);
      expect(zoomScales(tester).every((s) => (s - 1).abs() < .001), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the pinched item under the fingers', (tester) async {
      await pumpGrid(tester);
      await tester.drag(find.byType(GridView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      const focal = Offset(195, 400);
      final before = GridLayout(
        width: 390,
        columns: columnsOf(tester),
      ).anchorAt(Offset(focal.dx, scrollOf(tester) + focal.dy), 300);
      await pinch(tester, from: 200, to: 90, center: focal);
      final columns = columnsOf(tester);
      expect(columns, 6);
      final after = GridLayout(
        width: 390,
        columns: columns,
      ).anchorAt(Offset(focal.dx, scrollOf(tester) + focal.dy), 300);
      // The same item's row is still under the focal point: no jump to top.
      expect(after.index ~/ columns, before.index ~/ columns);
      expect(scrollOf(tester), greaterThan(0));
    });

    testWidgets('a pinch does not open an item or scroll away', (tester) async {
      await pumpGrid(tester);
      await pinch(tester, from: 200, to: 190);
      expect(opened, isEmpty);
      expect(columnsOf(tester), 3);
      expect(scrollOf(tester), 0);
    });

    testWidgets('scrolls a large collection without errors', (tester) async {
      await pumpGrid(tester);
      for (var i = 0; i < 6; i++) {
        await tester.fling(find.byType(GridView), const Offset(0, -900), 4000);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();
      expect(scrollOf(tester), greaterThan(2000));
      // Only the visible tiles exist, however long the list is.
      expect(tester.widgetList(find.byType(MediaTile)).length, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ensureVisible reveals an item left in the viewer', (
      tester,
    ) async {
      await pumpGrid(tester);
      final state = tester.state<MediaGridState>(find.byType(MediaGrid));
      state.ensureVisible(200);
      await tester.pump();
      expect(scrollOf(tester), greaterThan(0));
      final layout = GridLayout(width: 390, columns: 3);
      final top = (200 ~/ 3) * layout.pitch;
      expect(top, greaterThanOrEqualTo(scrollOf(tester) - .5));
      expect(top + layout.cell, lessThanOrEqualTo(scrollOf(tester) + 800.5));
      final offset = scrollOf(tester);
      state.ensureVisible(200); // Already visible: no movement.
      expect(scrollOf(tester), offset);
    });
  });
}
