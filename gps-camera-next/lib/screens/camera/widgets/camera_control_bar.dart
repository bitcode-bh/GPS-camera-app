import 'package:flutter/material.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/design/tokens.dart';

import '../../../core/widgets/pressable.dart';
import 'camera_design.dart';

enum CameraMode { video, photo }

class CameraControlBar extends StatelessWidget {
  static const height = 160.0;
  final CameraMode mode;
  final double iconTurns;
  final bool busy;
  final bool animate;

  /// Thumbnail of the newest Library item, when there is one.
  final ImageProvider? lastShot;
  final bool recording;
  final bool lockCameraChanges;
  final ValueChanged<CameraMode> onMode;
  final VoidCallback? onShutter;
  final VoidCallback? onFlip;
  final VoidCallback? onGallery;
  final VoidCallback? onStamp;

  const CameraControlBar({
    super.key,
    required this.mode,
    this.iconTurns = 0,
    required this.busy,
    this.animate = true,
    required this.lastShot,
    required this.recording,
    this.lockCameraChanges = false,
    required this.onMode,
    required this.onShutter,
    required this.onFlip,
    required this.onGallery,
    this.onStamp,
  });

  @override
  Widget build(BuildContext context) {
    final video = mode == CameraMode.video;
    final action = busy ? null : onShutter;
    final shutterLabel = busy
        ? (video ? 'Processing video' : 'Capturing photo')
        : video
        ? (recording ? 'Stop recording' : 'Start recording')
        : 'Take photo';
    final stamp = CameraAction(
      label: 'GPS stamp settings',
      iconTurns: iconTurns,
      icon: Icons.apps_rounded,
      onTap: onStamp,
    );
    final shutter = Semantics(
      label: shutterLabel,
      button: true,
      enabled: action != null,
      child: Pressable(
        onTap: action,
        scale: 1,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: SizedBox.square(
            key: const ValueKey('camera-shutter-inner'),
            dimension: 62,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: busy || recording
                  ? SizedBox.expand(
                      child: CameraCaptureGrid(
                        recording: recording,
                        animate: animate,
                      ),
                    )
                  : DecoratedBox(
                      key: ValueKey(video),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: action == null
                            ? Colors.white38
                            : (video ? const Color(0xFFFF453A) : Colors.white),
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
          ),
        ),
      ),
    );
    final gallery = CameraAction(
      label: video ? 'Open video library' : 'Open gallery',
      iconTurns: lastShot == null ? iconTurns : 0,
      icon: video ? Icons.video_library_outlined : Icons.photo_library_outlined,
      onTap: onGallery,
      child: lastShot == null
          ? null
          : ClipRSuperellipse(
              borderRadius: BorderRadius.circular(Corners.md),
              child: Image(
                image: lastShot!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Icon(
                  video
                      ? Icons.video_library_outlined
                      : Icons.photo_library_outlined,
                ),
              ),
            ),
    );
    final flip = onFlip == null
        ? const SizedBox.square(dimension: 48)
        : CameraAction(
            label: 'Switch camera',
            iconTurns: iconTurns,
            icon: Icons.cameraswitch_outlined,
            onTap: lockCameraChanges ? null : onFlip,
          );
    final modes = _ModePicker(
      mode: mode,
      locked: lockCameraChanges,
      onMode: onMode,
    );
    return SizedBox(
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: 92,
            child: Row(
              children: [
                const Spacer(),
                shutter,
                Expanded(child: Center(child: stamp)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                gallery,
                const SizedBox(width: 10),
                Expanded(child: modes),
                const SizedBox(width: 10),
                flip,
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  final CameraMode mode;
  final bool locked;
  final ValueChanged<CameraMode> onMode;
  const _ModePicker({
    required this.mode,
    required this.locked,
    required this.onMode,
  });

  @override
  Widget build(BuildContext context) => GlassSegmented<CameraMode>(
    options: const [
      (value: CameraMode.video, label: 'Video'),
      (value: CameraMode.photo, label: 'Photo'),
    ],
    selected: mode,
    enabled: !locked,
    height: 54,
    onChanged: onMode,
  );
}
