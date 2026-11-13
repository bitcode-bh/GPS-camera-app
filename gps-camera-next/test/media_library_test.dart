import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/models/media_item.dart';
import 'package:gps_camera_next/services/capture_service.dart';
import 'package:gps_camera_next/services/media_library.dart';

import 'support/fake_media.dart';

void main() {
  const delhi = MediaLocation(28.6139, 77.2090, place: 'New Delhi');

  test('loads newest first and reports each state', () async {
    final gateway = FakeGateway([photo(1, minute: 1), video(2, minute: 5)]);
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    final states = <LibraryStatus>[];
    library.addListener(() => states.add(library.status));
    expect(library.status, LibraryStatus.idle);
    await library.refresh();
    expect(states.first, LibraryStatus.loading);
    expect(library.status, LibraryStatus.loaded);
    expect(
      [for (final item in library.items) item.key],
      ['video:2', 'image:1'],
    );
    states.clear();
    await library.refresh();
    expect(states.first, LibraryStatus.refreshing);
    expect(library.status, LibraryStatus.loaded);
  });

  test('empty, restricted and failed loads are distinct states', () async {
    final gateway = FakeGateway();
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    await library.refresh();
    expect(library.status, LibraryStatus.empty);

    gateway.access = StorageAccess.permanentlyDenied;
    gateway.items = [photo(1)];
    await library.refresh();
    expect(library.status, LibraryStatus.permissionRestricted);
    expect(library.permanentlyDenied, isTrue);
    // Never "loaded" while access is missing.
    expect(library.items, isEmpty);
    expect(library.mapItems, isEmpty);

    gateway.access = StorageAccess.granted;
    gateway.failList = true;
    await library.refresh();
    expect(library.status, LibraryStatus.error);

    gateway.failList = false;
    await library.refresh();
    expect(library.status, LibraryStatus.loaded);
  });

  test('refreshes requested during a load collapse into one rerun', () async {
    final gateway = FakeGateway([photo(1)])..listGate = Completer();
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    final first = library.refresh();
    await pumpEventQueue();
    for (var i = 0; i < 5; i++) {
      unawaited(library.refresh());
    }
    gateway.items.add(photo(2, minute: 9));
    gateway.listGate!.complete();
    await first;
    expect(gateway.listCalls, 2);
    expect(library.items.first.key, 'image:2');
  });

  test('a list read before a delete cannot bring the item back', () async {
    final gateway = FakeGateway([photo(1), photo(2, minute: 2)]);
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    await library.refresh();
    // A slow reload is in flight with the old list when the delete lands.
    gateway.listGate = Completer();
    final reload = library.refresh();
    await pumpEventQueue();
    expect(await library.delete(library.items.first), isTrue);
    expect([for (final item in library.items) item.key], ['image:1']);
    gateway.listGate!.complete();
    await reload;
    await pumpEventQueue();
    expect([for (final item in library.items) item.key], ['image:1']);
    expect(library.status, LibraryStatus.loaded);
  });

  test('deleting the last item leaves an empty library', () async {
    final gateway = FakeGateway([photo(1)]);
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    await library.refresh();
    await library.delete(library.items.single);
    expect(library.status, LibraryStatus.empty);
  });

  test('reloads when MediaStore reports a change', () async {
    final gateway = FakeGateway([photo(1)]);
    final library = MediaLibrary(gateway: gateway, index: tempIndex());
    await library.refresh();
    gateway.items.clear(); // Deleted from another app.
    gateway.notifyChanged();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await pumpEventQueue();
    expect(library.status, LibraryStatus.empty);
    library.dispose();
  });

  group('map selection', () {
    test('takes the newest 20 geotagged items, not the newest 20 items', () {
      // 30 newer items without a location, then 25 older ones with one.
      final items = [
        for (var i = 0; i < 30; i++) photo(100 + i, minute: 30 + i % 29),
        for (var i = 0; i < 25; i++)
          i.isEven ? photo(i, minute: i) : video(i, minute: i),
      ];
      final picked = MediaLibrary.latestGeotagged(
        items,
        (item) => item.id < 100 ? delhi : null,
      );
      expect(picked, hasLength(20));
      expect(picked.every((item) => item.id < 100), isTrue);
      expect(picked.first.id, 24);
      expect(picked.last.id, 5);
      expect(picked.any((item) => item.isVideo), isTrue);
      expect(picked.any((item) => !item.isVideo), isTrue);
    });

    test('never shows one item twice', () {
      final picked = MediaLibrary.latestGeotagged([
        photo(1),
        photo(1),
        video(1),
      ], (_) => delhi);
      expect([
        for (final item in picked) item.key,
      ], unorderedEquals(['video:1', 'image:1']));
    });

    test('rejects missing, out-of-range and null-island coordinates', () {
      expect(MediaLocation.isValid(28.6, 77.2), isTrue);
      expect(MediaLocation.isValid(null, 77.2), isFalse);
      expect(MediaLocation.isValid(0, 0), isFalse);
      expect(MediaLocation.isValid(91, 10), isFalse);
      expect(MediaLocation.isValid(10, 181), isFalse);
      expect(MediaLocation.isValid(double.nan, 10), isFalse);
      expect(MediaLocation.fromJson({'lat': 0, 'lon': 0}), isNull);
      expect(MediaLocation.fromJson({'lat': -33.9, 'lon': 18.4})?.lat, -33.9);
    });

    test('reads file metadata newest first and stops at 20', () async {
      final gateway = FakeGateway([
        for (var i = 0; i < 40; i++) photo(i, minute: i),
      ]);
      for (final item in gateway.items) {
        gateway.located[item.key] = delhi;
      }
      final library = MediaLibrary(gateway: gateway, index: tempIndex());
      await library.refresh();
      expect(library.mapItems, hasLength(20));
      expect(library.mapItems.first.id, 39);
      // Only as many files were opened as the map needed.
      expect(gateway.locationCalls, hasLength(20));
      // A second load reads nothing again.
      await library.refresh();
      expect(gateway.locationCalls, hasLength(20));
    });

    test('items without a location are checked once and skipped', () async {
      final gateway = FakeGateway([photo(1, minute: 1), photo(2, minute: 2)]);
      gateway.located['image:1'] = delhi;
      final library = MediaLibrary(gateway: gateway, index: tempIndex());
      await library.refresh();
      await library.refresh();
      expect([for (final item in library.mapItems) item.key], ['image:1']);
      expect(gateway.locationCalls, ['image:2', 'image:1']);
    });

    test(
      'a capture recorded by the app appears without reading the file',
      () async {
        final gateway = FakeGateway([video(7)]);
        final index = tempIndex();
        final library = MediaLibrary(gateway: gateway, index: index);
        await index.recordCapture('video:7', location: delhi);
        await library.refresh();
        expect(library.mapItems.single.key, 'video:7');
        expect(library.locationOf(library.mapItems.single)?.place, 'New Delhi');
        expect(gateway.locationCalls, isEmpty);
      },
    );

    test('a deleted item leaves the map', () async {
      final gateway = FakeGateway([photo(1), photo(2, minute: 2)]);
      gateway.located['image:1'] = delhi;
      gateway.located['image:2'] = delhi;
      final library = MediaLibrary(gateway: gateway, index: tempIndex());
      await library.refresh();
      expect(library.mapItems, hasLength(2));
      await library.delete(library.items.first);
      expect([for (final item in library.mapItems) item.key], ['image:1']);
    });
  });

  test('the index survives a restart and links originals', () async {
    final index = tempIndex();
    await index.recordCapture(
      'image:1',
      location: delhi,
      originalKey: 'image:2',
    );
    await index.recordCapture('image:2', location: delhi);
    await index.save();
    // Same file, new instance.
    final gateway = FakeGateway([photo(1, minute: 2), photo(2)]);
    final reopened = MediaLibrary(gateway: gateway, index: index);
    await reopened.refresh();
    expect(reopened.originalOf(reopened.items.first)?.key, 'image:2');
    expect(reopened.originalOf(reopened.items.last), isNull);
  });

  test('media keys come from content URIs', () {
    expect(
      CaptureService.mediaKey(
        'content://media/external/images/media/54721',
        video: false,
      ),
      'image:54721',
    );
    expect(
      CaptureService.mediaKey(
        'content://media/external/video/media/9',
        video: true,
      ),
      video(9).key,
    );
    expect(CaptureService.mediaKey('', video: true), isNull);
    expect(CaptureService.mediaKey(null, video: false), isNull);
    expect(
      photo(54721).uri.toString(),
      'content://media/external/images/media/54721',
    );
  });

  test('durations format like a player', () {
    expect(formatMediaDuration(const Duration(seconds: 4)), '0:04');
    expect(formatMediaDuration(const Duration(seconds: 75)), '1:15');
    expect(formatMediaDuration(const Duration(seconds: 3725)), '1:02:05');
  });
}
