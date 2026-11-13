import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/state/state_machine.dart';

void main() {
  group('camera', () {
    CameraMachine previewing() => CameraMachine()
      ..go(CameraPhase.initializing)
      ..go(CameraPhase.previewing);

    test('opens, shoots and returns to the preview', () {
      final camera = CameraMachine();
      expect(camera.hasPreview, isFalse);
      expect(camera.go(CameraPhase.initializing), isTrue);
      expect(camera.go(CameraPhase.previewing), isTrue);
      expect(camera.canReconfigure, isTrue);
      expect(camera.go(CameraPhase.countdown), isTrue);
      expect(camera.go(CameraPhase.capturing), isTrue);
      expect(camera.canReconfigure, isFalse);
      expect(camera.hasPreview, isTrue);
      expect(camera.go(CameraPhase.previewing), isTrue);
    });

    test('cannot be ready before initialization finishes', () {
      final camera = CameraMachine();
      expect(camera.go(CameraPhase.previewing), isFalse);
      expect(camera.go(CameraPhase.capturing), isFalse);
      expect(camera.go(CameraPhase.recording), isFalse);
      expect(camera.state, CameraPhase.uninitialized);
      camera.go(CameraPhase.initializing);
      expect(camera.hasPreview, isFalse);
      expect(camera.go(CameraPhase.capturing), isFalse);
    });

    test('a recording must be stopped before the camera is released', () {
      final camera = previewing()
        ..go(CameraPhase.startingRecording)
        ..go(CameraPhase.recording);
      expect(camera.isRecording, isTrue);
      expect(camera.go(CameraPhase.suspended), isFalse);
      expect(camera.go(CameraPhase.switching), isFalse);
      expect(camera.go(CameraPhase.capturing), isFalse);
      expect(camera.state, CameraPhase.recording);
      expect(camera.go(CameraPhase.stoppingRecording), isTrue);
      expect(camera.isRecording, isFalse);
      expect(camera.recordingBusy, isTrue);
      expect(camera.go(CameraPhase.suspended), isTrue);
    });

    test('a failed start leaves no recording behind', () {
      final camera = previewing()..go(CameraPhase.startingRecording);
      expect(camera.go(CameraPhase.previewing), isTrue);
      expect(camera.isRecording, isFalse);
      expect(camera.recordingBusy, isFalse);
    });

    test('capture and recording exclude each other', () {
      final capturing = previewing()..go(CameraPhase.capturing);
      expect(capturing.go(CameraPhase.startingRecording), isFalse);
      expect(capturing.go(CameraPhase.switching), isFalse);
      final recording = previewing()..go(CameraPhase.startingRecording);
      expect(recording.go(CameraPhase.capturing), isFalse);
      expect(recording.go(CameraPhase.countdown), isFalse);
    });

    test('repeated events are harmless', () {
      final camera = previewing();
      for (var i = 0; i < 5; i++) {
        expect(camera.go(CameraPhase.switching), i == 0 ? isTrue : isTrue);
      }
      expect(camera.state, CameraPhase.switching);
      // A second lens switch cannot start until the first has reopened.
      expect(camera.canReconfigure, isFalse);
      expect(camera.go(CameraPhase.previewing), isFalse);
    });

    test('suspends from any idle or busy phase and recovers', () {
      for (final from in [
        CameraPhase.previewing,
        CameraPhase.countdown,
        CameraPhase.capturing,
        CameraPhase.switching,
      ]) {
        final camera = previewing();
        if (from != CameraPhase.previewing) camera.go(from);
        expect(camera.go(CameraPhase.suspended), isTrue, reason: '$from');
        expect(camera.hasPreview, isFalse);
        expect(camera.go(CameraPhase.previewing), isFalse);
        expect(camera.go(CameraPhase.initializing), isTrue);
        expect(camera.go(CameraPhase.previewing), isTrue);
      }
    });

    test('recovers from an error by reinitializing', () {
      final camera = CameraMachine()
        ..go(CameraPhase.initializing)
        ..go(CameraPhase.error);
      expect(camera.go(CameraPhase.previewing), isFalse);
      expect(camera.go(CameraPhase.initializing), isTrue);
    });

    test('released is final', () {
      final camera = previewing()..go(CameraPhase.released);
      for (final phase in CameraPhase.values) {
        if (phase == CameraPhase.released) continue;
        expect(camera.go(phase), isFalse, reason: '$phase');
      }
      expect(camera.state, CameraPhase.released);
    });

    test('notifies only on a real change', () {
      final camera = CameraMachine();
      var changes = 0;
      camera.addListener(() => changes++);
      camera.go(CameraPhase.initializing);
      camera.go(CameraPhase.initializing);
      camera.go(CameraPhase.recording); // Refused.
      expect(changes, 1);
    });
  });

  group('playback', () {
    PlaybackMachine ready() => PlaybackMachine()
      ..go(PlaybackPhase.preparing)
      ..go(PlaybackPhase.ready);

    void report(
      PlaybackMachine player, {
      bool error = false,
      bool playing = false,
      bool buffering = false,
      bool completed = false,
    }) => player.report(
      hasError: error,
      playing: playing,
      buffering: buffering,
      completed: completed,
    );

    test('prepares, plays, pauses, buffers and completes', () {
      final player = PlaybackMachine();
      expect(player.canControl, isFalse);
      expect(player.go(PlaybackPhase.playing), isFalse);
      player.go(PlaybackPhase.preparing);
      expect(player.canControl, isFalse);
      player.go(PlaybackPhase.ready);
      expect(player.canControl, isTrue);
      report(player);
      expect(player.state, PlaybackPhase.ready);
      report(player, playing: true);
      expect(player.state, PlaybackPhase.playing);
      report(player, playing: true, buffering: true);
      expect(player.state, PlaybackPhase.buffering);
      report(player);
      expect(player.state, PlaybackPhase.paused);
      report(player, completed: true);
      expect(player.state, PlaybackPhase.completed);
      report(player, playing: true);
      expect(player.state, PlaybackPhase.playing);
    });

    test('a released player is never reported as playing', () {
      final player = ready()..go(PlaybackPhase.released);
      report(player, playing: true);
      expect(player.state, PlaybackPhase.released);
      expect(player.canControl, isFalse);
      expect(player.go(PlaybackPhase.preparing), isFalse);
    });

    test('values that arrive before the player is ready are ignored', () {
      final player = PlaybackMachine()..go(PlaybackPhase.preparing);
      report(player, playing: true);
      expect(player.state, PlaybackPhase.preparing);
    });

    test('an error can only be left by preparing again or releasing', () {
      final player = ready();
      report(player, error: true);
      expect(player.state, PlaybackPhase.error);
      expect(player.canControl, isFalse);
      report(player, playing: true);
      expect(player.state, PlaybackPhase.error);
      expect(player.go(PlaybackPhase.preparing), isTrue);
    });

    test('a failed preparation ends in error, not ready', () {
      final player = PlaybackMachine()..go(PlaybackPhase.preparing);
      expect(player.go(PlaybackPhase.error), isTrue);
      expect(player.go(PlaybackPhase.playing), isFalse);
    });
  });
}
