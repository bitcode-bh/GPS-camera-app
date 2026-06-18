import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/text_styles.dart';
import '../../core/design/tokens.dart';
import '../../core/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/transitions.dart';
import '../../models/geo_data.dart';
import '../../models/template.dart';
import '../../state/settings_controller.dart';
import '../../state/template_controller.dart';
import '../../widgets/geo_stamp.dart';
import 'custom_template_editor.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final templates = TemplateController.instance;
    final settings = SettingsController.instance;
    final geo = GeoData.demo();

    return GlassScaffold(
      title: 'Templates',
      subtitle: 'Choose how your stamp looks',
      actions: [
        Pressable(
          onTap: () => Navigator.of(context)
              .push(SheetRoute(page: const CustomTemplateEditor())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: Palette.selectionGradient,
              borderRadius: BorderRadius.circular(Corners.pill),
              border: Border.all(color: Palette.selectionStroke, width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Palette.selectionGlow,
                  blurRadius: 14,
                  spreadRadius: -3,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 15, color: Palette.textHi),
                const SizedBox(width: 6),
                Text('Customize',
                    style: AppText.label.copyWith(
                        color: Palette.textHi, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
      body: ListenableBuilder(
        listenable: templates,
        builder: (context, _) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(Insets.md, 6, Insets.md, 32),
            itemCount: StampTemplate.values.length,
            separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
            itemBuilder: (context, i) {
              final t = StampTemplate.values[i];
              return _TemplateCard(
                template: t,
                selected: templates.config.template == t,
                geo: geo,
                settings: settings,
                onTap: () {
                  templates.selectTemplate(t);
                  Navigator.of(context).maybePop();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final StampTemplate template;
  final bool selected;
  final GeoData geo;
  final SettingsController settings;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.geo,
    required this.settings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = TemplateConfig.forTemplate(template);
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        radius: Corners.lg,
        blur: 12,
        stroke: selected ? Palette.selectionStroke : Palette.glassStroke,
        padding: const EdgeInsets.all(Insets.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(template.title, style: AppText.h2),
                const SizedBox(width: 8),
                if (template.isNew) const _NewBadge(),
                const Spacer(),
                _SelectMark(selected: selected),
              ],
            ),
            const SizedBox(height: 2),
            Text(template.blurb, style: AppText.label),
            const SizedBox(height: Insets.sm),
            // Preview over a faux-photo backdrop.
            ClipRRect(
              borderRadius: BorderRadius.circular(Corners.md),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF233149), Color(0xFF11182A), Color(0xFF1A2336)],
                  ),
                ),
                child: Align(
                  alignment: cfg.position == StampPosition.top
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: GeoStamp(
                    geo: geo,
                    config: cfg,
                    settings: settings,
                    preview: true,
                    live: false,
                    realMap: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.selectionFill,
        borderRadius: BorderRadius.circular(Corners.pill),
        border: Border.all(color: Palette.selectionStroke, width: 1),
      ),
      child: Text('NEW',
          style: AppText.caption.copyWith(
              color: Palette.accentMuted, fontSize: 8.5, letterSpacing: 0.8)),
    );
  }
}

class _SelectMark extends StatelessWidget {
  final bool selected;
  const _SelectMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.emphasized,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected ? Palette.selectionGradient : null,
        color: selected ? null : Palette.glassFillStrong,
        border: Border.all(
          color: selected ? Palette.selectionStroke : Palette.glassStroke,
        ),
      ),
      child: Icon(
        selected ? Icons.check : Icons.circle_outlined,
        size: selected ? 15 : 13,
        color: selected ? Palette.textHi : Palette.textLo,
      ),
    );
  }
}
