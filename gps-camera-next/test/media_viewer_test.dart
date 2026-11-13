import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/media_item.dart';
import 'package:gps_camera_next/screens/library/library_screen.dart';
import 'package:gps_camera_next/screens/library/media_grid.dart';
import 'package:gps_camera_next/screens/library/media_viewer.dart';
import 'package:gps_camera_next/screens/library/video_page.dart';
import 'package:gps_camera_next/services/media_library.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_media.dart';

/// Records every player the app creates, so leaks and duplicates show up.
class FakePlayers extends VideoPlayerPlatform {
  int _next = 0;
  final live = <int>{};
  final created = <String>[];
  final playing = <int>{};
  final volumes = <int, double>{};
  final positions = <int, Duration>{};
  final events = <int, StreamController<VideoEvent>>{};
  bool failNext = false;
  int maxLive = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++_next;
    created.add(options.dataSource.uri ?? '');
    live.add(id);
    if (live.length > maxLive) maxLive = live.length;
    final fail = failNext;
    failNext = false;
    events[id] = StreamController<VideoEvent>(
      onListen: () {
        if (fail) {
          events[id]!.addError(
            PlatformException(code: 'VideoError', message: 'decoder'),
          );
        } else {
          events[id]!.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 12),
              size: const Size(1920, 1080),
            ),
          );
        }
      },
    );
    return id;
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    live.remove(playerId);
    playing.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    if (!live.contains(playerId)) throw StateError('play after dispose');
    playing.add(playerId);
    events[playerId]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {
    playing.remove(playerId);
    if (live.contains(playerId)) {
      events[playerId]!.add(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: false,
        ),
      );
    }
  }

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes[playerId] = volume;

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      positions[playerId] = position;

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.teal);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.teal);
}

/// The player plugin finishes disposing on the real event loop, which the
/// test clock does not advance.
Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Unmounts everything and lets the bounded player teardown run out.
Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await flush(tester);
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  late FakeGateway gateway;
  late MediaLibrary library;
  late FakePlayers players;

  Future<void> open(
    WidgetTester tester,
    List<MediaItem> items, {
    int at = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    players = FakePlayers();
    VideoPlayerPlatform.instance = players;
    VideoPage.debugResetTeardown();
    gateway = FakeGateway(items);
    library = MediaLibrary(gateway: gateway, index: tempIndex());
    MediaLibrary.instance = library;
    await tester.runAsync(library.refresh);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewer(library: library, initial: library.items[at]),
      ),
    );
    await flush(tester);
    await flush(tester);
  }

  Future<void> swipe(WidgetTester tester, {bool forward = true}) async {
    await tester.drag(find.byType(PageView), Offset(forward ? -340 : 340, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await flush(tester);
    await flush(tester);
  }

  testWidgets('shows a photo with its date and toggles the controls', (
    tester,
  ) async {
    await open(tester, [photo(1, minute: 3)]);
    expect(find.text('1 November 2026'), findsOneWidget);
    expect(find.byType(PhotoPage), findsOneWidget);
    expect(find.byTooltip('Details'), findsOneWidget);
    await tester.tap(find.byType(PhotoPage));
    await tester.pump(kDoubleTapTimeout);
    await tester.pump(const Duration(milliseconds: 200));
    final hidden = tester.widgetList<AnimatedOpacity>(
      find.ancestor(
        of: find.byTooltip('Details'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(hidden.first.opacity, 0);
    expect(players.created, isEmpty);
    await close(tester);
  });

  testWidgets('double-tap zooms, locks paging, and resets', (tester) async {
    await open(tester, [photo(2, minute: 2), photo(1, minute: 1)]);
    final center = tester.getCenter(find.byType(PhotoPage));
    Future<void> doubleTap() async {
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
    }

    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    await doubleTap();
    expect(scale(), greaterThan(2));
    // While zoomed a horizontal drag pans the photo, it does not change page.
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.drag(find.byType(PhotoPage), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image:2')), findsOneWidget);
    await doubleTap();
    expect(scale(), closeTo(1, .001));
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<PageScrollPhysics>(),
    );
    await close(tester);
  });

  testWidgets('plays a video, pauses, mutes and seeks', (tester) async {
    await open(tester, [video(5)]);
    expect(players.created.single, 'content://media/external/video/media/5');
    expect(players.playing, {1});
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(players.playing, isEmpty);
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(players.volumes[1], 0);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(players.volumes[1], 1);

    final bar = tester.getRect(find.byType(Slider));
    await tester.tapAt(bar.centerLeft + Offset(bar.width * .5, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(players.positions[1]!.inSeconds, inInclusiveRange(4, 8));
    // Seeking while paused does not start playback.
    expect(players.playing, isEmpty);
    await close(tester);
  });

  testWidgets('holds one player however many videos are browsed', (
    tester,
  ) async {
    await open(tester, [
      video(4, minute: 4),
      video(3, minute: 3),
      photo(2, minute: 2),
      video(1, minute: 1),
    ]);
    expect(players.live, hasLength(1));
    await swipe(tester);
    expect(players.live, hasLength(1));
    expect(players.created.last, endsWith('/3'));
    await swipe(tester); // Onto the photo: no decoder at all.
    expect(players.live, isEmpty);
    expect(players.playing, isEmpty);
    await swipe(tester);
    expect(players.created.last, endsWith('/1'));
    for (var i = 0; i < 3; i++) {
      await swipe(tester, forward: false);
    }
    expect(players.live, hasLength(1));
    expect(players.maxLive, 1);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('returns to a video at the position it was left', (tester) async {
    await open(tester, [video(2, minute: 2), video(1, minute: 1)]);
    // The player reports its position while it plays.
    players.positions[1] = const Duration(seconds: 7);
    await tester.pump(const Duration(milliseconds: 600));
    await swipe(tester);
    await swipe(tester, forward: false);
    expect(players.created.last, endsWith('/2'));
    expect(players.positions[players.live.single], const Duration(seconds: 7));
    await close(tester);
  });

  testWidgets('stops playback and frees the player on exit', (tester) async {
    await open(tester, [video(5)]);
    expect(players.playing, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
    expect(players.live, isEmpty);
    expect(players.playing, isEmpty);
    await close(tester);
  });

  testWidgets('pauses when the app goes to the background', (tester) async {
    await open(tester, [video(5)]);
    expect(players.playing, {1});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(players.playing, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    // Resumes paused, in place, with the same player.
    expect(players.playing, isEmpty);
    expect(players.live, {1});
    expect(find.byTooltip('Play'), findsOneWidget);
    await close(tester);
  });

  testWidgets('reports an unplayable video and can retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    players = FakePlayers()..failNext = true;
    VideoPlayerPlatform.instance = players;
    VideoPage.debugResetTeardown();
    gateway = FakeGateway([video(5)]);
    library = MediaLibrary(gateway: gateway, index: tempIndex());
    MediaLibrary.instance = library;
    await tester.runAsync(library.refresh);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewer(library: library, initial: library.items.first),
      ),
    );
    await flush(tester);
    await flush(tester);
    expect(find.text('This video can’t be played.'), findsOneWidget);
    expect(players.playing, isEmpty);
    await tester.tap(find.text('Try again'));
    await flush(tester);
    await flush(tester);
    expect(find.text('This video can’t be played.'), findsNothing);
    expect(players.live, hasLength(1));
    expect(players.playing, hasLength(1));
    await close(tester);
  });

  testWidgets('deleting moves to a neighbour, then closes when empty', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    players = FakePlayers();
    VideoPlayerPlatform.instance = players;
    VideoPage.debugResetTeardown();
    gateway = FakeGateway([photo(2, minute: 2), photo(1, minute: 1)]);
    library = MediaLibrary(gateway: gateway, index: tempIndex());
    MediaLibrary.instance = library;
    await tester.runAsync(library.refresh);
    String? leftOn;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => leftOn = await openMediaViewer(
              context,
              library,
              library.items.first,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.items, hasLength(2));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(gateway.items.single.key, 'image:1');
    expect(find.byKey(const ValueKey('image:1')), findsOneWidget);

    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(gateway.shared, ['image:1']);

    await tester.tap(find.byTooltip('Back to library'));
    await tester.pumpAndSettle();
    expect(leftOn, 'image:1');
    expect(find.byType(MediaViewer), findsNothing);
    await close(tester);
  });

  testWidgets('details show the saved capture location', (tester) async {
    await open(tester, [photo(1)]);
    await tester.runAsync(
      () => library.index.recordCapture(
        'image:1',
        location: const MediaLocation(28.6139, 77.209, place: 'New Delhi'),
      ),
    );
    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.text('New Delhi'), findsOneWidget);
    expect(find.text('28.613900, 77.209000'), findsOneWidget);
    expect(find.text('3000 × 4000  ·  2.0 MB'), findsOneWidget);
    await close(tester);
  });

  testWidgets('library opens an item and returns to the grid', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    players = FakePlayers();
    VideoPlayerPlatform.instance = players;
    VideoPage.debugResetTeardown();
    gateway = FakeGateway([for (var i = 0; i < 40; i++) photo(i, minute: i)]);
    library = MediaLibrary(gateway: gateway, index: tempIndex());
    MediaLibrary.instance = library;
    await tester.runAsync(library.refresh);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(library: library)));
    await tester.pumpAndSettle();
    expect(find.byType(MediaGrid), findsOneWidget);
    await tester.tap(find.byType(MediaTile).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Back to library'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewer), findsNothing);
    expect(find.byType(MediaGrid), findsOneWidget);

    // The map tab with nothing geotagged says so instead of inventing places.
    await tester.tap(find.bySemanticsLabel('Map'));
    await tester.pumpAndSettle();
    expect(find.text('No locations yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('library explains empty and restricted states', (tester) async {
    gateway = FakeGateway();
    library = MediaLibrary(gateway: gateway, index: tempIndex());
    // Load first: the index reads a real file, which the fake clock can't run.
    await tester.runAsync(library.refresh);
    await tester.pumpWidget(MaterialApp(home: LibraryScreen(library: library)));
    await tester.pump();
    await tester.pump();
    expect(find.text('No photos or videos yet'), findsOneWidget);
    gateway.access = StorageAccess.denied;
    await tester.runAsync(library.refresh);
    await tester.pump();
    expect(find.text('Storage access is off'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.byType(VideoPage), findsNothing);
    await close(tester);
  });
}
