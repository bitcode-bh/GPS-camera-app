import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/media_item.dart';
import '../../services/media_image.dart';

/// Grid geometry for one column count. Pure, so the zoom math is testable.
class GridLayout {
  const GridLayout({
    required this.width,
    required this.columns,
    this.topPadding = 0,
  });

  static const spacing = 2.0;

  final double width;
  final int columns;
  final double topPadding;

  double get cell => (width - spacing * (columns - 1)) / columns;
  double get pitch => cell + spacing;

  double contentHeight(int count) =>
      topPadding + (count / columns).ceil() * pitch;

  /// The item under a content-space point, and how far down its row it is.
  ({int index, double rowFraction}) anchorAt(Offset point, int count) {
    if (count <= 0) return (index: 0, rowFraction: 0);
    final rows = (point.dy - topPadding) / pitch;
    final lastRow = (count - 1) ~/ columns;
    final row = rows.floor().clamp(0, lastRow);
    final column = (point.dx / pitch).floor().clamp(0, columns - 1);
    return (
      index: math.min(row * columns + column, count - 1),
      rowFraction: (rows - row).clamp(0.0, 1.0),
    );
  }

  /// Scroll offset that puts the anchored item back at viewport y [focalY].
  double scrollFor(int index, double rowFraction, double focalY) =>
      topPadding + (index ~/ columns + rowFraction) * pitch - focalY;
}

/// Density levels and the continuous value a pinch moves between them.
class GridDensity {
  /// Practical column counts for the available width, sparse to dense.
  static List<int> levelsFor(double width) {
    if (width >= 840) return const [4, 6, 9, 12];
    if (width >= 600) return const [3, 5, 7, 10];
    return const [2, 3, 4, 6];
  }

  static int defaultFor(List<int> levels) => levels[1];

  /// The layout drawn for a continuous column value: the next denser level,
  /// scaled up, so the grid always covers the viewport mid-pinch.
  static int renderLevel(List<int> levels, double effective) {
    for (final level in levels) {
      if (level >= effective - 1e-6) return level;
    }
    return levels.last;
  }

  /// The level a released pinch settles on (nearest by ratio).
  static int snapLevel(List<int> levels, double effective) {
    var best = levels.first;
    var bestDistance = double.infinity;
    for (final level in levels) {
      final distance = (math.log(level) - math.log(effective)).abs();
      if (distance < bestDistance) {
        best = level;
        bestDistance = distance;
      }
    }
    return best;
  }

  static double clamp(List<int> levels, double effective) =>
      effective.clamp(levels.first * .8, levels.last * 1.2).toDouble();
}

class MediaGrid extends StatefulWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.onOpen,
    required this.initialColumns,
    required this.onColumnsChanged,
    this.topPadding = 0,
    this.bottomPadding = 0,
  });

  final List<MediaItem> items;
  final ValueChanged<int> onOpen;
  final int? initialColumns;
  final ValueChanged<int> onColumnsChanged;
  final double topPadding;
  final double bottomPadding;

  @override
  State<MediaGrid> createState() => MediaGridState();
}

class MediaGridState extends State<MediaGrid>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _pointers = <int, Offset>{};
  late final _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_onSettleTick);

  List<int> _levels = const [2, 3, 4, 6];
  double _width = 0;
  double _viewportHeight = 0;
  int? _columns; // Committed level. Null until the first layout.
  double _effective = 3; // Continuous columns while pinching or settling.
  bool _pinching = false;
  double _startSpan = 1;
  double _startEffective = 3;
  Offset _focal = Offset.zero;
  int _anchorIndex = 0;
  double _anchorFraction = 0;
  double _settleFrom = 3;
  int _settleTo = 3;

  bool get _zooming => _pinching || _settle.isAnimating;
  int get _renderColumns => GridDensity.renderLevel(_levels, _effective);

  GridLayout _layout(int columns) => GridLayout(
    width: _width,
    columns: columns,
    topPadding: widget.topPadding,
  );

  @override
  void dispose() {
    _settle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just far enough to show [index], e.g. after leaving the viewer.
  void ensureVisible(int index) {
    if (!_scroll.hasClients || _width <= 0 || _zooming) return;
    final layout = _layout(_renderColumns);
    final top = layout.topPadding + (index ~/ layout.columns) * layout.pitch;
    final position = _scroll.position;
    final visibleTop = position.pixels + widget.topPadding;
    final visibleBottom =
        position.pixels + _viewportHeight - widget.bottomPadding;
    double? target;
    if (top < visibleTop) {
      target = top - widget.topPadding;
    } else if (top + layout.cell > visibleBottom) {
      target = top + layout.cell - _viewportHeight + widget.bottomPadding;
    }
    if (target != null) {
      _scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _startPinch();
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pinching && _pointers.length >= 2) _updatePinch();
  }

  void _pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.length < 2) _endPinch();
  }

  double get _span {
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _startPinch() {
    if (!_scroll.hasClients || widget.items.isEmpty) return;
    _settle.stop();
    final points = _pointers.values.take(2).toList();
    _focal = (points[0] + points[1]) / 2;
    _startSpan = math.max(_span, 1);
    _startEffective = _effective;
    // Scaling pivots on the focal point, so the content under it is exact.
    final anchor = _layout(_renderColumns).anchorAt(
      Offset(_focal.dx, _scroll.offset + _focal.dy),
      widget.items.length,
    );
    _anchorIndex = anchor.index;
    _anchorFraction = anchor.rowFraction;
    setState(() => _pinching = true);
  }

  void _updatePinch() {
    // Spreading the fingers enlarges thumbnails, so it lowers the column count.
    _apply(
      GridDensity.clamp(
        _levels,
        _startEffective * _startSpan / math.max(_span, 1),
      ),
    );
  }

  void _endPinch() {
    _settleFrom = _effective;
    _settleTo = GridDensity.snapLevel(_levels, _effective);
    setState(() => _pinching = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
      _onSettleTick();
    } else {
      _settle.forward(from: 0);
    }
  }

  void _onSettleTick() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    _apply(_settleFrom + (_settleTo - _settleFrom) * t);
    if (_settle.value == 1 && _columns != _settleTo) {
      _columns = _settleTo;
      widget.onColumnsChanged(_settleTo);
    }
  }

  /// Draw [effective] columns while keeping the anchored item under the focal
  /// point, whichever level is rendered underneath.
  void _apply(double effective) {
    if (!mounted) return;
    setState(() => _effective = effective);
    if (!_scroll.hasClients) return;
    final layout = _layout(_renderColumns);
    final maxScroll = math.max(
      0.0,
      layout.contentHeight(widget.items.length) +
          widget.bottomPadding -
          _viewportHeight,
    );
    _scroll.jumpTo(
      layout
          .scrollFor(_anchorIndex, _anchorFraction, _focal.dy)
          .clamp(0.0, maxScroll),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final levels = GridDensity.levelsFor(width);
      if (width != _width || _columns == null) {
        // First layout, or the window changed size: keep the nearest level.
        _width = width;
        _levels = levels;
        final wanted = _columns ?? widget.initialColumns;
        _columns = wanted == null
            ? GridDensity.defaultFor(levels)
            : GridDensity.snapLevel(levels, wanted.toDouble());
        if (!_zooming) _effective = _columns!.toDouble();
      }
      _viewportHeight = constraints.maxHeight;
      final columns = _renderColumns;
      final scale = columns / _effective;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final thumbnailSize = _layout(columns).cell * pixelRatio > 190
          ? 512
          : 256;
      return Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerEnd,
        onPointerCancel: _pointerEnd,
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_focal.dx, _focal.dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1)
              ..translateByDouble(-_focal.dx, -_focal.dy, 0, 1),
            child: GridView.builder(
              controller: _scroll,
              physics: _zooming
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: widget.topPadding,
                bottom: widget.bottomPadding,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: GridLayout.spacing,
                crossAxisSpacing: GridLayout.spacing,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) => MediaTile(
                key: ValueKey(widget.items[index].key),
                item: widget.items[index],
                thumbnailSize: thumbnailSize,
                compact: columns >= levels.last,
                onTap: _zooming ? null : () => widget.onOpen(index),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.thumbnailSize,
    this.compact = false,
    this.onTap,
  });

  final MediaItem item;
  final int thumbnailSize;
  final bool compact;
  final VoidCallback? onTap;

  static final _date = DateFormat('d MMM yyyy, HH:mm');

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: item.isVideo
        ? 'Video, ${formatMediaDuration(item.duration)}, ${_date.format(item.taken)}'
        : 'Photo, ${_date.format(item.taken)}',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF1C1C1E)),
            Hero(
              tag: item.key,
              child: Image(
                image: MediaThumbnail(item, size: thumbnailSize),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: child,
                      ),
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white24,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (item.isVideo)
              Positioned(
                right: 4,
                bottom: 3,
                child: compact
                    ? const Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                      )
                    : Text(
                        formatMediaDuration(item.duration),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                        ),
                      ),
              ),
          ],
        ),
      ),
    ),
  );
}
