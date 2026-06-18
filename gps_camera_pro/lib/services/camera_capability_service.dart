import 'package:flutter/services.dart';

import '../models/camera_resolution.dart';

enum DetectedLensType { ultraWide, main, telephoto, periscope, front, external, unknown }

extension DetectedLensTypeX on DetectedLensType {
  String get label => switch (this) {
        DetectedLensType.ultraWide => 'Ultra-wide',
        DetectedLensType.main => 'Main',
        DetectedLensType.telephoto => 'Telephoto',
        DetectedLensType.periscope => 'Periscope',
        DetectedLensType.front => 'Front',
        DetectedLensType.external => 'External',
        DetectedLensType.unknown => 'Camera',
      };
}

class LensOption {
  final String id;
  final DetectedLensType type;
  final double focalLength;
  final double zoom;

  const LensOption({
    required this.id,
    required this.type,
    required this.focalLength,
    required this.zoom,
  });

  String get label {
    final z = zoom < 1 ? zoom.toStringAsFixed(1) : zoom.toStringAsFixed(zoom % 1 == 0 ? 0 : 1);
    return '${z}x';
  }
}

class CameraInfo {
  final String id;
  final String facing;
  final List<double> focalLengths;
  final double? aperture;
  final int? sensorOrientation;
  final List<String> physicalIds;

  const CameraInfo({
    required this.id,
    required this.facing,
    this.focalLengths = const [],
    this.aperture,
    this.sensorOrientation,
    this.physicalIds = const [],
  });
}

/// Queries Android Camera2 APIs (via platform channel) to discover the back
/// camera's true hardware capabilities. Results are cached after the first
/// successful detection and never change at runtime.
class CameraCapabilityService {
  CameraCapabilityService._();
  static final CameraCapabilityService instance = CameraCapabilityService._();

  static const _channel = MethodChannel('com.gpscamera.gps_camera_pro/gallery');

  // Sensible fallback before detection runs (covers any device).
  static const List<CameraResolution> _fallback = [
    CameraResolution(4096, 3072), // ~12 MP
    CameraResolution(2048, 1536), // ~3 MP
    CameraResolution(1920, 1080), // ~2 MP
  ];

  List<CameraResolution> _resolutions = _fallback;
  bool _detected = false;
  bool _hasFlash = true;
  bool _hasOis = false;
  bool _hasEis = false;
  bool _hasHdr = false;
  bool _hasNight = false;
  bool _supportsRaw = false;
  bool _manualFocus = false;
  bool _manualSensor = false;
  bool _kelvinWhiteBalance = false;
  bool _macro = false;
  double _maxDigitalZoom = 8.0;
  double? _minFocusDistance;
  int? _minIso;
  int? _maxIso;
  int? _minExposureNs;
  int? _maxExposureNs;
  double? _minEv;
  double? _maxEv;
  double? _evStep;
  List<int> _whiteBalanceModes = const [];
  List<String> _fpsRanges = const [];
  List<LensOption> _lensOptions = const [LensOption(id: 'fallback', type: DetectedLensType.main, focalLength: 1, zoom: 1)];
  List<CameraInfo> _cameras = const [];
  List<String> _physicalCameraIds = const [];

  List<CameraResolution> get resolutions => _resolutions;
  bool get isDetected => _detected;
  bool get hasFlash => _hasFlash;
  bool get hasOis => _hasOis;
  bool get hasEis => _hasEis;
  bool get hasHdr => _hasHdr;
  bool get hasNight => _hasNight;
  bool get supportsRaw => _supportsRaw;
  bool get manualFocus => _manualFocus;
  bool get manualSensor => _manualSensor;
  bool get kelvinWhiteBalance => _kelvinWhiteBalance;
  bool get hasMacro => _macro;
  double get maxDigitalZoom => _maxDigitalZoom;
  double? get minFocusDistance => _minFocusDistance;
  int? get minIso => _minIso;
  int? get maxIso => _maxIso;
  int? get minExposureNs => _minExposureNs;
  int? get maxExposureNs => _maxExposureNs;
  double? get minEv => _minEv;
  double? get maxEv => _maxEv;
  double? get evStep => _evStep;
  List<int> get whiteBalanceModes => _whiteBalanceModes;
  List<String> get fpsRanges => _fpsRanges;
  List<LensOption> get lensOptions => _lensOptions;
  List<CameraInfo> get cameras => _cameras;
  List<String> get physicalCameraIds => _physicalCameraIds;

  /// Run once from the camera screen's [initState]. Safe to call multiple times;
  /// subsequent calls are no-ops after the first successful detection.
  Future<void> detect() async {
    if (_detected) return;
    try {
      final raw = await _channel.invokeMethod<Map>('detectCapabilities');
      if (raw == null) return;

      // Parse resolution list and deduplicate into distinct MP tiers.
      final rawSizes = (raw['resolutions'] as List?)?.cast<Map>() ?? [];
      final all = rawSizes
          .map((m) => CameraResolution(m['w'] as int, m['h'] as int))
          .where((r) => r.pixels >= 307_200) // skip anything below VGA
          .toList()
        ..sort((a, b) => b.pixels.compareTo(a.pixels));

      // Keep one representative per tier: include a resolution only when it's
      // at most 75% of the previous one (otherwise they're effectively the same).
      final tiers = <CameraResolution>[];
      for (final r in all) {
        if (tiers.isEmpty || r.megapixels / tiers.last.megapixels <= 0.75) {
          tiers.add(r);
        }
      }
      if (tiers.isNotEmpty) _resolutions = tiers;

      _hasFlash = raw['hasFlash'] as bool? ?? true;
      _hasOis = raw['hasOis'] as bool? ?? false;
      _hasEis = raw['hasEis'] as bool? ?? false;
      _hasHdr = raw['hasHdr'] as bool? ?? false;
      _hasNight = raw['hasNight'] as bool? ?? false;
      _supportsRaw = raw['supportsRaw'] as bool? ?? false;
      _manualFocus = raw['manualFocus'] as bool? ?? false;
      _manualSensor = raw['manualSensor'] as bool? ?? false;
      _kelvinWhiteBalance = raw['kelvinWhiteBalance'] as bool? ?? false;
      _macro = raw['hasMacro'] as bool? ?? false;
      _maxDigitalZoom =
          (raw['maxDigitalZoom'] as num?)?.toDouble() ?? 8.0;
      _minFocusDistance = (raw['minFocusDistance'] as num?)?.toDouble();
      final isoRange = raw['isoRange'] as Map?;
      _minIso = isoRange?['min'] as int?;
      _maxIso = isoRange?['max'] as int?;
      final exposureRange = raw['exposureTimeRange'] as Map?;
      _minExposureNs = exposureRange?['min'] as int?;
      _maxExposureNs = exposureRange?['max'] as int?;
      final evRange = raw['exposureCompensationRange'] as Map?;
      _minEv = (evRange?['min'] as num?)?.toDouble();
      _maxEv = (evRange?['max'] as num?)?.toDouble();
      _evStep = (evRange?['step'] as num?)?.toDouble();
      _whiteBalanceModes =
          ((raw['whiteBalanceModes'] as List?) ?? const []).whereType<int>().toList();
      _fpsRanges =
          ((raw['fpsRanges'] as List?) ?? const []).map((e) => '$e').toList();
      _physicalCameraIds =
          ((raw['physicalCameraIds'] as List?) ?? const []).map((e) => '$e').toList();
      _lensOptions = _parseLensOptions(raw['lensOptions'] as List?);
      _cameras = _parseCameras(raw['cameras'] as List?);
      _detected = true;
    } catch (_) {
      // Detection failed — fallback list stays active.
    }
  }

  List<int> isoValues() {
    final min = _minIso;
    final max = _maxIso;
    if (min == null || max == null || min >= max) return const [];
    const base = [25, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800];
    final values = base.where((v) => v >= min && v <= max).toList();
    if (!values.contains(min)) values.insert(0, min);
    if (!values.contains(max)) values.add(max);
    return values.toSet().toList()..sort();
  }

  List<int> shutterSpeedsNs() {
    final min = _minExposureNs;
    final max = _maxExposureNs;
    if (min == null || max == null || min >= max) return const [];
    const base = [
      125000, // 1/8000
      250000,
      500000,
      1000000,
      2000000,
      4000000,
      8000000,
      16666666,
      33333333,
      66666666,
      125000000,
      250000000,
      500000000,
      1000000000,
      2000000000,
      5000000000,
      10000000000,
      30000000000,
    ];
    final values = base.where((v) => v >= min && v <= max).toList();
    if (!values.contains(min)) values.insert(0, min);
    if (!values.contains(max)) values.add(max);
    return values.toSet().toList()..sort();
  }

  List<LensOption> _parseLensOptions(List? raw) {
    final items = <LensOption>[];
    for (final item in raw ?? const []) {
      if (item is! Map) continue;
      final focal = (item['focalLength'] as num?)?.toDouble();
      final zoom = (item['zoom'] as num?)?.toDouble();
      if (focal == null || zoom == null) continue;
      items.add(LensOption(
        id: '${item['id'] ?? focal}',
        focalLength: focal,
        zoom: zoom,
        type: _lensType('${item['type'] ?? 'unknown'}'),
      ));
    }
    if (items.isEmpty) return const [LensOption(id: 'fallback', type: DetectedLensType.main, focalLength: 1, zoom: 1)];
    items.sort((a, b) => a.zoom.compareTo(b.zoom));
    return items;
  }

  List<CameraInfo> _parseCameras(List? raw) {
    return [
      for (final item in raw ?? const [])
        if (item is Map)
          CameraInfo(
            id: '${item['id']}',
            facing: '${item['facing'] ?? 'unknown'}',
            focalLengths: ((item['focalLengths'] as List?) ?? const [])
                .whereType<num>()
                .map((e) => e.toDouble())
                .toList(),
            aperture: (item['aperture'] as num?)?.toDouble(),
            sensorOrientation: item['sensorOrientation'] as int?,
            physicalIds: ((item['physicalIds'] as List?) ?? const []).map((e) => '$e').toList(),
          ),
    ];
  }

  DetectedLensType _lensType(String value) => switch (value) {
        'ultraWide' => DetectedLensType.ultraWide,
        'main' => DetectedLensType.main,
        'telephoto' => DetectedLensType.telephoto,
        'periscope' => DetectedLensType.periscope,
        'front' => DetectedLensType.front,
        'external' => DetectedLensType.external,
        _ => DetectedLensType.unknown,
      };

  /// The highest-MP (default) resolution.
  CameraResolution get defaultResolution => _resolutions.first;

  /// Resolution at [index], clamped so it's always valid.
  CameraResolution resolutionAt(int index) {
    if (_resolutions.isEmpty) return _fallback.first;
    return _resolutions[index.clamp(0, _resolutions.length - 1)];
  }
}
