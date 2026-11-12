import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Captures the stamped viewfinder composite and saves it to the device gallery
/// via Android's native MediaStore API (no third-party gallery library for photos).
class CaptureService {
  CaptureService._();
  static final CaptureService instance = CaptureService._();

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/gallery',
  );

  /// Rasterise a [RepaintBoundary] and return the result as JPEG bytes.
  /// We encode to PNG in Dart first (lossless, compact for channel transfer),
  /// then ask Android to decode + re-encode as JPEG — avoids RGBA→ARGB
  /// byte-order issues that arise when passing raw pixel data.
  Future<Uint8List?> rasterize(
    RenderRepaintBoundary boundary, {
    double pixelRatio = 3.0,
  }) async {
    try {
      final uiImage = await boundary.toImage(pixelRatio: pixelRatio);
      final pngData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (pngData == null) return null;
      final jpeg = await _channel.invokeMethod<Uint8List>('pngToJpeg', {
        'png': pngData.buffer.asUint8List(),
        'quality': 100,
      });
      return jpeg;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> photoMetadata(File photo) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>('photoMetadata', {
        'path': photo.path,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<Uint8List?> setPhotoLocation(
    Uint8List bytes, {
    String? sourcePath,
    double? latitude,
    double? longitude,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('setPhotoLocation', {
        'bytes': bytes,
        'sourcePath': sourcePath,
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (_) {
      return null;
    }
  }

  /// Save JPEG [bytes] to the device gallery via Android MediaStore.
  /// Returns the content:// URI (API 29+) or file path (older) so the caller
  /// can track the gallery entry for later deletion. Returns null on failure.
  Future<String?> saveImageToGallery(Uint8List bytes) async {
    try {
      final name = 'GPS_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name,
        'album': 'GPS Camera Next',
      });
      return ref;
    } catch (_) {
      return null;
    }
  }

  /// Save the un-stamped original camera JPEG to the gallery (used when
  /// "Save Original" is enabled in settings).
  Future<bool> saveOriginalToGallery(
    String path, {
    File? localCapture,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final bytes = await setPhotoLocation(
        await File(path).readAsBytes(),
        latitude: latitude,
        longitude: longitude,
      );
      if (bytes == null) return false;
      if (localCapture != null) {
        try {
          await originalFor(localCapture).writeAsBytes(bytes);
        } on FileSystemException {
          // The device-gallery original can still be exported.
        }
      }
      final name = 'GPS_original_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name,
        'album': 'GPS Camera Next',
      });
      return ref != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> stampVideo(
    String path, {
    required DateTime startedAt,
    required List<Map<String, Object>> samples,
    required bool clock24,
  }) async {
    try {
      return await _channel.invokeMethod<String>('stampVideo', {
        'path': path,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'samples': samples,
        'clock24': clock24,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Save a recorded video file to the device gallery.
  Future<bool> saveVideoToGallery(String path) async {
    try {
      await Gal.putVideo(path, album: 'GPS Camera Next');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<SavedVideo>> listVideos() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listVideos',
    );
    return [
      for (final row in rows ?? const [])
        SavedVideo(
          id: (row['id'] as num).toInt(),
          name: row['name'] as String,
          duration: Duration(milliseconds: (row['durationMs'] as num).toInt()),
          added: DateTime.fromMillisecondsSinceEpoch(
            (row['addedSeconds'] as num).toInt() * 1000,
          ),
        ),
    ];
  }

  Future<void> openVideo(int id) =>
      _channel.invokeMethod<void>('openVideo', {'id': id});

  /// Open the system gallery app.
  Future<void> openGallery() async {
    try {
      await Gal.open();
    } catch (_) {}
  }

  /// Persist the most recent JPEG capture so the thumbnail survives a restart.
  Future<void> cacheLast(Uint8List bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/last_capture.jpg').writeAsBytes(bytes);
    } catch (_) {}
  }

  Future<Uint8List?> loadLast() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final name in ['last_capture.jpg', 'last_capture.png']) {
        final f = File('${dir.path}/$name');
        if (f.existsSync()) return await f.readAsBytes();
      }
      final captures = await getLocalCaptures();
      if (captures.isNotEmpty) return await captures.first.readAsBytes();
    } catch (_) {}
    return null;
  }

  /// Save each capture to private app storage for the in-app swipeable viewer.
  /// Pass [galleryRef] (the URI/path returned by [saveImageToGallery]) so the
  /// capture can later be deleted from the gallery as well.
  Future<File?> saveLocalCapture(Uint8List bytes, {String? galleryRef}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final capturesDir = Directory('${dir.path}/captures')
        ..createSync(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final photo = await File(
        '${capturesDir.path}/capture_$ts.jpg',
      ).writeAsBytes(bytes);
      if (galleryRef != null) {
        await File(
          '${capturesDir.path}/capture_$ts.ref',
        ).writeAsString(galleryRef);
      }
      return photo;
    } catch (_) {
      return null;
    }
  }

  File originalFor(File capture) => File('${capture.path}.original');

  /// Keep the local copy and its reference if the gallery deletion fails,
  /// so the user can retry without losing access to the photo.
  Future<void> deleteCapture(File localFile) async {
    final refFile = File(
      localFile.path.replaceFirst(RegExp(r'\.[^.]+$'), '.ref'),
    );
    final hasGalleryCopy = await refFile.exists();
    if (hasGalleryCopy) {
      final ref = await refFile.readAsString();
      await _channel.invokeMethod<void>('deleteImage', {'ref': ref});
    }

    final dir = await getApplicationDocumentsDirectory();
    for (final name in ['last_capture.jpg', 'last_capture.png']) {
      final cached = File('${dir.path}/$name');
      if (await cached.exists()) await cached.delete();
    }

    await localFile.delete();
    final original = originalFor(localFile);
    if (await original.exists()) {
      try {
        await original.delete();
      } on FileSystemException {
        // A failed private-sidecar cleanup must not hide a successful delete.
      }
    }
    if (hasGalleryCopy) {
      try {
        await refFile.delete();
      } on FileSystemException {
        // The photo is already gone. The sidecar is ignored by the viewer.
      }
    }
  }

  /// All locally cached captures, newest first.
  ///
  /// The directory scan + sort runs on a background isolate via [Isolate.run]
  /// so opening the gallery never blocks the UI thread, even with thousands of
  /// captures. Returns paths (isolates can't return live [File] handles), which
  /// are rehydrated into [File]s on return.
  Future<List<File>> getLocalCaptures() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final capturesPath = '${dir.path}/captures';
      final paths = await Isolate.run<List<String>>(() {
        final capturesDir = Directory(capturesPath);
        if (!capturesDir.existsSync()) return const [];
        return capturesDir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => p.endsWith('.jpg') || p.endsWith('.png'))
            .toList()
          ..sort((a, b) => b.compareTo(a));
      });
      return paths.map((p) => File(p)).toList();
    } catch (_) {
      return [];
    }
  }
}

class SavedVideo {
  const SavedVideo({
    required this.id,
    required this.name,
    required this.duration,
    required this.added,
  });

  final int id;
  final String name;
  final Duration duration;
  final DateTime added;

  bool get stamped => name.startsWith('stamped_');
}
