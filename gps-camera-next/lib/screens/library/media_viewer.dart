import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/media_item.dart';
import '../../services/media_image.dart';
import '../../services/media_library.dart';
import '../../state/settings_controller.dart';
import '../../widgets/mini_map.dart';
import 'video_page.dart';

/// Opens the full-screen viewer and returns the key of the item it was left on.
Future<String?> openMediaViewer(
  BuildContext context,
  MediaLibrary library,
  MediaItem item,
) => Navigator.of(context).push<String>(
  PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => MediaViewer(library: library, initial: item),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.library, required this.initial});

  final MediaLibrary library;
  final MediaItem initial;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  static final _dateFormat = DateFormat('d MMMM yyyy');
  static final _timeFormat = DateFormat('HH:mm');

  late List<MediaItem> _items = widget.library.items;
  late String _currentKey = widget.initial.key;
  late int _index = _indexOf(_currentKey);
  late final _pages = PageController(initialPage: _index);
  final _videoPositions = <String, Duration>{};
  bool _controls = true;
  bool _zoomed = false;
  bool _muted = false;
  bool _busy = false;
  String? _showingOriginalOf;

  MediaItem? get _current => _items.isEmpty ? null : _items[_index];

  int _indexOf(String key) {
    final index = _items.indexWhere((item) => item.key == key);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onLibrary);
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    _pages.dispose();
    super.dispose();
  }

  /// Keeps the viewer on the same item when the Library changes underneath
  /// it, and moves to a neighbour when that item is deleted.
  void _onLibrary() {
    if (!mounted) return;
    final items = widget.library.items;
    if (items.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final found = items.indexWhere((item) => item.key == _currentKey);
    final index = found >= 0 ? found : _index.clamp(0, items.length - 1);
    setState(() {
      _items = items;
      _index = index;
      _currentKey = items[index].key;
      _zoomed = false;
    });
    if (_pages.hasClients && _pages.page?.round() != index) {
      _pages.jumpToPage(index);
    }
  }

  void _close() => Navigator.of(context).pop(_currentKey);

  Future<void> _delete() async {
    final item = _current;
    if (item == null || _busy) return;
    final noun = item.isVideo ? 'video' : 'photo';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $noun?'),
        content: Text('This $noun will be removed from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    var deleted = false;
    try {
      deleted = await widget.library.delete(item);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (!deleted) _say('Could not delete this $noun.');
  }

  Future<void> _share() async {
    final item = _current;
    if (item == null) return;
    try {
      await widget.library.gateway.share(item);
    } catch (_) {
      _say('Could not share this item.');
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _showDetails() async {
    final item = _current;
    if (item == null) return;
    var location = widget.library.locationOf(item);
    if (location == null) {
      try {
        location = await widget.library.gateway.location(item);
      } catch (_) {}
    }
    if (!mounted) return;
    final megabytes = item.sizeBytes / (1024 * 1024);
    final settings = SettingsController.instance;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_dateFormat.format(item.taken)} at ${_timeFormat.format(item.taken)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(item.name, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Text(
                [
                  if (item.width > 0 && item.height > 0)
                    '${item.width} × ${item.height}',
                  if (item.isVideo) formatMediaDuration(item.duration),
                  if (item.sizeBytes > 0) '${megabytes.toStringAsFixed(1)} MB',
                ].join('  ·  '),
              ),
              const SizedBox(height: 12),
              if (location == null)
                const Text(
                  'No location was saved with this item.',
                  style: TextStyle(color: Colors.white70),
                )
              else ...[
                if (location.place.isNotEmpty) Text(location.place),
                Text(
                  '${location.lat.toStringAsFixed(6)}, ${location.lon.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => showMapZoomPopup(
                      context,
                      lat: location!.lat,
                      lon: location.lon,
                      heading: 0,
                      kind: settings.mapKind,
                      initialZoom: settings.mapZoom,
                    ),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Show on map'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final item = _current;
    final original = item == null ? null : widget.library.originalOf(item);
    final showingOriginal = item != null && _showingOriginalOf == item.key;
    final place = item == null ? null : widget.library.locationOf(item)?.place;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              physics: _zoomed || _busy
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (index) => setState(() {
                _index = index;
                _currentKey = _items[index].key;
                _zoomed = false;
                _showingOriginalOf = null;
              }),
              itemBuilder: (context, index) {
                final page = _items[index];
                if (page.isVideo) {
                  return VideoPage(
                    key: ValueKey(page.key),
                    item: page,
                    active: index == _index,
                    controlsVisible: _controls,
                    muted: _muted,
                    resumeAt: _videoPositions[page.key] ?? Duration.zero,
                    onPosition: (position) =>
                        _videoPositions[page.key] = position,
                    onToggleControls: () =>
                        setState(() => _controls = !_controls),
                    onMuted: (muted) => setState(() => _muted = muted),
                    bottomInset: padding.bottom + 56,
                  );
                }
                return PhotoPage(
                  key: ValueKey(page.key),
                  item: index == _index && showingOriginal && original != null
                      ? original
                      : page,
                  heroTag: page.key == widget.initial.key ? page.key : null,
                  onTap: () => setState(() => _controls = !_controls),
                  onZoomChanged: (zoomed) {
                    if (index == _index && zoomed != _zoomed) {
                      setState(() => _zoomed = zoomed);
                    }
                  },
                );
              },
            ),
            _Chrome(
              visible: _controls,
              top: true,
              padding: EdgeInsets.fromLTRB(4, padding.top + 4, 4, 20),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to library',
                    onPressed: _close,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: item == null
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              Text(
                                showingOriginal
                                    ? 'Original'
                                    : _dateFormat.format(item.taken),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  _timeFormat.format(item.taken),
                                  if (place != null && place.isNotEmpty) place,
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                  ),
                  IconButton(
                    tooltip: 'Details',
                    onPressed: item == null ? null : _showDetails,
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                ],
              ),
            ),
            _Chrome(
              visible: _controls,
              top: false,
              padding: EdgeInsets.fromLTRB(4, 20, 4, padding.bottom + 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Share',
                    onPressed: item == null || _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  if (original != null)
                    IconButton(
                      tooltip: showingOriginal
                          ? 'Show stamped photo'
                          : 'Show original photo',
                      isSelected: showingOriginal,
                      onPressed: () => setState(
                        () => _showingOriginalOf = showingOriginal
                            ? null
                            : item!.key,
                      ),
                      selectedIcon: const Icon(Icons.compare_rounded),
                      icon: const Icon(Icons.compare_outlined),
                    ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: item == null || _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.top,
    required this.padding,
    required this.child,
  });

  final bool visible;
  final bool top;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    top: top ? 0 : null,
    bottom: top ? null : 0,
    child: IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Color(0xB3000000), Colors.transparent],
            ),
          ),
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    ),
  );
}

/// A zoomable photo. Panning only engages once zoomed, so a swipe at 1× always
/// belongs to the pager and a drag while zoomed always belongs to the photo.
class PhotoPage extends StatefulWidget {
  const PhotoPage({
    super.key,
    required this.item,
    required this.onTap,
    required this.onZoomChanged,
    this.heroTag,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  final String? heroTag;

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage>
    with SingleTickerProviderStateMixin {
  static const _doubleTapScale = 2.6;
  final _transform = TransformationController();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_onAnimate);
  Matrix4Tween? _tween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_reportZoom);
    _animation; // Create the ticker now. Dispose is too late to do it.
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _reportZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  void _onAnimate() {
    final tween = _tween;
    if (tween == null) return;
    _transform.value = tween.transform(
      Curves.easeOutCubic.transform(_animation.value),
    );
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _transform.value, end: target);
    _animation.forward(from: 0);
  }

  void _onDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.02) {
      _animateTo(Matrix4.identity());
      return;
    }
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(
          -_doubleTapAt.dx * (_doubleTapScale - 1),
          -_doubleTapAt.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Enough pixels to stay sharp when zoomed, without holding a full sensor
    // frame in memory.
    final longest = (media.size.longestSide * media.devicePixelRatio * 1.5)
        .round()
        .clamp(1024, 4096);
    Widget photo = Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: MediaThumbnail(widget.item, size: 512),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        Image(
          image: ResizeImage(
            MediaImage(widget.item),
            width: longest,
            height: longest,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const Center(
            child: Text(
              'This photo can’t be opened.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ],
    );
    if (widget.heroTag != null) {
      photo = Hero(tag: widget.heroTag!, child: photo);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        panEnabled: _zoomed,
        onInteractionStart: (_) => _animation.stop(),
        onInteractionEnd: (_) {
          if (_transform.value.getMaxScaleOnAxis() <= 1.02) {
            _animateTo(Matrix4.identity());
          }
        },
        child: photo,
      ),
    );
  }
}
