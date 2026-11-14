import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/native.dart';

/// Settings storage: a small JSON file in the app's private folder.
///
/// Reads are synchronous from memory; each change is written in order, to a
/// temporary file first, so a crash never leaves a half-written file.
class Prefs {
  Prefs._(this._values, this._file);

  /// In memory only (tests).
  factory Prefs.memory([Map<String, Object> values = const {}]) =>
      Prefs._({...values}, null);

  static Future<Prefs> load() async {
    final values = <String, Object>{};
    File? file;
    try {
      final dir = await Native.supportDir();
      file = File('${dir.path}/settings.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          for (final entry in json.entries) {
            final value = entry.value;
            if (value != null) values['${entry.key}'] = value as Object;
          }
        }
      }
    } catch (_) {
      // A damaged file only costs the saved settings.
    }
    return Prefs._(values, file);
  }

  final Map<String, Object> _values;
  final File? _file;
  Future<void> _writes = Future.value();

  String? getString(String key) {
    final value = _values[key];
    return value is String ? value : null;
  }

  bool? getBool(String key) {
    final value = _values[key];
    return value is bool ? value : null;
  }

  int? getInt(String key) {
    final value = _values[key];
    return value is num ? value.toInt() : null;
  }

  double? getDouble(String key) {
    final value = _values[key];
    return value is num ? value.toDouble() : null;
  }

  void setString(String key, String value) => _set(key, value);
  void setBool(String key, bool value) => _set(key, value);
  void setInt(String key, int value) => _set(key, value);
  void setDouble(String key, double value) => _set(key, value);

  void _set(String key, Object value) {
    if (_values[key] == value) return;
    _values[key] = value;
    final file = _file;
    if (file == null) return;
    final snapshot = jsonEncode(_values);
    _writes = _writes.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        // Retried with the next change.
      }
    });
  }

  /// Completes when every change so far is on disk.
  Future<void> flush() => _writes;
}
