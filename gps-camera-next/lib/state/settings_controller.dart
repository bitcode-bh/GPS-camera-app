import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/capture_options.dart';
import '../models/coordinates.dart';
import '../models/geo_data.dart';
import '../models/map_kind.dart';

/// App-wide display preferences, persisted across launches. A tiny singleton
/// [ChangeNotifier] so any screen can listen with a [ListenableBuilder] and get
/// granular rebuilds.
class SettingsController extends ChangeNotifier {
  SettingsController._();
  static final SettingsController instance = SettingsController._();

  SharedPreferences? _prefs;

  MapKind mapKind = MapKind.hybrid;
  CoordFormat coordFormat = CoordFormat.decimal;
  AddressFormat addressFormat = AddressFormat.long;
  UnitSystem unitSystem = UnitSystem.metric;
  TempUnit tempUnit = TempUnit.celsius;
  bool clock24 = false;
  bool saveOriginal = false;
  CaptureRatio captureRatio = CaptureRatio.r4_3;
  bool watermark = true;
  bool saveLocation = true;
  static const gpsAccuracyOptions = [10, 25, 50, 100];
  int gpsAccuracyLimit = 25;
  bool stampEnabled = true;
  int timerSeconds = 0;
  double mapZoom = 16.5;

  /// Library grid density. Null until the user pinches the grid.
  int? libraryColumns;

  void attach(SharedPreferences prefs) {
    _prefs = prefs;
    final s = prefs;
    mapKind = _read(MapKind.values, s.getString('mapKind'), MapKind.hybrid);
    coordFormat = _read(
      CoordFormat.values,
      s.getString('coordFormat'),
      CoordFormat.decimal,
    );
    addressFormat = _read(
      AddressFormat.values,
      s.getString('addressFormat'),
      AddressFormat.long,
    );
    unitSystem = _read(
      UnitSystem.values,
      s.getString('unitSystem'),
      UnitSystem.metric,
    );
    tempUnit = _read(
      TempUnit.values,
      s.getString('tempUnit'),
      TempUnit.celsius,
    );
    clock24 = s.getBool('clock24') ?? false;
    saveOriginal = s.getBool('saveOriginal') ?? false;
    captureRatio = _read(
      CaptureRatio.values,
      s.getString('captureRatio'),
      CaptureRatio.r4_3,
    );
    watermark = s.getBool('watermark') ?? true;
    saveLocation = s.getBool('saveLocation') ?? true;
    final accuracyLimit = s.getInt('gpsAccuracyLimit');
    gpsAccuracyLimit = gpsAccuracyOptions.contains(accuracyLimit)
        ? accuracyLimit!
        : 25;
    stampEnabled = s.getBool('stampEnabled') ?? true;
    timerSeconds = s.getInt('timerSeconds') ?? 0;
    mapZoom = s.getDouble('mapZoom') ?? 16.5;
    libraryColumns = s.getInt('libraryColumns');
  }

  static T _read<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  void _commit() {
    final s = _prefs;
    if (s != null) {
      s.setString('mapKind', mapKind.name);
      s.setString('coordFormat', coordFormat.name);
      s.setString('addressFormat', addressFormat.name);
      s.setString('unitSystem', unitSystem.name);
      s.setString('tempUnit', tempUnit.name);
      s.setBool('clock24', clock24);
      s.setBool('saveOriginal', saveOriginal);
      s.setString('captureRatio', captureRatio.name);
      s.setBool('watermark', watermark);
      s.setBool('saveLocation', saveLocation);
      s.setInt('gpsAccuracyLimit', gpsAccuracyLimit);
      s.setBool('stampEnabled', stampEnabled);
      s.setInt('timerSeconds', timerSeconds);
      s.setDouble('mapZoom', mapZoom);
      final columns = libraryColumns;
      if (columns != null) s.setInt('libraryColumns', columns);
    }
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    _commit();
  }
}
