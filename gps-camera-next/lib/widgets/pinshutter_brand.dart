import 'package:flutter/material.dart';

/// Outlined script artwork, rendered once rather than shaded on every frame.
class PinShutterWordmark extends StatelessWidget {
  const PinShutterWordmark({super.key, this.width = 240});

  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/pinshutter-wordmark.png',
    width: width,
    height: width / 4,
    fit: BoxFit.contain,
    semanticLabel: 'PinShutter',
  );
}

/// Only used while the camera is unavailable; never covers a live preview.
class PinShutterLoading extends StatelessWidget {
  const PinShutterLoading({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading camera',
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/pinshutter-icon.png',
            width: 96,
            height: 96,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 20),
          const PinShutterWordmark(),
          const SizedBox(height: 20),
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFFBCC2E6),
            ),
          ),
        ],
      ),
    ),
  );
}
