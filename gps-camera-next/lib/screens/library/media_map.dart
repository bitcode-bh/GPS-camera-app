import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/map_kind.dart';
import '../../models/media_item.dart';
import '../../services/media_image.dart';
import '../../services/media_library.dart';
import '../../state/settings_controller.dart';
import '../camera/widgets/camera_design.dart';

/// What the map is showing. A selected marker always has its preview open,
/// so those are one state here.
enum MapPhase {
  uninitialized,
  loadingMedia,
  ready,
  markerSelected,
  empty,
  error,
}

/// Media captured close enough together to share one marker at this zoom.
class MarkerGroup {
  MarkerGroup(this.at, this.items);

  final MediaLocation at;
  final List<MediaItem> items;

  String get id => items.first.key;
}

/// Groups items whose markers would overlap on screen. Every item stays
/// reachable through its group, including items with identical coordinates.
List<MarkerGroup> groupMarkers(
  List<MediaItem> items,
  MediaLocation? Function(MediaItem) locate,
  double zoom, {
  double radius = 26,
}) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  Offset project(MediaLocation at) {
    final sin = math.sin(at.lat.clamp(-85.0, 85.0) * math.pi / 180);
    return Offset(
      (at.lon + 180) / 360 * scale,
      (.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale,
    );
  }

  final groups = <MarkerGroup>[];
  final centers = <Offset>[];
  for (final item in items) {
    final at = locate(item);
    if (at == null) continue;
    final point = project(at);
    final index = centers.indexWhere((c) => (c - point).distance <= radius);
    if (index >= 0) {
      groups[index].items.add(item);
    } else {
      groups.add(MarkerGroup(at, [item]));
      centers.add(point);
    }
  }
  return groups;
}

/// Drops deleted media from a selection. Null when nothing selected survives.
List<String>? reconcileSelection(List<String>? selected, Set<String> live) {
  if (selected == null) return null;
  final kept = [
    for (final key in selected)
      if (live.contains(key)) key,
  ];
  return kept.isEmpty ? null : kept;
}

MapPhase mapPhase(LibraryStatus status, int markers, bool hasSelection) =>
    switch (status) {
      LibraryStatus.idle => MapPhase.uninitialized,
      LibraryStatus.loading => MapPhase.loadingMedia,
      LibraryStatus.error => MapPhase.error,
      LibraryStatus.permissionRestricted ||
      LibraryStatus.empty => MapPhase.empty,
      LibraryStatus.loaded || LibraryStatus.refreshing =>
        markers == 0
            ? MapPhase.empty
            : hasSelection
            ? MapPhase.markerSelected
            : MapPhase.ready,
    };

class MediaMap extends StatefulWidget {
  const MediaMap({
    super.key,
    required this.library,
    required this.onOpen,
    this.topPadding = 0,
    this.bottomPadding = 0,
  });

  final MediaLibrary library;
  final ValueChanged<MediaItem> onOpen;
  final double topPadding;
  final double bottomPadding;

  @override
  State<MediaMap> createState() => _MediaMapState();
}

class _MediaMapState extends State<MediaMap> {
  final _map = MapController();
  final _previewPages = PageController();
  List<String>? _selected; // Keys of the selected marker's items.
  double _zoom = 3;
  bool _mapReady = false;
  bool _tilesFailed = false;
  int _tileEpoch = 0;

  MediaLibrary get _library => widget.library;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibrary);
  }

  @override
  void dispose() {
    _library.removeListener(_onLibrary);
    _previewPages.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onLibrary() {
    if (!mounted) return;
    setState(() {
      // A marker whose media was deleted must not stay selected.
      _selected = reconcileSelection(_selected, {
        for (final item in _library.mapItems) item.key,
      });
      if (_library.mapItems.isEmpty) _mapReady = false;
    });
  }

  List<LatLng> get _points => [
    for (final item in _library.mapItems)
      if (_library.locationOf(item) case final at?) LatLng(at.lat, at.lon),
  ];

  /// Frames every marker, upright, with room for the chrome around it.
  void _fit() {
    final points = _points;
    if (points.isEmpty || !_mapReady) return;
    _map.rotate(0);
    final bounds = LatLngBounds.fromPoints(points);
    if (bounds.southWest == bounds.northEast) {
      _map.move(points.first, 15);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          maxZoom: 16,
          padding: EdgeInsets.fromLTRB(
            48,
            widget.topPadding + 48,
            48,
            widget.bottomPadding + 120,
          ),
        ),
      );
    }
  }

  void _select(MarkerGroup group) {
    setState(() => _selected = [for (final item in group.items) item.key]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_previewPages.hasClients) _previewPages.jumpToPage(0);
    });
  }

  void _retryTiles() => setState(() {
    _tilesFailed = false;
    _tileEpoch++;
  });

  @override
  Widget build(BuildContext context) {
    final items = _library.mapItems;
    final phase = mapPhase(_library.status, items.length, _selected != null);
    if (phase == MapPhase.uninitialized || phase == MapPhase.loadingMedia) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    if (phase == MapPhase.error) {
      return _MapMessage(
        title: 'Couldn’t load your library',
        action: 'Try again',
        onAction: _library.refresh,
      );
    }
    if (phase == MapPhase.empty) {
      return _library.hasItems
          ? const _MapMessage(
              title: 'No locations yet',
              detail: 'Photos and videos captured with a GPS fix appear here.',
            )
          : const _MapMessage(title: 'No photos or videos yet');
    }

    final groups = groupMarkers(items, _library.locationOf, _zoom);
    final selected = _selected;
    final selectedItems = selected == null
        ? const <MediaItem>[]
        : [
            for (final item in items)
              if (selected.contains(item.key)) item,
          ];
    final kind = SettingsController.instance.mapKind;
    final points = _points;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            initialCameraFit: points.length < 2
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    maxZoom: 16,
                    padding: EdgeInsets.fromLTRB(
                      48,
                      widget.topPadding + 48,
                      48,
                      widget.bottomPadding + 120,
                    ),
                  ),
            minZoom: 2,
            maxZoom: 19,
            backgroundColor: const Color(0xFF1C1C1E),
            onMapReady: () {
              _mapReady = true;
              setState(() => _zoom = _map.camera.zoom);
            },
            onTap: (_, _) => setState(() => _selected = null),
            onPositionChanged: (camera, _) {
              // Regroup only when the zoom moved enough to change overlaps.
              if ((camera.zoom - _zoom).abs() >= .25) {
                setState(() => _zoom = camera.zoom);
              }
            },
          ),
          children: [
            TileLayer(
              key: ValueKey('base-$_tileEpoch-${kind.name}'),
              urlTemplate: kind.tileUrl,
              userAgentPackageName: 'com.gpscamera.gps_camera_next',
              errorTileCallback: (_, _, _) {
                if (!_tilesFailed && mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tilesFailed = true);
                  });
                }
              },
            ),
            if (kind.overlayUrl != null)
              TileLayer(
                key: ValueKey('labels-$_tileEpoch'),
                urlTemplate: kind.overlayUrl!,
                userAgentPackageName: 'com.gpscamera.gps_camera_next',
                errorTileCallback: (_, _, _) {},
              ),
            MarkerLayer(
              rotate: true,
              markers: [
                for (final group in groups)
                  Marker(
                    key: ValueKey(group.id),
                    point: LatLng(group.at.lat, group.at.lon),
                    width: 44,
                    height: 44,
                    child: _MarkerDot(
                      group: group,
                      selected:
                          selected != null &&
                          group.items.any((i) => selected.contains(i.key)),
                      onTap: () => _select(group),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 8,
          top: widget.topPadding + 6,
          // Readable on any imagery: the tile terms require visible credit.
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  'Map data © Esri',
                  style: TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        if (_tilesFailed)
          Positioned(
            top: widget.topPadding + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: const Color(0xE61C1C1E),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _retryTiles,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                      'Map images need a connection. Tap to retry.',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: widget.bottomPadding + (selectedItems.isEmpty ? 16 : 16 + 96),
          child: Material(
            color: const Color(0xE61C1C1E),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Show all locations',
              color: Colors.white,
              onPressed: _fit,
              icon: const Icon(Icons.zoom_out_map_rounded, size: 20),
            ),
          ),
        ),
        if (selectedItems.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: widget.bottomPadding + 12,
            height: 84,
            child: Material(
              color: const Color(0xF21C1C1E),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: PageView.builder(
                controller: _previewPages,
                itemCount: selectedItems.length,
                itemBuilder: (context, index) => _MarkerPreview(
                  item: selectedItems[index],
                  location: _library.locationOf(selectedItems[index]),
                  position: selectedItems.length > 1
                      ? '${index + 1} of ${selectedItems.length}'
                      : null,
                  onTap: () => widget.onOpen(selectedItems[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final MarkerGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = group.items.length;
    final size = (count > 1 ? 22.0 : 14.0) + (selected ? 4 : 0);
    return Semantics(
      button: true,
      label: count > 1
          ? '$count items at this location'
          : (group.items.first.isVideo ? 'Video location' : 'Photo location'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? cameraYellow : Colors.white,
              border: Border.all(color: const Color(0xFF1C1C1E), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 3),
              ],
            ),
            child: count > 1
                ? Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _MarkerPreview extends StatelessWidget {
  const _MarkerPreview({
    required this.item,
    required this.location,
    required this.onTap,
    this.position,
  });

  final MediaItem item;
  final MediaLocation? location;
  final String? position;
  final VoidCallback onTap;

  static final _date = DateFormat('d MMM yyyy  ·  HH:mm');

  @override
  Widget build(BuildContext context) {
    final at = location;
    final where = at == null
        ? ''
        : at.place.isNotEmpty
        ? at.place
        : '${at.lat.toStringAsFixed(5)}, ${at.lon.toStringAsFixed(5)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 64,
                child: Image(
                  image: MediaThumbnail(item),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF2C2C2E)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _date.format(item.taken),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        item.isVideo
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        [
                          item.isVideo
                              ? 'Video  ${formatMediaDuration(item.duration)}'
                              : 'Photo',
                          ?position,
                        ].join('  ·  '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({
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
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
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
