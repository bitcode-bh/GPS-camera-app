import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Turns a framed capture into files in the device gallery.
///
/// Saving is a fixed sequence: rasterise, tag, write, publish. MediaStore
/// keeps each new file hidden until it is fully written, so a capture never
/// appears in the Library half-saved.
class CaptureService {
  CaptureService._();
  static final CaptureService instance = CaptureService._();

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/gallery',
  );

  /// Snapshot a [RepaintBoundary]. The layer tree is captured when this is
  /// called, so the viewfinder can change again straight away.
  Future<ui.Image?> snapshot(
    RenderRepaintBoundary boundary, {
    double pixelRatio = 3.0,
  }) async {
    try {
      return await boundary.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  /// Encode a snapshot as JPEG. PNG is the lossless transfer format and
  /// Android re-encodes it, which avoids channel byte-order pitfalls.
  Future<Uint8List?> encodeJpeg(ui.Image image) async {
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      return await _channel.invokeMethod<Uint8List>('pngToJpeg', {
        'png': png.buffer.asUint8List(),
        'quality': 100,
      });
    } catch (_) {
      return null;
    } finally {
      image.dispose();
    }
  }

  /// Writes EXIF: capture settings copied from [sourcePath], the GPS position
  /// when given, and the orientation the phone was held in.
  Future<Uint8List?> setPhotoLocation(
    Uint8List bytes, {
    String? sourcePath,
    double? latitude,
    double? longitude,
    int quarterTurns = 0,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('setPhotoLocation', {
        'bytes': bytes,
        'sourcePath': sourcePath,
        'latitude': latitude,
        'longitude': longitude,
        'quarterTurns': quarterTurns,
      });
    } catch (_) {
      return null;
    }
  }

  /// Saves a JPEG to the app's album. Returns its content URI, or null.
  Future<String?> saveImageToGallery(
    Uint8List bytes, {
    required DateTime taken,
    String prefix = 'GPS',
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': '${prefix}_${taken.millisecondsSinceEpoch}.jpg',
        'takenMs': taken.millisecondsSinceEpoch,
      });
    } catch (_) {
      return null;
    }
  }

  /// Saves the unstamped camera JPEG ("Save original"). Returns its URI.
  Future<String?> saveOriginalToGallery(
    String path, {
    required DateTime taken,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final bytes = await setPhotoLocation(
        await File(path).readAsBytes(),
        latitude: latitude,
        longitude: longitude,
      );
      if (bytes == null) return null;
      return await saveImageToGallery(
        bytes,
        taken: taken,
        prefix: 'GPS_original',
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> stampVideo(
    String path, {
    required DateTime startedAt,
    required List<Map<String, Object>> samples,
    required bool clock24,
    List<Map<String, Object>> frames = const [],
    List<double>? stampRect,
  }) async {
    try {
      return await _channel.invokeMethod<String>('stampVideo', {
        'path': path,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'samples': samples,
        'clock24': clock24,
        'frames': frames,
        'stampRect': stampRect,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Saves a finished recording to the app's album. Returns its content URI,
  /// an empty string where the platform reports none, or null on failure.
  Future<String?> saveVideoToGallery(
    String path, {
    required DateTime taken,
    bool stamped = false,
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveVideo', {
        'path': path,
        'name':
            '${stamped ? 'GPS_stamped' : 'GPS_video'}_${taken.millisecondsSinceEpoch}.mp4',
        'takenMs': taken.millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      try {
        await Gal.putVideo(path, album: 'GPS Camera Next');
        return '';
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// `image:42` / `video:42` for a MediaStore content URI, matching
  /// `MediaItem.key`.
  static String? mediaKey(String? uri, {required bool video}) {
    final id = int.tryParse(
      Uri.tryParse(uri ?? '')?.pathSegments.lastOrNull ?? '',
    );
    return id == null ? null : '${video ? 'video' : 'image'}:$id';
  }

  /// Open the system gallery app.
  Future<void> openGallery() async {
    try {
      await Gal.open();
    } catch (_) {}
  }

  /// Earlier builds kept a private copy of every photo beside the gallery
  /// copy. Publish any that never reached the gallery, then drop the
  /// duplicates.
  Future<void> migrateLegacyCaptures() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final captures = Directory('${documents.path}/captures');
      if (await captures.exists()) {
        final files = await captures.list().toList();
        for (final photo in files.whereType<File>()) {
          if (!photo.path.endsWith('.jpg')) continue;
          final base = photo.path.substring(0, photo.path.length - 4);
          if (!await File('$base.ref').exists()) {
            final saved = await saveImageToGallery(
              await photo.readAsBytes(),
              taken: await photo.lastModified(),
            );
            if (saved == null) continue; // Keep it. Retried next launch.
          }
          await photo.delete();
        }
        final left = await captures.list().toList();
        if (!left.any((entry) => entry.path.endsWith('.jpg'))) {
          await captures.delete(recursive: true);
        }
      }
      for (final name in ['last_capture.jpg', 'last_capture.png']) {
        final cached = File('${documents.path}/$name');
        if (await cached.exists()) await cached.delete();
      }
    } catch (_) {
      // Nothing is deleted unless its gallery copy exists.
    }
  }
}
