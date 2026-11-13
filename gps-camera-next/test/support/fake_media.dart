import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gps_camera_next/models/media_item.dart';
import 'package:gps_camera_next/services/media_library.dart';

/// A 1×1 PNG, enough for every thumbnail and photo request.
final onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

MediaItem photo(int id, {int minute = 0}) => MediaItem(
  id: id,
  kind: MediaKind.image,
  name: 'GPS_$id.jpg',
  taken: DateTime(2026, 11, 1, 10, minute),
  modifiedSeconds: 1,
  width: 3000,
  height: 4000,
  sizeBytes: 2 << 20,
  mime: 'image/jpeg',
);

MediaItem video(int id, {int minute = 0, int seconds = 12}) => MediaItem(
  id: id,
  kind: MediaKind.video,
  name: 'GPS_video_$id.mp4',
  taken: DateTime(2026, 11, 1, 10, minute),
  modifiedSeconds: 1,
  duration: Duration(seconds: seconds),
  width: 1920,
  height: 1080,
  sizeBytes: 20 << 20,
  mime: 'video/mp4',
);

class FakeGateway implements MediaGateway {
  FakeGateway([List<MediaItem>? items]) : items = [...?items];

  List<MediaItem> items;
  final located = <String, MediaLocation>{};
  StorageAccess access = StorageAccess.granted;
  bool failList = false;
  Completer<void>? listGate;
  int listCalls = 0;
  final locationCalls = <String>[];
  final shared = <String>[];
  final _changes = StreamController<void>.broadcast();

  void notifyChanged() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<StorageAccess> ensureAccess() async => access;

  @override
  Future<List<MediaItem>> list() async {
    listCalls++;
    final snapshot = [...items]..sort(MediaLibrary.newestFirst);
    await listGate?.future;
    if (failList) throw StateError('MediaStore unavailable');
    return snapshot;
  }

  @override
  Future<MediaLocation?> location(MediaItem item) async {
    locationCalls.add(item.key);
    return located[item.key];
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item, int size) async => onePixel;

  @override
  Future<Uint8List?> read(MediaItem item) async => onePixel;

  @override
  Future<bool> delete(MediaItem item) async {
    final before = items.length;
    items.removeWhere((other) => other.key == item.key);
    return items.length != before;
  }

  @override
  Future<void> share(MediaItem item) async => shared.add(item.key);
}

/// An index stored in a throwaway directory.
MediaIndex tempIndex() {
  final dir = Directory.systemTemp.createTempSync('media-index-');
  return MediaIndex(file: () async => File('${dir.path}/index.json'));
}
