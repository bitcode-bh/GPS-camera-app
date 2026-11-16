import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../services/capture_service.dart';
import '../../services/media_library.dart';
import '../../state/settings_controller.dart';
import '../../widgets/pinshutter_brand.dart';
import '../../core/widgets/controls.dart';
import '../../core/design/text_styles.dart';
import 'media_grid.dart';
import 'media_map.dart';
import '../../services/native_location.dart';
import 'media_viewer.dart';

/// Photos and videos captured by the app: a grid and a map of where the most
/// recent ones were taken.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.library});

  final MediaLibrary? library;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final MediaLibrary _library = widget.library ?? MediaLibrary.instance;
  final _grid = GlobalKey<MediaGridState>();
  bool _showMap = false;
  bool _mapBuilt = false; // The map and its tiles load on first use only.

  @override
  void initState() {
    super.initState();
    _library.refresh();
  }

  Future<void> _open(MediaItem item) async {
    final leftOn = await openMediaViewer(context, _library, item);
    if (!mounted || leftOn == null) return;
    final index = _library.items.indexWhere((other) => other.key == leftOn);
    if (index >= 0) _grid.currentState?.ensureVisible(index);
  }

  void _selectTab(bool map) => setState(() {
    _showMap = map;
    _mapBuilt = _mapBuilt || map;
  });

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final topPadding = padding.top + 64;
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            key: const ValueKey('library-bottom-navigation'),
            height: 56,
            child: Center(
              child: _Segments(map: _showMap, onChanged: _selectTab),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _library,
        builder: (context, _) => Stack(
          children: [
            IndexedStack(
              index: _showMap ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                _gridTab(topPadding, 8),
                if (_mapBuilt)
                  MediaMap(
                    library: _library,
                    onOpen: _open,
                    topPadding: topPadding,
                    bottomPadding: 8,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(4, padding.top + 4, 4, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back to camera',
                            color: Colors.white,
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          ),
                          const Expanded(
                            child: Center(
                              child: PinShutterWordmark(width: 156),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Open device gallery',
                            color: Colors.white,
                            onPressed: CaptureService.instance.openGallery,
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridTab(double topPadding, double bottomPadding) {
    switch (_library.status) {
      case LibraryStatus.idle || LibraryStatus.loading:
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      case LibraryStatus.permissionRestricted:
        return _Message(
          title: 'Storage access is off',
          detail: 'Allow storage access to see your photos and videos.',
          action: _library.permanentlyDenied ? 'Open Settings' : 'Allow',
          onAction: _library.permanentlyDenied
              ? NativeLocation.openAppSettings
              : _library.refresh,
        );
      case LibraryStatus.error:
        return _Message(
          title: 'Couldn’t load your library',
          action: 'Try again',
          onAction: _library.refresh,
        );
      case LibraryStatus.empty:
        return const _Message(
          title: 'No photos or videos yet',
          detail: 'Your captures appear here.',
        );
      case LibraryStatus.loaded || LibraryStatus.refreshing:
        final settings = SettingsController.instance;
        return MediaGrid(
          key: _grid,
          items: _library.items,
          onOpen: (index) => _open(_library.items[index]),
          initialColumns: settings.libraryColumns,
          onColumnsChanged: (columns) =>
              settings.update(() => settings.libraryColumns = columns),
          topPadding: topPadding,
          bottomPadding: bottomPadding + 8,
        );
    }
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.map, required this.onChanged});
  final bool map;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: GlassSegmented<bool>(
      options: const [
        (value: false, label: 'Library'),
        (value: true, label: 'Map'),
      ],
      selected: map,
      height: 56,
      onChanged: onChanged,
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.detail,
    this.action,
    this.onAction,
  });

  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: AppText.title),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}
