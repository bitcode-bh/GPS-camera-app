import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/media_item.dart';
import '../../services/media_image.dart';
import '../../state/state_machine.dart';

/// One video in the viewer. Only the active page owns a player, so the app
/// holds at most one decoder however many videos the Library contains.
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.item,
    required this.active,
    required this.controlsVisible,
    required this.muted,
    required this.resumeAt,
    required this.onPosition,
    required this.onToggleControls,
    required this.onMuted,
    this.bottomInset = 0,
  });

  final MediaItem item;
  final bool active;
  final bool controlsVisible;
  final bool muted;
  final Duration resumeAt;
  final ValueChanged<Duration> onPosition;
  final VoidCallback onToggleControls;
  final ValueChanged<bool> onMuted;
  final double bottomInset;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  // Replaced after each release: a released machine never plays again.
  var _machine = PlaybackMachine();
  VideoPlayerController? _player;
  double? _scrubbing; // Milliseconds while the user drags the bar.
  bool _resumeAfterScrub = false;

  PlaybackPhase get _phase => _machine.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _machine.addListener(_onPhase);
    if (widget.active) _open();
  }

  @override
  void didUpdateWidget(VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active || widget.item.key != old.item.key) {
      _close();
      if (widget.active) _open();
    } else if (widget.muted != old.muted) {
      _player?.setVolume(widget.muted ? 0 : 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep playing, or holding audio focus, behind another app.
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _machine.removeListener(_onPhase);
    _release();
    _machine
      ..go(PlaybackPhase.released)
      ..dispose();
    super.dispose();
  }

  void _onPhase() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (!_machine.go(PlaybackPhase.preparing)) return;
    final player = VideoPlayerController.contentUri(widget.item.uri);
    _player = player;
    try {
      await player.initialize();
      // The page may have been swiped away, or reopened, while preparing.
      if (!mounted || !identical(player, _player)) return;
      await player.setVolume(widget.muted ? 0 : 1);
      final resumeAt = widget.resumeAt;
      if (resumeAt > Duration.zero &&
          resumeAt < player.value.duration - const Duration(seconds: 1)) {
        await player.seekTo(resumeAt);
      }
      if (!mounted || !identical(player, _player)) return;
      player.addListener(_onPlayerValue);
      _machine.go(PlaybackPhase.ready);
      await player.play();
    } catch (_) {
      if (mounted && identical(player, _player)) {
        _machine.go(PlaybackPhase.error);
      }
    }
  }

  void _onPlayerValue() {
    final value = _player?.value;
    if (value == null) return;
    _machine.report(
      hasError: value.hasError,
      playing: value.isPlaying,
      buffering: value.isBuffering,
      completed: value.isCompleted,
    );
  }

  /// Leaves the page: remember the position and free the decoder.
  void _close() {
    _release();
    _machine
      ..removeListener(_onPhase)
      ..go(PlaybackPhase.released)
      ..dispose();
    _machine = PlaybackMachine()..addListener(_onPhase);
  }

  void _release() {
    final player = _player;
    if (player == null) return;
    _player = null;
    player.removeListener(_onPlayerValue);
    if (player.value.isInitialized) {
      widget.onPosition(
        player.value.isCompleted ? Duration.zero : player.value.position,
      );
    }
    unawaited(player.dispose());
  }

  void _pause() {
    if (_machine.canControl) _player?.pause();
  }

  void _togglePlay() {
    final player = _player;
    if (player == null || !_machine.canControl) return;
    if (player.value.isPlaying) {
      player.pause();
    } else {
      if (player.value.isCompleted) player.seekTo(Duration.zero);
      player.play();
    }
  }

  void _retry() {
    _release();
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final showVideo = player != null && _machine.canControl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The poster stays until the first frame, so there is no black flash.
          Image(
            image: MediaThumbnail(widget.item, size: 512),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          if (showVideo)
            Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
          if (_phase == PlaybackPhase.preparing ||
              _phase == PlaybackPhase.buffering)
            const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          if (_phase == PlaybackPhase.error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This video can’t be played.',
                    style: TextStyle(color: Colors.white),
                  ),
                  TextButton(onPressed: _retry, child: const Text('Try again')),
                ],
              ),
            ),
          if (!widget.active)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 64,
                color: Colors.white70,
              ),
            ),
          if (showVideo)
            AnimatedOpacity(
              opacity: widget.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: IgnorePointer(
                ignoring: !widget.controlsVisible,
                child: _controls(player),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls(VideoPlayerController player) => Stack(
    children: [
      Center(
        child: IconButton(
          iconSize: 56,
          color: Colors.white,
          style: IconButton.styleFrom(backgroundColor: Colors.black38),
          tooltip: _phase == PlaybackPhase.playing ? 'Pause' : 'Play',
          onPressed: _togglePlay,
          icon: Icon(switch (_phase) {
            PlaybackPhase.playing ||
            PlaybackPhase.buffering => Icons.pause_rounded,
            PlaybackPhase.completed => Icons.replay_rounded,
            _ => Icons.play_arrow_rounded,
          }),
        ),
      ),
      Positioned(
        left: 12,
        right: 4,
        bottom: widget.bottomInset,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: player,
          builder: (context, value, _) {
            final total = value.duration.inMilliseconds.toDouble();
            final position =
                (_scrubbing ?? value.position.inMilliseconds.toDouble()).clamp(
                  0.0,
                  total <= 0 ? 0.0 : total,
                );
            String time(double ms) =>
                formatMediaDuration(Duration(milliseconds: ms.round()));
            const style = TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            );
            return Row(
              children: [
                Text(time(position), style: style),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Semantics(
                      label: 'Playback position',
                      child: Slider(
                        max: total <= 0 ? 1 : total,
                        value: position,
                        onChangeStart: (v) {
                          _resumeAfterScrub = value.isPlaying;
                          player.pause();
                          setState(() => _scrubbing = v);
                        },
                        onChanged: (v) => setState(() => _scrubbing = v),
                        onChangeEnd: (v) async {
                          await player.seekTo(
                            Duration(milliseconds: v.round()),
                          );
                          if (!mounted || !identical(player, _player)) return;
                          setState(() => _scrubbing = null);
                          if (_resumeAfterScrub) await player.play();
                        },
                      ),
                    ),
                  ),
                ),
                Text(time(total), style: style),
                IconButton(
                  tooltip: widget.muted ? 'Unmute' : 'Mute',
                  color: Colors.white,
                  onPressed: () => widget.onMuted(!widget.muted),
                  icon: Icon(
                    widget.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
