import 'package:camera/camera.dart';

/// A specific JPEG output size detected from the device's Camera2 hardware.
/// All instances are immutable; equality is by pixel count.
class CameraResolution {
  final int width;
  final int height;

  const CameraResolution(this.width, this.height);

  int get pixels => width * height;
  double get megapixels => pixels / 1_000_000.0;

  /// Short label shown in the camera toolbar, e.g. "50 MP".
  String get mpLabel {
    final mp = megapixels;
    if (mp >= 10) return '${mp.round()} MP';
    if (mp >= 1) return '${mp.toStringAsFixed(1)} MP';
    return '${(mp * 1000).round()} KP';
  }

  /// [ResolutionPreset] that best represents this resolution for CameraX.
  ResolutionPreset get preset {
    if (pixels >= 16_000_000) return ResolutionPreset.max;
    if (pixels >= 8_000_000) return ResolutionPreset.ultraHigh;
    if (pixels >= 3_500_000) return ResolutionPreset.veryHigh;
    if (pixels >= 900_000) return ResolutionPreset.high;
    return ResolutionPreset.medium;
  }

  /// pixelRatio to use when rasterising the stamp composite.
  /// Higher MP selection → higher ratio → sharper stamp text.
  double get stampPixelRatio {
    if (megapixels >= 24) return 4.0;
    if (megapixels >= 10) return 3.5;
    if (megapixels >= 4) return 3.0;
    if (megapixels >= 2) return 2.5;
    return 2.0;
  }

  @override
  bool operator ==(Object other) =>
      other is CameraResolution && other.pixels == pixels;

  @override
  int get hashCode => pixels.hashCode;

  @override
  String toString() => '$width×$height ($mpLabel)';
}
