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

  TemplateConfig config = TemplateConfig.forTemplate(StampTemplate.advance);

  void attach(SharedPreferences prefs) {
    _prefs = prefs;
    final saved = prefs.getString('templateConfig');
    if (saved != null) {
      try {
        config = TemplateConfig.decode(saved);
      } catch (_) {/* keep default */}
    }
    // Migrate away the old default branding title persisted by earlier builds.
    if (config.projectTitle.trim() == 'GPS Map Camera' ||
        config.projectTitle.trim() == 'GPS Camera') {
      config.projectTitle = '';
    }
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

  /// Adjust stamp opacity. Pass [persist: false] while dragging so the live
  /// preview updates without writing prefs on every tick.
  void setStampOpacity(double value, {bool persist = true}) {
    config.stampOpacity = value.clamp(-1.0, 1.0);
    if (persist) {
      _commit();
    } else {
      notifyListeners();
    }
  }
}
