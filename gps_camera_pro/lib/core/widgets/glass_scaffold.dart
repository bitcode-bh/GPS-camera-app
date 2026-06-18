import 'package:flutter/material.dart';

import '../design/palette.dart';
import '../design/text_styles.dart';
import '../design/tokens.dart';
import 'aurora_background.dart';
import 'pressable.dart';

/// Shared chrome for the secondary screens: an animated aurora backdrop and a
/// frosted top bar with a back affordance, title/subtitle and optional actions.
class GlassScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;

  const GlassScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions = const [],
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Palette.ink,
      body: AuroraBackground(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Insets.md, topPad + 10, Insets.md, 6),
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.h1),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: AppText.label),
                        ],
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(child: body),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.glassFillStrong,
          border: Border.all(color: Palette.glassStroke),
        ),
        child: Icon(icon, size: 17, color: Palette.textHi),
      ),
    );
  }
}
