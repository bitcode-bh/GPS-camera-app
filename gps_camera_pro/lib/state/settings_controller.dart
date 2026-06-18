import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/capture_options.dart';
import '../models/coordinates.dart';
import '../models/geo_data.dart';
import '../models/map_kind.dart';

enum RawCaptureMode { jpeg, raw, rawJpeg }
enum HdrMode { auto, on, off }
enum NightMode { off, on }
enum GridType { thirds, square, golden }
enum ProWhiteBalance { auto, daylight, cloudy, shade, fluorescent, incandescent, kelvin }
enum MeteringMode { matrix, center, spot }

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
  bool gridLines = false;
  GridType gridType = GridType.thirds;
  bool shutterSound = true;
  CaptureRatio captureRatio = CaptureRatio.full;
  bool watermark = true;
  bool saveLocation = true;
  bool levelIndicator = false;
  bool histogram = false;
  bool focusPeaking = false;
  bool zebraStripes = false;
  bool proMode = false;
  bool stampEnabled = true;
  RawCaptureMode rawCaptureMode = RawCaptureMode.jpeg;
  HdrMode hdrMode = HdrMode.auto;
  NightMode nightMode = NightMode.off;
  ProWhiteBalance whiteBalance = ProWhiteBalance.auto;
  int kelvin = 5600;
  int? proIso;
  int? proShutterNs;
  double manualFocus = 0.0;
  MeteringMode meteringMode = MeteringMode.matrix;
  FlashMode flashMode = FlashMode.off;

  /// Index into [CameraCapabilityService.resolutions]. 0 = highest resolution
  /// (the default). Stored as an int so it survives the removal of the old
  /// CaptureQuality enum without needing a migration.
  int captureResolutionIndex = 0;

  int timerSeconds = 0;
  bool mirror = false;
  double mapZoom = 16.5;

  void attach(SharedPreferences prefs) {
    _prefs = prefs;
    final s = prefs;
    mapKind = _read(MapKind.values, s.getString('mapKind'), MapKind.hybrid);
    coordFormat =
        _read(CoordFormat.values, s.getString('coordFormat'), CoordFormat.decimal);
    addressFormat =
        _read(AddressFormat.values, s.getString('addressFormat'), AddressFormat.long);
    unitSystem =
        _read(UnitSystem.values, s.getString('unitSystem'), UnitSystem.metric);
    tempUnit = _read(TempUnit.values, s.getString('tempUnit'), TempUnit.celsius);
    clock24 = s.getBool('clock24') ?? false;
    saveOriginal = s.getBool('saveOriginal') ?? false;
    gridLines = s.getBool('gridLines') ?? false;
    gridType = _read(GridType.values, s.getString('gridType'), GridType.thirds);
    shutterSound = s.getBool('shutterSound') ?? true;
    captureRatio =
        _read(CaptureRatio.values, s.getString('captureRatio'), CaptureRatio.full);
    watermark = s.getBool('watermark') ?? true;
    saveLocation = s.getBool('saveLocation') ?? true;
    levelIndicator = s.getBool('levelIndicator') ?? false;
    histogram = s.getBool('histogram') ?? false;
    focusPeaking = s.getBool('focusPeaking') ?? false;
    zebraStripes = s.getBool('zebraStripes') ?? false;
    proMode = s.getBool('proMode') ?? false;
    stampEnabled = true; // Always enable stamp on startup (user's critical requirement)
    rawCaptureMode =
        _read(RawCaptureMode.values, s.getString('rawCaptureMode'), RawCaptureMode.jpeg);
    hdrMode = _read(HdrMode.values, s.getString('hdrMode'), HdrMode.auto);
    nightMode = _read(NightMode.values, s.getString('nightMode'), NightMode.off);
    whiteBalance =
        _read(ProWhiteBalance.values, s.getString('whiteBalance'), ProWhiteBalance.auto);
    kelvin = s.getInt('kelvin') ?? 5600;
    proIso = s.getInt('proIso');
    proShutterNs = s.getInt('proShutterNs');
    manualFocus = s.getDouble('manualFocus') ?? 0.0;
    meteringMode =
        _read(MeteringMode.values, s.getString('meteringMode'), MeteringMode.matrix);
    flashMode = _read(FlashMode.values, s.getString('flashMode'), FlashMode.off);
    captureResolutionIndex = s.getInt('captureResolutionIndex') ?? 0;
    timerSeconds = s.getInt('timerSeconds') ?? 0;
    mirror = s.getBool('mirror') ?? false;
    mapZoom = s.getDouble('mapZoom') ?? 16.5;
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
      s.setBool('gridLines', gridLines);
      s.setString('gridType', gridType.name);
      s.setBool('shutterSound', shutterSound);
      s.setString('captureRatio', captureRatio.name);
      s.setBool('watermark', watermark);
      s.setBool('saveLocation', saveLocation);
      s.setBool('levelIndicator', levelIndicator);
      s.setBool('histogram', histogram);
      s.setBool('focusPeaking', focusPeaking);
      s.setBool('zebraStripes', zebraStripes);
      s.setBool('proMode', proMode);
      s.setBool('stampEnabled', stampEnabled);
      s.setString('rawCaptureMode', rawCaptureMode.name);
      s.setString('hdrMode', hdrMode.name);
      s.setString('nightMode', nightMode.name);
      s.setString('whiteBalance', whiteBalance.name);
      s.setInt('kelvin', kelvin);
      if (proIso == null) {
        s.remove('proIso');
      } else {
        s.setInt('proIso', proIso!);
      }
      if (proShutterNs == null) {
        s.remove('proShutterNs');
      } else {
        s.setInt('proShutterNs', proShutterNs!);
      }
      s.setDouble('manualFocus', manualFocus);
      s.setString('meteringMode', meteringMode.name);
      s.setString('flashMode', flashMode.name);
      s.setInt('captureResolutionIndex', captureResolutionIndex);
      s.setInt('timerSeconds', timerSeconds);
      s.setBool('mirror', mirror);
      s.setDouble('mapZoom', mapZoom);
    }
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    _commit();
  }
}
