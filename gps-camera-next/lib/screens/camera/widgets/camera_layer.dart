import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';

/// Shows the live camera preview (cover-fitted, portrait-corrected). When no
/// camera is available (simulator / web / permission denied) it falls back to a
/// clean dark viewport with a loader.
///
class CameraLayer extends StatelessWidget {
  final CameraController? controller;
  const CameraLayer({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const FallbackScene();
    }
    final preview = c.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(c),
        ),
      ),
    );
  }
}

class FallbackScene extends StatelessWidget {
  const FallbackScene({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Palette.accentMuted),
          ),
        ),
      ),
    );
  }
}
