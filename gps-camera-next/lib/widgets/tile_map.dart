import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A point on Earth in degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

/// Web Mercator, where the whole world is `256 · 2^zoom` logical pixels wide.
class Mercator {
  const Mercator._();

  static const maxLat = 85.05112878;

  static double worldSize(double zoom) => 256 * math.pow(2, zoom).toDouble();

  static Offset project(GeoPoint p, double zoom) {
    final size = worldSize(zoom);
    final lat = p.lat.clamp(-maxLat, maxLat) * math.pi / 180;
    final x = (p.lon + 180) / 360 * size;
    final y =
        (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * size;
    return Offset(x, y);
  }

  static GeoPoint unproject(Offset o, double zoom) {
    final size = worldSize(zoom);
    final lon = o.dx / size * 360 - 180;
    final n = math.pi - 2 * math.pi * o.dy / size;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return GeoPoint(lat.clamp(-maxLat, maxLat), lon);
  }
}

/// The view: centre and zoom. Listeners rebuild the map.
class TileMapController extends ChangeNotifier {
  TileMapController({
    GeoPoint center = const GeoPoint(0, 0),
    double zoom = 3,
    this.minZoom = 1,
    this.maxZoom = 19,
  }) {
    _center = center;
    _zoom = zoom.clamp(minZoom, maxZoom);
  }

  final double minZoom;
  final double maxZoom;
  late GeoPoint _center;
  late double _zoom;

  GeoPoint get center => _center;
  double get zoom => _zoom;

  void move(GeoPoint center, double zoom) {
    _center = center;
    _zoom = zoom.clamp(minZoom, maxZoom);
    notifyListeners();
  }

  /// Frames [points] inside [size] minus [padding], at most [maxZoom].
  void fit(
    List<GeoPoint> points,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
    double maxZoom = 16,
  }) {
    if (points.isEmpty || size.isEmpty) return;
    final view = padding.deflateSize(size);
    var zoom = math.min(maxZoom, this.maxZoom);
    // Measure the points at zoom 0, then scale up to fill the view.
    final at0 = [for (final p in points) Mercator.project(p, 0)];
    final rect = at0
        .skip(1)
        .fold(
          Rect.fromPoints(at0.first, at0.first),
          (r, o) => r.expandToInclude(Rect.fromPoints(o, o)),
        );
    if (rect.width > 0 || rect.height > 0) {
      final scale = math.min(
        rect.width > 0 ? view.width / rect.width : double.infinity,
        rect.height > 0 ? view.height / rect.height : double.infinity,
      );
      zoom = math.min(zoom, math.log(scale) / math.ln2);
    }
    zoom = zoom.clamp(minZoom, this.maxZoom);
    // Centre the points in the padded view, not the whole widget.
    final centre0 = rect.center;
    final world = Mercator.worldSize(zoom) / 256;
    final shift = Offset(
      (padding.right - padding.left) / 2,
      (padding.bottom - padding.top) / 2,
    );
    move(Mercator.unproject(centre0 * world + shift, zoom), zoom);
  }
}

/// One raster tile source.
class TileSource {
  const TileSource(this.urlTemplate, {this.tileSize = 256});

  /// With `{z}`, `{x}` and `{y}`.
  final String urlTemplate;

  /// Image pixels per tile. 512 px tiles are drawn one level lower, so their
  /// labels keep the size they were designed at.
  final int tileSize;

  String url(int z, int x, int y) => urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');
}

/// Something drawn at a place on the map, centred on it.
class MapMarker {
  const MapMarker({
    required this.at,
    required this.child,
    this.size = const Size(44, 44),
    this.key,
  });

  final GeoPoint at;
  final Widget child;
  final Size size;
  final Key? key;
}

/// A small slippy map: raster tiles, markers, and (optionally) pan, pinch and
/// double-tap zoom. No rotation.
class TileMap extends StatefulWidget {
  const TileMap({
    super.key,
    required this.controller,
    required this.sources,
    this.markers = const [],
    this.interactive = true,
    this.userAgent,
    this.headers = const {},
    this.background = const Color(0xFF1C1C1E),
    this.onTap,
    this.onTileError,
  });

  final TileMapController controller;
  final List<TileSource> sources;
  final List<MapMarker> markers;
  final bool interactive;
  final String? userAgent;
  final Map<String, String> headers;
  final Color background;
  final VoidCallback? onTap;
  final VoidCallback? onTileError;

  @override
  State<TileMap> createState() => _TileMapState();
}

class _TileMapState extends State<TileMap> {
  // Gesture start state.
  GeoPoint? _startCenter;
  double _startZoom = 0;
  Offset _startFocal = Offset.zero;
  Size _size = Size.zero;

  TileMapController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(TileMap old) {
    super.didUpdateWidget(old);
    if (old.controller != _c) {
      old.controller.removeListener(_changed);
      _c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Screen position of a world pixel at the current view.
  Offset _toScreen(Offset world, Offset centre) =>
      world - centre + _size.center(Offset.zero);

  void _onScaleStart(ScaleStartDetails d) {
    _startCenter = _c.center;
    _startZoom = _c.zoom;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _startCenter;
    if (start == null) return;
    final zoom = (_startZoom + math.log(d.scale) / math.ln2).clamp(
      _c.minZoom,
      _c.maxZoom,
    );
    // Keep the world point that was under the first focal point under the
    // fingers as they move and spread.
    final mid = _size.center(Offset.zero);
    final startCentre = Mercator.project(start, _startZoom);
    final anchor = startCentre + (_startFocal - mid);
    final anchorNow = anchor * math.pow(2, zoom - _startZoom).toDouble();
    final centre = anchorNow - (d.localFocalPoint - mid);
    _c.move(Mercator.unproject(centre, zoom), zoom);
  }

  void _onDoubleTap(TapDownDetails d) {
    final zoom = (_c.zoom + 1).clamp(_c.minZoom, _c.maxZoom);
    final mid = _size.center(Offset.zero);
    final centre = Mercator.project(_c.center, _c.zoom);
    final anchor = centre + (d.localPosition - mid);
    final anchorNow = anchor * math.pow(2, zoom - _c.zoom).toDouble();
    _c.move(
      Mercator.unproject(anchorNow - (d.localPosition - mid), zoom),
      zoom,
    );
  }

  List<Widget> _tiles(TileSource source, Offset centre) {
    final levelShift = source.tileSize >= 512 ? 1 : 0;
    final level = (_c.zoom.round() - levelShift).clamp(0, 22);
    final count = 1 << level;
    final tileSize = Mercator.worldSize(_c.zoom) / count;
    final topLeft = centre - _size.center(Offset.zero);
    final first = (topLeft.dx / tileSize).floor();
    final last = ((topLeft.dx + _size.width) / tileSize).floor();
    final top = math.max(0, (topLeft.dy / tileSize).floor());
    final bottom = math.min(
      count - 1,
      ((topLeft.dy + _size.height) / tileSize).floor(),
    );
    final headers = {
      ...widget.headers,
      if (widget.userAgent != null) 'User-Agent': widget.userAgent!,
    };
    return [
      for (var ty = top; ty <= bottom; ty++)
        for (var tx = first; tx <= last; tx++)
          Positioned(
            key: ValueKey('${source.urlTemplate}/$level/$tx/$ty'),
            left: tx * tileSize - topLeft.dx,
            top: ty * tileSize - topLeft.dy,
            // A hair larger so neighbouring tiles never show a seam.
            width: tileSize + .5,
            height: tileSize + .5,
            child: Image.network(
              source.url(level, ((tx % count) + count) % count, ty),
              headers: headers,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stack) {
                final report = widget.onTileError;
                if (report != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => report());
                }
                return const SizedBox.shrink();
              },
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      if (_size.isEmpty || !_size.isFinite) return const SizedBox.shrink();
      final centre = Mercator.project(_c.center, _c.zoom);
      final map = ClipRect(
        child: ColoredBox(
          color: widget.background,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final source in widget.sources) ..._tiles(source, centre),
              for (final marker in widget.markers)
                () {
                  final at = _toScreen(
                    Mercator.project(marker.at, _c.zoom),
                    centre,
                  );
                  return Positioned(
                    key: marker.key,
                    left: at.dx - marker.size.width / 2,
                    top: at.dy - marker.size.height / 2,
                    width: marker.size.width,
                    height: marker.size.height,
                    child: marker.child,
                  );
                }(),
            ],
          ),
        ),
      );
      if (!widget.interactive) return IgnorePointer(child: map);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTapDown: _onDoubleTap,
        onDoubleTap: () {},
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: (_) => _startCenter = null,
        child: map,
      );
    },
  );
}
