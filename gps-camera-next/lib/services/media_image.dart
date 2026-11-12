import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/media_item.dart';
import 'media_library.dart';

/// A MediaStore thumbnail, decoded off the UI thread and held in Flutter's
/// image cache. [size] is the longest edge in pixels.
class MediaThumbnail extends ImageProvider<MediaThumbnail> {
  const MediaThumbnail(this.item, {this.size = 256});

  final MediaItem item;
  final int size;

  @override
  Future<MediaThumbnail> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    MediaThumbnail key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: item.key,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final gateway = MediaLibrary.instance.gateway;
      Uint8List? bytes;
      // A file saved a moment ago may not have a thumbnail yet. Ask twice.
      for (var attempt = 0; attempt < 2 && bytes == null; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        try {
          bytes = await gateway.thumbnail(item, size);
        } catch (_) {
          if (attempt > 0) rethrow;
        }
      }
      if (bytes == null || bytes.isEmpty) throw StateError('No thumbnail');
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Let a later build retry instead of caching the failure.
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaThumbnail &&
      other.item.revision == item.revision &&
      other.size == size;

  @override
  int get hashCode => Object.hash(item.revision, size);
}

/// The full photo. Wrap in [ResizeImage] to bound the decoded size.
class MediaImage extends ImageProvider<MediaImage> {
  const MediaImage(this.item);

  final MediaItem item;

  @override
  Future<MediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(MediaImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: item.key,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await MediaLibrary.instance.gateway.read(item);
      if (bytes == null || bytes.isEmpty) throw StateError('No image');
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaImage && other.item.revision == item.revision;

  @override
  int get hashCode => item.revision.hashCode;
}
