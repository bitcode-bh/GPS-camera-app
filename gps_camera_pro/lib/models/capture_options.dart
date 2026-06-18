/// Photo aspect ratios offered in the camera (portrait orientation).
enum CaptureRatio { full, r4_3, r16_9, r1_1 }

extension CaptureRatioX on CaptureRatio {
  String get label => switch (this) {
        CaptureRatio.full => 'Full',
        CaptureRatio.r4_3 => '4:3',
        CaptureRatio.r16_9 => '16:9',
        CaptureRatio.r1_1 => '1:1',
      };

  /// width / height for the portrait viewfinder box. `null` means fill the
  /// available area (no letterboxing).
  double? get portraitWH => switch (this) {
        CaptureRatio.full => null,
        CaptureRatio.r4_3 => 3 / 4,
        CaptureRatio.r16_9 => 9 / 16,
        CaptureRatio.r1_1 => 1.0,
      };
}
