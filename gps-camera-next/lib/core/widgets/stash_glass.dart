import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Adapts Stash's glass optics to Flutter's Impeller backdrop texture.
class StashGlass extends StatelessWidget {
  static ui.FragmentProgram? _program;

  static Future<void> prepare() async {
    if (ui.ImageFilter.isShaderFilterSupported) {
      _program = await ui.FragmentProgram.fromAsset('shaders/stash_glass.frag');
    }
  }

  static bool get supported => _program != null;

  final Widget child;
  final double radius;
  final Color tint;
  final double head;
  final double tail;
  final double dropRadius;
  final double dropHalfWidth;
  final bool vertical;
  final bool menu;

  const StashGlass({
    super.key,
    required this.child,
    required this.radius,
    required this.tint,
    this.head = 0,
    this.tail = 0,
    this.dropRadius = 0,
    this.dropHalfWidth = 0,
    this.vertical = false,
    this.menu = false,
  });

  @override
  Widget build(BuildContext context) {
    final program = _program;
    if (program == null) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: _GlassFilter(
              program: program,
              glass: this,
              scale: MediaQuery.devicePixelRatioOf(context),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlassFilter extends LeafRenderObjectWidget {
  final ui.FragmentProgram program;
  final StashGlass glass;
  final double scale;

  const _GlassFilter({
    required this.program,
    required this.glass,
    required this.scale,
  });

  @override
  _RenderGlassFilter createRenderObject(BuildContext context) =>
      _RenderGlassFilter(program.fragmentShader(), glass, scale);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassFilter renderObject,
  ) {
    renderObject.update(glass, scale);
  }
}

class _RenderGlassFilter extends RenderBox {
  final ui.FragmentShader _shader;
  StashGlass _glass;
  double _scale;

  _RenderGlassFilter(this._shader, this._glass, this._scale);

  void update(StashGlass glass, double scale) {
    final old = _glass;
    if (_scale == scale &&
        old.radius == glass.radius &&
        old.tint == glass.tint &&
        old.head == glass.head &&
        old.tail == glass.tail &&
        old.dropRadius == glass.dropRadius &&
        old.dropHalfWidth == glass.dropHalfWidth &&
        old.vertical == glass.vertical &&
        old.menu == glass.menu) {
      return;
    }
    _glass = glass;
    _scale = scale;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final origin = localToGlobal(Offset.zero) * _scale;
    final tint = _glass.tint;
    _shader
      ..setFloat(2, origin.dx)
      ..setFloat(3, origin.dy)
      ..setFloat(4, size.width * _scale)
      ..setFloat(5, size.height * _scale)
      ..setFloat(6, _glass.radius * _scale)
      ..setFloat(7, tint.a)
      ..setFloat(8, tint.r)
      ..setFloat(9, tint.g)
      ..setFloat(10, tint.b)
      ..setFloat(11, _glass.head * _scale)
      ..setFloat(12, _glass.tail * _scale)
      ..setFloat(13, _glass.dropRadius * _scale)
      ..setFloat(14, _glass.dropHalfWidth * _scale)
      ..setFloat(15, _glass.vertical ? 1 : 0)
      ..setFloat(16, _glass.menu ? _scale : 0);
    final filter = (layer as BackdropFilterLayer? ?? BackdropFilterLayer())
      ..filter = ui.ImageFilter.shader(_shader)
      ..blendMode = BlendMode.src;
    layer = filter;
    context.pushClipRect(
      true,
      offset,
      Offset.zero & size,
      (context, offset) => context.pushLayer(filter, (_, _) {}, offset),
      clipBehavior: Clip.hardEdge,
    );
  }

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }
}
