import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// A shared, premium page transition: the incoming page fades through while
/// sliding up a touch and settling with the app's emphasised curve. Used for
/// all pushes so navigation feels like one coherent system.
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute({required Widget page})
      : super(
          transitionDuration: Motion.page,
          reverseTransitionDuration: Motion.normal,
          opaque: false,
          barrierColor: Colors.black54,
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Motion.emphasized,
              reverseCurve: Motion.standard,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Sheet-style route that slides up from the bottom (templates, editors).
class SheetRoute<T> extends PageRouteBuilder<T> {
  SheetRoute({required Widget page})
      : super(
          transitionDuration: Motion.page,
          reverseTransitionDuration: Motion.normal,
          opaque: false,
          barrierColor: Colors.black54,
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Motion.emphasized,
              reverseCurve: Motion.standard,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        );
}
