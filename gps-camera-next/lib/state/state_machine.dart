import 'package:flutter/foundation.dart';

/// A state plus the table of moves it may make. Anything else is refused, so
/// a late callback cannot push a component into a state it must not reach.
class StateMachine<S extends Enum> extends ChangeNotifier {
  StateMachine(this._state, this._table);

  S _state;
  final Map<S, Set<S>> _table;

  S get state => _state;

  bool can(S next) => _table[_state]?.contains(next) ?? false;

  /// Moves to [next] when the table allows it. Returns whether it moved.
  bool go(S next) {
    if (next == _state) return true;
    if (!can(next)) {
      assert(() {
        debugPrint('Refused transition $_state -> $next');
        return true;
      }());
      return false;
    }
    _state = next;
    notifyListeners();
    return true;
  }
}

/// What the camera hardware session is doing. One value replaces the separate
/// initializing, flipping, busy, countdown, recording and paused flags, which
/// could previously disagree with each other.
enum CameraPhase {
  uninitialized,
  initializing,
  previewing,
  countdown,
  capturing,
  startingRecording,
  recording,
  stoppingRecording,
  switching,
  suspended,
  error,
  released,
}

class CameraMachine extends StateMachine<CameraPhase> {
  CameraMachine() : super(CameraPhase.uninitialized, _moves);

  static const _moves = <CameraPhase, Set<CameraPhase>>{
    CameraPhase.uninitialized: {
      CameraPhase.initializing,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.initializing: {
      CameraPhase.previewing,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.previewing: {
      CameraPhase.countdown,
      CameraPhase.capturing,
      CameraPhase.startingRecording,
      CameraPhase.switching,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.countdown: {
      CameraPhase.capturing,
      CameraPhase.previewing,
      CameraPhase.suspended,
      CameraPhase.released,
    },
    CameraPhase.capturing: {
      CameraPhase.previewing,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.startingRecording: {
      CameraPhase.recording,
      CameraPhase.previewing,
      CameraPhase.stoppingRecording,
      CameraPhase.suspended,
      CameraPhase.released,
    },
    CameraPhase.recording: {
      CameraPhase.stoppingRecording,
      CameraPhase.released,
    },
    CameraPhase.stoppingRecording: {
      CameraPhase.previewing,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.switching: {
      CameraPhase.initializing,
      CameraPhase.suspended,
      CameraPhase.error,
      CameraPhase.released,
    },
    CameraPhase.suspended: {
      CameraPhase.initializing,
      CameraPhase.uninitialized,
      CameraPhase.released,
    },
    CameraPhase.error: {
      CameraPhase.initializing,
      CameraPhase.suspended,
      CameraPhase.released,
    },
    CameraPhase.released: {},
  };

  /// A live preview the user can frame with.
  bool get hasPreview => switch (state) {
    CameraPhase.previewing ||
    CameraPhase.countdown ||
    CameraPhase.capturing ||
    CameraPhase.startingRecording ||
    CameraPhase.recording ||
    CameraPhase.stoppingRecording => true,
    _ => false,
  };

  bool get isRecording => state == CameraPhase.recording;

  /// Starting, running or finishing a recording.
  bool get recordingBusy => switch (state) {
    CameraPhase.startingRecording ||
    CameraPhase.recording ||
    CameraPhase.stoppingRecording => true,
    _ => false,
  };

  /// Lens, mode and ratio may only change from an idle preview.
  bool get canReconfigure => state == CameraPhase.previewing;
}

/// Library video playback. Mirrors the player, and refuses anything after
/// release so a disposed player is never reported as playing.
enum PlaybackPhase {
  idle,
  preparing,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
  released,
}

class PlaybackMachine extends StateMachine<PlaybackPhase> {
  PlaybackMachine() : super(PlaybackPhase.idle, _moves);

  static const _active = {
    PlaybackPhase.playing,
    PlaybackPhase.paused,
    PlaybackPhase.buffering,
    PlaybackPhase.completed,
    PlaybackPhase.error,
    PlaybackPhase.released,
  };

  static const _moves = <PlaybackPhase, Set<PlaybackPhase>>{
    PlaybackPhase.idle: {PlaybackPhase.preparing, PlaybackPhase.released},
    PlaybackPhase.preparing: {
      PlaybackPhase.ready,
      PlaybackPhase.error,
      PlaybackPhase.released,
    },
    PlaybackPhase.ready: _active,
    PlaybackPhase.playing: _active,
    PlaybackPhase.paused: _active,
    PlaybackPhase.buffering: _active,
    PlaybackPhase.completed: {
      PlaybackPhase.playing,
      PlaybackPhase.paused,
      PlaybackPhase.buffering,
      PlaybackPhase.error,
      PlaybackPhase.released,
    },
    PlaybackPhase.error: {PlaybackPhase.preparing, PlaybackPhase.released},
    PlaybackPhase.released: {},
  };

  /// Play, pause and seek only make sense with a prepared player.
  bool get canControl => switch (state) {
    PlaybackPhase.ready ||
    PlaybackPhase.playing ||
    PlaybackPhase.paused ||
    PlaybackPhase.buffering ||
    PlaybackPhase.completed => true,
    _ => false,
  };

  /// Folds the player's reported values into a phase.
  void report({
    required bool hasError,
    required bool playing,
    required bool buffering,
    required bool completed,
  }) {
    if (!canControl) return;
    go(
      hasError
          ? PlaybackPhase.error
          : completed
          ? PlaybackPhase.completed
          : buffering && playing
          ? PlaybackPhase.buffering
          : playing
          ? PlaybackPhase.playing
          : state == PlaybackPhase.ready
          ? PlaybackPhase.ready
          : PlaybackPhase.paused,
    );
  }
}
