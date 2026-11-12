import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/pressable.dart';
import 'camera_design.dart';

enum CameraMode { video, photo }

class CameraControlBar extends StatelessWidget {
  static const height = 160.0;
  final CameraMode mode;
  final double iconTurns;
  final bool busy;

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
    final shutterLabel = video
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
        scale: .94,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cameraYellow,
                  ),
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: recording ? 28 : 62,
                  height: recording ? 28 : 62,
                  decoration: BoxDecoration(
                    color: action == null
                        ? Colors.white38
                        : (video ? const Color(0xFFFF453A) : Colors.white),
                    borderRadius: BorderRadius.circular(recording ? 7 : 31),
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
          : ClipOval(
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

class _ModePicker extends StatefulWidget {
  final CameraMode mode;
  final bool locked;
  final ValueChanged<CameraMode> onMode;
  const _ModePicker({
    required this.mode,
    required this.locked,
    required this.onMode,
  });

  @override
  State<_ModePicker> createState() => _ModePickerState();
}

class _ModePickerState extends State<_ModePicker> {
  double? _dragPosition;

  void _select(int index) {
    setState(() => _dragPosition = null);
    if (widget.locked || index == widget.mode.index) return;
    HapticFeedback.selectionClick();
    widget.onMode(CameraMode.values[index]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final slot = constraints.maxWidth / CameraMode.values.length;
      void follow(double x) =>
          setState(() => _dragPosition = (x / slot - .5).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.locked
            ? null
            : (d) => follow(d.localPosition.dx),
        onHorizontalDragUpdate: widget.locked
            ? null
            : (d) => follow(d.localPosition.dx),
        onHorizontalDragEnd: widget.locked
            ? null
            : (d) => _select(
                (_dragPosition ?? widget.mode.index.toDouble()).round(),
              ),
        onHorizontalDragCancel: () => setState(() => _dragPosition = null),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration:
                    _dragPosition != null ||
                        MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  2 * (_dragPosition ?? widget.mode.index.toDouble()) - 1,
                  0,
                ),
                child: Container(
                  width: slot,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF414141), Color(0xFF252525)],
                    ),
                    border: Border.all(color: const Color(0x55FFFFFF)),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in CameraMode.values)
                    Expanded(
                      child: Semantics(
                        label:
                            mode.name[0].toUpperCase() + mode.name.substring(1),
                        button: true,
                        selected: widget.mode == mode,
                        enabled: !widget.locked || widget.mode == mode,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.locked && widget.mode != mode
                              ? null
                              : () => _select(mode.index),
                          child: ExcludeSemantics(
                            child: SizedBox(
                              height: 52,
                              child: Center(
                                child: Text(
                                  mode.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: .4,
                                    color: widget.mode == mode
                                        ? cameraYellow
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
