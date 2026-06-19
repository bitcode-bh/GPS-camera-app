import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/design/palette.dart';
import '../core/design/text_styles.dart';
import '../core/design/tokens.dart';
import '../core/glass.dart';
import '../core/widgets/pressable.dart';
import '../models/map_kind.dart';
import '../state/settings_controller.dart';

/// A live base-map card centred on the fix, with an accuracy ring and a glowing
/// heading pin. [compact] trims the chrome for small stamp thumbnails. Wrapped
/// in a [RepaintBoundary] so map tile repaints never dirty the rest of the UI.
class MiniMap extends StatelessWidget {
  final double lat;
  final double lon;
  final double heading;
  final MapKind kind;
  final Color accent;
  final double zoom;
  final double radius;
  final bool compact;

  /// When false, a lightweight painted placeholder is shown instead of a live
  /// tile map. Used for the many tiny previews (template gallery, editor) so we
  /// never spin up a dozen map engines / tile downloads at once.
  final bool realMap;

  const MiniMap({
    super.key,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.kind,
    this.accent = Palette.teal,
    this.zoom = 16.5,
    this.radius = 14,
    this.compact = false,
    this.realMap = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!realMap) {
      return _StaticMap(heading: heading, accent: accent, radius: radius, label: kind.label);
    }
    final center = LatLng(lat, lon);
    final br = BorderRadius.circular(radius);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: br,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            border: Border.all(color: Palette.glassStrokeSoft, width: 0.6),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                // Recreate only when the fix moves ~100 m, the style changes, or the zoom level changes,
                // so small jitters don't trigger a tile reload/flicker.
                key: ValueKey(
                    '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)},${kind.name},$zoom'),
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: kind.tileUrl,
                    userAgentPackageName: 'com.gpscamera.gps_camera_pro',
                    tileDimension: 256,
                  ),
                  if (kind.overlayUrl != null)
                    TileLayer(
                      urlTemplate: kind.overlayUrl!,
                      userAgentPackageName: 'com.gpscamera.gps_camera_pro',
                      tileDimension: 256,
                    ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: center,
                        radius: compact ? 13 : 20,
                        color: accent.withValues(alpha: 0.14),
                        borderColor: accent.withValues(alpha: 0.75),
                        borderStrokeWidth: 1.2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 36,
                        height: 36,
                        child: Transform.rotate(
                          angle: heading * math.pi / 180,
                          child: CustomPaint(painter: _PinPainter(accent)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Subtle vignette for legibility of any overlaid chrome.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0x00000000), Color(0x55000000)],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                Positioned(
                  left: 6,
                  top: 6,
                  child: _Tag(text: kind.label.toUpperCase(), accent: accent),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: _LiveDot(color: Palette.success),
                ),
                const Positioned(
                  left: 8,
                  bottom: 6,
                  child: Text('100 m',
                      style: TextStyle(
                          fontSize: 8, color: Color(0xFFD7DEE7), fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color accent;
  const _Tag({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: accent,
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 7)],
      ),
    );
  }
}

/// A painted, network-free stand-in for the live map (used in tiny previews).
class _StaticMap extends StatelessWidget {
  final double heading;
  final Color accent;
  final double radius;
  final String label;
  const _StaticMap({
    required this.heading,
    required this.accent,
    required this.radius,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: br,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(color: Palette.glassStroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _StaticMapPainter(accent)),
            Transform.rotate(
              angle: heading * math.pi / 180,
              child: Center(child: CustomPaint(painter: _PinPainter(accent), size: const Size(28, 28))),
            ),
            Positioned(
              left: 5,
              top: 5,
              child: _Tag(text: label.toUpperCase(), accent: accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticMapPainter extends CustomPainter {
  final Color accent;
  _StaticMapPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15314A), Color(0xFF0E2233), Color(0xFF14283A)],
        ).createShader(rect),
    );
    // Faint "streets".
    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      final y = size.height * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    final diag = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height * 0.3), diag);

    // Accuracy ring.
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, size.shortestSide * 0.22,
        Paint()..color = accent.withValues(alpha: 0.16));
    canvas.drawCircle(
      c,
      size.shortestSide * 0.22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _StaticMapPainter old) => old.accent != accent;
}

class _PinPainter extends CustomPainter {
  final Color accent;
  const _PinPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final cone = ui.Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - 9, c.dy - 19)
      ..lineTo(c.dx + 9, c.dy - 19)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(
          c,
          Offset(c.dx, c.dy - 19),
          [accent.withValues(alpha: 0.0), accent.withValues(alpha: 0.55)],
        ),
    );
    canvas.drawCircle(c, 5, Paint()..color = accent);
    canvas.drawCircle(
      c,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) => old.accent != accent;
}

/// Helper function to open the enlarged map zoom popup modal
void showMapZoomPopup(
  BuildContext context, {
  required double lat,
  required double lon,
  required double heading,
  required MapKind kind,
  required double initialZoom,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _MapZoomPopup(
      lat: lat,
      lon: lon,
      heading: heading,
      kind: kind,
      initialZoom: initialZoom,
    ),
  );
}

/// A premium glassmorphism popup displaying a larger interactive map preview
/// with zoom controls (+/-), double-tap to reset zoom, and pinch-to-zoom gestures.
class _MapZoomPopup extends StatefulWidget {
  final double lat;
  final double lon;
  final double heading;
  final MapKind kind;
  final double initialZoom;

  const _MapZoomPopup({
    required this.lat,
    required this.lon,
    required this.heading,
    required this.kind,
    required this.initialZoom,
  });

  @override
  State<_MapZoomPopup> createState() => _MapZoomPopupState();
}

class _MapZoomPopupState extends State<_MapZoomPopup> {
  late double _currentZoom;
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _currentZoom = widget.initialZoom;
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    // Save the zoom level to settings when the popup closes
    final zoomToSave = _currentZoom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SettingsController.instance.update(() {
        SettingsController.instance.mapZoom = zoomToSave;
      });
    });
    super.dispose();
  }

  void _zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 0.5).clamp(1.0, 18.0);
      _mapController.move(LatLng(widget.lat, widget.lon), _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 0.5).clamp(1.0, 18.0);
      _mapController.move(LatLng(widget.lat, widget.lon), _currentZoom);
    });
  }

  void _resetZoom() {
    setState(() {
      _currentZoom = 16.5; // Default zoom
      _mapController.move(LatLng(widget.lat, widget.lon), _currentZoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.lat, widget.lon);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlassSurface(
            radius: Corners.xl,
            blur: Blurs.sheet,
            fill: const Color(0xE6080C16),
            stroke: Palette.glassStroke,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corners.xl),
              child: SizedBox(
                height: 280,
                child: GestureDetector(
                  onDoubleTap: _resetZoom,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: _currentZoom,
                          onPositionChanged: (position, hasGesture) {
                            if (hasGesture) {
                              setState(() {
                                _currentZoom = position.zoom.clamp(1.0, 18.0);
                              });
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: widget.kind.tileUrl,
                            userAgentPackageName: 'com.gpscamera.gps_camera_pro',
                            tileDimension: 256,
                          ),
                          if (widget.kind.overlayUrl != null)
                            TileLayer(
                              urlTemplate: widget.kind.overlayUrl!,
                              userAgentPackageName: 'com.gpscamera.gps_camera_pro',
                              tileDimension: 256,
                            ),
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: center,
                                radius: 20,
                                color: Palette.teal.withValues(alpha: 0.14),
                                borderColor: Palette.teal.withValues(alpha: 0.75),
                                borderStrokeWidth: 1.2,
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: center,
                                width: 36,
                                height: 36,
                                child: Transform.rotate(
                                  angle: widget.heading * math.pi / 180,
                                  child: CustomPaint(painter: _PinPainter(Palette.teal)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Top-Left Floating Zoom Value Chip
                      Positioned(
                        left: 10,
                        top: 10,
                        child: IgnorePointer(
                          child: GlassSurface(
                            radius: Corners.sm,
                            blur: Blurs.chip,
                            fill: const Color(0x99070B14),
                            stroke: Palette.glassStroke,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              '${_currentZoom.toStringAsFixed(1)}x',
                              style: AppText.mono.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Palette.teal,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Top-Right Floating Close Button
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Pressable(
                          onTap: () => Navigator.pop(context),
                          child: GlassSurface(
                            radius: Corners.pill,
                            blur: Blurs.chip,
                            fill: const Color(0x99070B14),
                            stroke: Palette.glassStroke,
                            padding: const EdgeInsets.all(6),
                            child: const Icon(Icons.close, size: 16, color: Palette.textHi),
                          ),
                        ),
                      ),
                      // Bottom-Left Reset Instruction Hint
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0x99070B14),
                              borderRadius: BorderRadius.circular(Corners.sm),
                              border: Border.all(color: Palette.glassStrokeSoft, width: 0.6),
                            ),
                            child: Text(
                              'Double-tap to reset',
                              style: AppText.caption.copyWith(
                                fontSize: 8.5,
                                color: Palette.textHi,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Bottom-Right Floating zoom +/- controls
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ZoomButton(icon: Icons.add, onTap: _zoomIn),
                            const SizedBox(height: 8),
                            _ZoomButton(icon: Icons.remove, onTap: _zoomOut),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        radius: Corners.sm,
        blur: Blurs.chip,
        fill: const Color(0x99070B14),
        stroke: Palette.glassStroke,
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: Palette.textHi),
      ),
    );
  }
}
