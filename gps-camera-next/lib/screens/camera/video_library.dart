import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/capture_service.dart';
import 'widgets/camera_design.dart';

Future<void> showVideoLibrary(BuildContext context) async {
  final captures = CaptureService.instance;
  if (defaultTargetPlatform != TargetPlatform.android) {
    await captures.openGallery();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _VideoLibrary(captures),
  );
}

class _VideoLibrary extends StatefulWidget {
  const _VideoLibrary(this.captures);
  final CaptureService captures;

  @override
  State<_VideoLibrary> createState() => _VideoLibraryState();
}

class _VideoLibraryState extends State<_VideoLibrary> {
  late final _videos = widget.captures.listVideos();
  String? _playbackError;

  Future<void> _open(SavedVideo video) async {
    setState(() => _playbackError = null);
    try {
      await widget.captures.openVideo(video.id);
    } catch (_) {
      if (mounted) {
        setState(() => _playbackError = 'Could not open this video.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => CameraGlass(
    radius: 30,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          ListTile(
            title: const Text('Videos'),
            trailing: IconButton(
              tooltip: 'Close videos',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          if (_playbackError != null) Text(_playbackError!),
          Expanded(
            child: FutureBuilder<List<SavedVideo>>(
              future: _videos,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load saved videos.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final videos = snapshot.data!;
                if (videos.isEmpty) {
                  return const Center(child: Text('No saved videos yet.'));
                }
                final dateFormat = MaterialLocalizations.of(context);
                return ListView.builder(
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    final minutes = video.duration.inMinutes;
                    final seconds = (video.duration.inSeconds % 60)
                        .toString()
                        .padLeft(2, '0');
                    return ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(video.stamped ? 'Stamped video' : 'Video'),
                      subtitle: Text(
                        '${dateFormat.formatShortDate(video.added)} · '
                        '${dateFormat.formatTimeOfDay(TimeOfDay.fromDateTime(video.added))} · '
                        '$minutes:$seconds',
                      ),
                      onTap: () => _open(video),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
