import 'dart:io';
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

  static const _channel = MethodChannel('com.gpscamera.gps_camera_pro/gallery');

  /// Rasterise a [RepaintBoundary] and return the result as JPEG bytes.
  /// We encode to PNG in Dart first (lossless, compact for channel transfer),
  /// then ask Android to decode + re-encode as JPEG — avoids RGBA→ARGB
  /// byte-order issues that arise when passing raw pixel data.
  Future<Uint8List?> rasterize(RenderRepaintBoundary boundary,
      {double pixelRatio = 3.0}) async {
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

  /// Save JPEG [bytes] to the device gallery via Android MediaStore.
  /// Returns the content:// URI (API 29+) or file path (older) so the caller
  /// can track the gallery entry for later deletion. Returns null on failure.
  Future<String?> saveImageToGallery(Uint8List bytes) async {
    try {
      final name = 'GPS_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name,
        'album': 'GPS Camera',
      });
      return ref;
    } catch (_) {
      return null;
    }
  }

  /// Save the un-stamped original camera JPEG to the gallery (used when
  /// "Save Original" is enabled in settings).
  Future<void> saveRawToGallery(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final name = 'GPS_original_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _channel.invokeMethod<void>('saveImage', {
        'bytes': bytes,
        'name': name,
        'album': 'GPS Camera',
      });
    } catch (_) {}
  }

  /// Save a recorded video file to the device gallery.
  Future<bool> saveVideoToGallery(String path) async {
    try {
      await Gal.putVideo(path, album: 'GPS Camera');
      return true;
    } catch (_) {
      return false;
    }
  }

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
    } catch (_) {}
    return null;
  }

  /// Save each capture to private app storage for the in-app swipeable viewer.
  /// Pass [galleryRef] (the URI/path returned by [saveImageToGallery]) so the
  /// capture can later be deleted from the gallery as well.
  Future<void> saveLocalCapture(Uint8List bytes, {String? galleryRef}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final capturesDir = Directory('${dir.path}/captures')
        ..createSync(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      await File('${capturesDir.path}/capture_$ts.jpg').writeAsBytes(bytes);
      if (galleryRef != null) {
        await File('${capturesDir.path}/capture_$ts.ref')
            .writeAsString(galleryRef);
      }
    } catch (_) {}
  }

  /// Delete a local capture file AND its corresponding gallery entry.
  /// The gallery ref is read from the companion .ref file written at capture time.
  Future<void> deleteCapture(File localFile) async {
    try {
      final refPath =
          localFile.path.replaceFirst(RegExp(r'\.[^.]+$'), '.ref');
      final refFile = File(refPath);
      if (refFile.existsSync()) {
        final ref = await refFile.readAsString();
        try {
          await _channel.invokeMethod<void>('deleteImage', {'ref': ref});
        } catch (_) {}
        await refFile.delete().catchError((_) => refFile);
      }
      await localFile.delete().catchError((_) => localFile);
    } catch (_) {}
  }

  /// All locally cached captures, newest first.
  Future<List<File>> getLocalCaptures() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final capturesDir = Directory('${dir.path}/captures');
      if (!capturesDir.existsSync()) return [];
      final files = capturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }
}
