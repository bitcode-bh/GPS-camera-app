import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/template.dart';

/// Holds the selected stamp template + custom field configuration, persisted
/// across launches. Singleton [ChangeNotifier] shared by the camera screen and
/// the template/editor screens.
class TemplateController extends ChangeNotifier {
  TemplateController._();
  static final TemplateController instance = TemplateController._();

  SharedPreferences? _prefs;
  final _saved = <String, String>{};
  List<String> get savedNames => _saved.keys.toList(growable: false);

  TemplateConfig config = TemplateConfig.forTemplate(StampTemplate.minimal);

  void attach(SharedPreferences prefs) {
    _prefs = prefs;
    _saved.clear();
    final stored = prefs.getString('savedTemplates');
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored) as Map<String, dynamic>;
        _saved.addAll(
          decoded.map((name, value) => MapEntry(name, value as String)),
        );
      } on Object {
        // Keep the editor usable if stored custom templates cannot be read.
      }
    }
    final saved = prefs.getString('templateConfig');
    if (saved != null) {
      try {
        config = TemplateConfig.decode(saved);
      } catch (_) {
        /* keep default */
      }
    }
    // Migrate away the old default branding title persisted by earlier builds.
    if (config.projectTitle.trim() == 'GPS Map Camera' ||
        config.projectTitle.trim() == 'GPS Camera') {
      config.projectTitle = '';
    }
  }

  void saveTemplate(String name) {
    final title = name.trim();
    if (title.isEmpty) return;
    _saved[title] = config.encode();
    _prefs?.setString('savedTemplates', jsonEncode(_saved));
    notifyListeners();
  }

  void applySavedTemplate(String name) {
    final encoded = _saved[name];
    if (encoded == null) return;
    final number = config.photoNumber;
    config = TemplateConfig.decode(encoded)..photoNumber = number;
    _commit();
  }

  void resetTemplate() {
    final number = config.photoNumber;
    config = TemplateConfig.forTemplate(StampTemplate.minimal)
      ..photoNumber = number;
    _commit();
  }

  void _commit() {
    _prefs?.setString('templateConfig', config.encode());
    notifyListeners();
  }

  /// Switch to a preset template, resetting fields to that template's defaults
  /// (custom text values are preserved).
  void selectTemplate(StampTemplate t) {
    config.template = t;
    config.fields = TemplateConfig.defaultsFor(t);
    config.width = t == StampTemplate.minimal ? .72 : 1;
    config.palette = StampPalette.white;
    _commit();
  }

  void toggleField(StampField f, bool on) {
    if (on) {
      config.fields.add(f);
    } else {
      config.fields.remove(f);
    }
    _commit();
  }

  void update(void Function(TemplateConfig c) change) {
    change(config);
    _commit();
  }

  void bumpPhotoNumber() {
    config.photoNumber += 1;
    _commit();
  }
}
