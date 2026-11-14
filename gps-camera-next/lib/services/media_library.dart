import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import 'native.dart';

enum StorageAccess { granted, denied, permanentlyDenied }

/// Everything the Library needs from the platform. Faked in tests.
abstract class MediaGateway {
  Future<StorageAccess> ensureAccess();
  Future<List<MediaItem>> list();
  Future<Uint8List?> thumbnail(MediaItem item, int size);
  Future<Uint8List?> read(MediaItem item);
  Future<MediaLocation?> location(MediaItem item);
  Future<bool> delete(MediaItem item);
  Future<void> share(MediaItem item);
  Stream<void> get changes;
}

class PlatformMediaGateway implements MediaGateway {
  const PlatformMediaGateway();

  static const _channel = MethodChannel(
    'com.gpscamera.gps_camera_next/library',
  );
  static const _events = EventChannel(
    'com.gpscamera.gps_camera_next/library_changes',
  );

  Map<String, Object?> _ref(MediaItem item) => {
    'id': item.id,
    'kind': item.kind.name,
  };

  @override
  Future<StorageAccess> ensureAccess() async {
    final access = await _channel.invokeMethod<String>('ensureAccess');
    return StorageAccess.values.firstWhere(
      (value) => value.name == access,
      orElse: () => StorageAccess.denied,
    );
  }

  @override
  Future<List<MediaItem>> list() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('list');
    return [for (final row in rows ?? const []) MediaItem.fromRow(row)];
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item, int size) => _channel
      .invokeMethod<Uint8List>('thumbnail', {..._ref(item), 'size': size});

  @override
  Future<Uint8List?> read(MediaItem item) =>
      _channel.invokeMethod<Uint8List>('read', _ref(item));

  @override
  Future<MediaLocation?> location(MediaItem item) async {
    final row = await _channel.invokeMapMethod<String, Object?>(
      'location',
      _ref(item),
    );
    return MediaLocation.fromJson(row);
  }

  @override
  Future<bool> delete(MediaItem item) async =>
      await _channel.invokeMethod<bool>('delete', _ref(item)) ?? false;

  @override
  Future<void> share(MediaItem item) =>
      _channel.invokeMethod<void>('share', {..._ref(item), 'mime': item.mime});

  @override
  Stream<void> get changes => _events.receiveBroadcastStream();
}

/// Capture locations recorded by the app, plus cached metadata lookups.
///
/// This is the app's own record of where each item was captured. Videos carry
/// no location metadata, so the index is the only source for them.
class MediaIndex {
  MediaIndex({Future<File> Function()? file}) : _file = file ?? _defaultFile;

  final Future<File> Function() _file;
  final _entries = <String, Map<String, Object?>>{};
  bool _loaded = false;
  Future<void> _writes = Future.value();

  static Future<File> _defaultFile() async {
    final dir = await Native.supportDir();
    return File('${dir.path}/media_index.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        for (final entry in json.entries) {
          if (entry.value is Map) {
            _entries[entry.key as String] = Map<String, Object?>.from(
              entry.value as Map,
            );
          }
        }
      }
    } catch (_) {
      // A damaged index only costs cached lookups.
    }
  }

  /// A location the app knows, or one already read from the file's metadata.
  MediaLocation? location(MediaItem item) =>
      MediaLocation.fromJson(_entries[item.key]);

  /// True once this revision of the file was checked, located or not.
  bool isResolved(MediaItem item) {
    final entry = _entries[item.key];
    if (entry == null) return false;
    return entry['captured'] == true ||
        entry['checked'] == item.modifiedSeconds;
  }

  String? originalOf(MediaItem item) =>
      _entries[item.key]?['original'] as String?;

  /// Record what the app knew at the shutter.
  Future<void> recordCapture(
    String key, {
    MediaLocation? location,
    String? originalKey,
  }) async {
    await load();
    _entries[key] = {
      ...?location?.toJson(),
      'captured': true,
      'original': ?originalKey,
    };
    await _save();
  }

  void cacheLookup(MediaItem item, MediaLocation? location) {
    _entries[item.key] = {
      ...?_entries[item.key],
      ...?location?.toJson(),
      'checked': item.modifiedSeconds,
    };
  }

  /// Drop entries for media that no longer exists.
  bool prune(Set<String> liveKeys) {
    final before = _entries.length;
    _entries.removeWhere((key, _) => !liveKeys.contains(key));
    return _entries.length != before;
  }

  Future<void> save() => _save();

  Future<void> _save() {
    final snapshot = jsonEncode(_entries);
    return _writes = _writes.then((_) async {
      try {
        final file = await _file();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        // Retried on the next change.
      }
    });
  }
}

enum LibraryStatus {
  idle,
  loading,
  loaded,
  refreshing,
  empty,
  permissionRestricted,
  error,
}

/// The app's media, newest first, with one explicit load state.
class MediaLibrary extends ChangeNotifier {
  MediaLibrary({MediaGateway? gateway, MediaIndex? index})
    : gateway = gateway ?? const PlatformMediaGateway(),
      index = index ?? MediaIndex();

  static MediaLibrary instance = MediaLibrary();

  static const mapLimit = 20;

  final MediaGateway gateway;
  final MediaIndex index;

  LibraryStatus _status = LibraryStatus.idle;
  List<MediaItem> _items = const [];
  List<MediaItem> _mapItems = const [];
  bool _permanentlyDenied = false;
  int _generation = 0;
  Future<void>? _loading;
  bool _reloadRequested = false;
  StreamSubscription<void>? _changes;
  Timer? _changeDebounce;
  bool _disposed = false;

  LibraryStatus get status => _status;
  List<MediaItem> get items => _items;
  bool get permanentlyDenied => _permanentlyDenied;
  bool get hasItems => _items.isNotEmpty;

  /// The newest geotagged items, at most [mapLimit].
  List<MediaItem> get mapItems => _mapItems;

  MediaLocation? locationOf(MediaItem item) => index.location(item);

  MediaItem? originalOf(MediaItem item) {
    final key = index.originalOf(item);
    if (key == null) return null;
    for (final candidate in _items) {
      if (candidate.key == key) return candidate;
    }
    return null;
  }

  /// Loads or reloads. Calls made while a load runs collapse into one rerun.
  Future<void> refresh() {
    final running = _loading;
    if (running != null) {
      _reloadRequested = true;
      return running;
    }
    return _loading = _run().whenComplete(() => _loading = null);
  }

  Future<void> _run() async {
    // Never notify inside the caller's build.
    await Future<void>.value();
    do {
      _reloadRequested = false;
      await _load();
    } while (_reloadRequested && !_disposed);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _set(
      _status == LibraryStatus.loaded || _status == LibraryStatus.empty
          ? LibraryStatus.refreshing
          : LibraryStatus.loading,
    );
    try {
      final access = await gateway.ensureAccess();
      if (_stale(generation)) return;
      if (access != StorageAccess.granted) {
        _permanentlyDenied = access == StorageAccess.permanentlyDenied;
        _items = const [];
        _mapItems = const [];
        _set(LibraryStatus.permissionRestricted);
        return;
      }
      await index.load();
      final items = await gateway.list();
      if (_stale(generation)) return;
      _listenForChanges();
      _items = List.unmodifiable(items);
      final pruned = index.prune({for (final item in items) item.key});
      _mapItems = latestGeotagged(items, index.location, limit: mapLimit);
      _set(items.isEmpty ? LibraryStatus.empty : LibraryStatus.loaded);
      if (pruned) unawaited(index.save());
      await _resolveLocations(generation);
    } catch (_) {
      if (_stale(generation)) return;
      _set(LibraryStatus.error);
    }
  }

  /// Reads capture locations from file metadata, newest first, and stops once
  /// the map is full. Results are cached so no file is read twice.
  Future<void> _resolveLocations(int generation) async {
    var located = 0;
    var changed = false;
    for (final item in _items) {
      if (located >= mapLimit) break;
      if (!index.isResolved(item)) {
        MediaLocation? location;
        try {
          location = await gateway.location(item);
        } catch (_) {
          continue; // Unreadable now. Try again on the next load.
        }
        if (_stale(generation)) return;
        index.cacheLookup(item, location);
        changed = true;
      }
      if (index.location(item) != null) located++;
    }
    if (!changed) return;
    unawaited(index.save());
    _mapItems = latestGeotagged(_items, index.location, limit: mapLimit);
    notifyListeners();
  }

  /// Newest [limit] items that have a valid capture location.
  static List<MediaItem> latestGeotagged(
    Iterable<MediaItem> items,
    MediaLocation? Function(MediaItem) locate, {
    int limit = mapLimit,
  }) {
    final seen = <String>{};
    final eligible = [
      for (final item in items)
        if (locate(item) != null && seen.add(item.key)) item,
    ]..sort(newestFirst);
    return List.unmodifiable(eligible.take(limit));
  }

  static int newestFirst(MediaItem a, MediaItem b) {
    final byTime = b.taken.compareTo(a.taken);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  Future<bool> delete(MediaItem item) async {
    if (!await gateway.delete(item)) return false;
    ++_generation; // A list read before the delete must not bring it back.
    _items = List.unmodifiable(_items.where((other) => other.key != item.key));
    index.prune({for (final other in _items) other.key});
    unawaited(index.save());
    _mapItems = latestGeotagged(_items, index.location, limit: mapLimit);
    _set(_items.isEmpty ? LibraryStatus.empty : LibraryStatus.loaded);
    unawaited(refresh());
    return true;
  }

  void _listenForChanges() {
    _changes ??= gateway.changes.listen((_) {
      _changeDebounce?.cancel();
      _changeDebounce = Timer(const Duration(milliseconds: 400), refresh);
    }, onError: (Object _) {});
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _set(LibraryStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _changeDebounce?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}
