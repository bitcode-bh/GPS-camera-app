import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/geo_data.dart';
import 'package:gps_camera_next/models/map_kind.dart';
import 'package:gps_camera_next/models/template.dart';
import 'package:gps_camera_next/services/map_attribution.dart';
import 'package:gps_camera_next/state/prefs.dart';
import 'package:gps_camera_next/state/settings_controller.dart';
import 'package:gps_camera_next/widgets/geo_stamp.dart';
import 'package:gps_camera_next/widgets/tile_map.dart';
import 'package:gps_camera_next/widgets/map_credits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Measure the long real provider list with Android's normal typeface,
    // rather than the deliberately wide Ahem test glyphs. Reuse SDK fonts.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(config.readAsStringSync())['packages'] as List);
    final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final bytes = File(
      '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  testWidgets('full terrain provider list remains visible in a narrow stamp', (
    tester,
  ) async {
    final previous = MapAttribution.instance;
    addTearDown(() => MapAttribution.instance = previous);
    // The public terrain service's actual copyrightText, checked 15 Nov 2026.
    const credit =
        'Sources: Esri, HERE, Garmin, Intermap, increment P Corp., GEBCO, USGS, FAO, NPS, NRCAN, GeoBase, IGN, Kadaster NL, Ordnance Survey, Esri Japan, METI, Esri China (Hong Kong), (c) OpenStreetMap contributors, and the GIS User Community';
    final service = MapAttribution.instance = MapAttribution(
      fetch: (_) async => jsonEncode({'copyrightText': credit}),
    );
    await service.forKind(MapKind.terrain);
    final settings = SettingsController.instance..attach(Prefs.memory());
    settings.mapKind = MapKind.terrain;
    final config = TemplateConfig.forTemplate(StampTemplate.advance)
      ..width = .75;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: GeoStamp(
                geo: GeoData.demo(),
                config: config,
                settings: settings,
                live: false,
                forCapture: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<TileMap>(find.byType(TileMap)).sources, isNotEmpty);
    expect(find.text('Powered by Esri · $credit'), findsOneWidget);
    final row = tester.getRect(find.byKey(const ValueKey('geostamp-row')));
    final credits = tester.getRect(
      find.byKey(const ValueKey('geostamp-map-credits')),
    );
    expect(row.bottom, tester.getRect(find.byType(GeoStamp)).bottom);
    expect(credits.bottom, lessThanOrEqualTo(row.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'a superseded request cannot populate the current credits cache',
    () async {
      final old = Completer<String>();
      final fresh = Completer<String>();
      var calls = 0;
      final service = MapAttribution(
        fetch: (_) => calls++ == 0 ? old.future : fresh.future,
      );
      final pending = service.forKind(MapKind.normal);
      service.retry(MapKind.normal);
      final current = service.forKind(MapKind.normal);
      old.complete('{"copyrightText":"Old provider"}');
      await pending;
      expect(service.cached(MapKind.normal), isNull);
      fresh.complete('{"copyrightText":"Current provider"}');
      await current;
      expect(service.cached(MapKind.normal), contains('Current provider'));
    },
  );

  testWidgets(
    'cached credits render immediately; switching or refreshing drops old data',
    (tester) async {
      final previous = MapAttribution.instance;
      addTearDown(() => MapAttribution.instance = previous);
      final response = Completer<String>();
      var calls = 0;
      final service = MapAttribution.instance = MapAttribution(
        fetch: (_) async {
          if (calls++ == 0) return '{"copyrightText":"First provider"}';
          return response.future;
        },
      );
      await service.forKind(MapKind.normal);
      Widget page(MapKind kind) => MaterialApp(
        home: MapCreditsBuilder(
          kind: kind,
          builder: (_, credit) => Text(credit ?? 'waiting'),
        ),
      );
      // A completed cache is present in the first layout of a fresh snapshot.
      await tester.pumpWidget(page(MapKind.normal));
      expect(find.text('Powered by Esri · First provider'), findsOneWidget);
      await tester.pumpWidget(page(MapKind.terrain));
      expect(find.text('waiting'), findsOneWidget);
      expect(find.textContaining('First provider'), findsNothing);
      await tester.pumpWidget(page(MapKind.normal));
      expect(find.textContaining('First provider'), findsOneWidget);
      service.retry(MapKind.normal);
      await tester.pumpWidget(page(MapKind.normal));
      expect(find.text('waiting'), findsOneWidget);
      response.complete('{"copyrightText":"New provider"}');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('New provider'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('all layer metadata must supply nonempty copyright information', () {
    expect(
      MapAttribution.parse(
        jsonEncode({
          'copyrightText':
              '<a href="https://example.org">Esri &amp; Partners</a> &#169; OpenStreetMap',
        }),
      ),
      'Esri & Partners © OpenStreetMap',
    );
    for (final body in [
      '{}',
      '{"copyrightText":" "}',
      '{"error":{"code":403}}',
    ]) {
      expect(() => MapAttribution.parse(body), throwsFormatException);
    }
  });

  test(
    'hybrid retains both layer credits and coalesces metadata requests',
    () async {
      final requests = <Uri>[];
      final service = MapAttribution(
        fetch: (uri) async {
          requests.add(uri);
          return jsonEncode({
            'copyrightText': requests.length == 1
                ? 'Imagery provider'
                : 'Label provider',
          });
        },
      );
      final first = service.forKind(MapKind.hybrid);
      expect(service.forKind(MapKind.hybrid), same(first));
      expect(await first, contains('Imagery provider · Label provider'));
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (u) => u.scheme == 'https' && !u.path.contains('/tile/'),
        ),
        isTrue,
      );
      expect(
        requests.every((u) => !u.queryParameters.containsKey('token')),
        isTrue,
      );
      service.retry(MapKind.hybrid);
      await service.forKind(MapKind.hybrid);
      expect(requests, hasLength(4));
    },
  );

  test(
    'failed credits can be retried rather than replaced with guessed names',
    () async {
      var fail = true;
      final service = MapAttribution(
        fetch: (_) async {
          if (fail) throw StateError('offline');
          return '{"copyrightText":"Regional source"}';
        },
      );
      await expectLater(service.forKind(MapKind.normal), throwsStateError);
      fail = false;
      service.retry(MapKind.normal);
      expect(
        await service.forKind(MapKind.normal),
        contains('Regional source'),
      );
    },
  );

  for (final oversized in [false, true]) {
    testWidgets(
      'capture waits for full credits and keeps stable bounds (oversized: $oversized)',
      (tester) async {
        final previous = MapAttribution.instance;
        addTearDown(() => MapAttribution.instance = previous);
        final response = Completer<String>();
        MapAttribution.instance = MapAttribution(fetch: (_) => response.future);
        final settings = SettingsController.instance..attach(Prefs.memory());
        settings.mapKind = MapKind.normal;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 390,
                  child: GeoStamp(
                    geo: GeoData.demo(),
                    config: TemplateConfig.forTemplate(StampTemplate.advance),
                    settings: settings,
                    live: false,
                    forCapture: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final bounds = tester.getRect(find.byType(GeoStamp));
        expect(tester.widget<TileMap>(find.byType(TileMap)).sources, isEmpty);
        final credit = oversized
            ? List.filled(200, 'Regional source').join(', ')
            : 'Esri, Regional imagery partner, © OpenStreetMap contributors';
        response.complete(jsonEncode({'copyrightText': credit}));
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(find.byType(GeoStamp)), bounds);
        final sources = tester.widget<TileMap>(find.byType(TileMap)).sources;
        expect(sources.isEmpty, oversized);
        if (!oversized) {
          expect(find.text('Powered by Esri · $credit'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
