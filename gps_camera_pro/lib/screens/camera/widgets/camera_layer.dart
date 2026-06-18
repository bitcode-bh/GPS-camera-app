import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';

/// Shows the live camera preview (cover-fitted, portrait-corrected). When no
/// camera is available (simulator / web / permission denied) it falls back to a
/// clean dark viewport with a loader.
///
/// Two backends: the `camera` plugin ([controller]) for auto mode, or the
/// native Camera2 manual-sensor pipeline ([proTextureId]) for pro mode. When a
/// native texture id is supplied it takes precedence.
class CameraLayer extends StatelessWidget {
  final CameraController? controller;
  final int? proTextureId;
  final int proWidth;
  final int proHeight;
  const CameraLayer({
    super.key,
    this.controller,
    this.proTextureId,
    this.proWidth = 0,
    this.proHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Native manual-sensor preview (Camera2 → Flutter texture).
    if (proTextureId != null && proWidth > 0 && proHeight > 0) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            // Native buffer is landscape; swap for the portrait viewport.
            width: proHeight.toDouble(),
            height: proWidth.toDouble(),
            child: Texture(textureId: proTextureId!),
          ),
        ),
      );
    }

    final c = controller;
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const FallbackScene();
    }
    final preview = c.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height, // previewSize is landscape; swap for portrait
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
