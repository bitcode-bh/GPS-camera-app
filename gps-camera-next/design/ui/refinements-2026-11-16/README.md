# Compact settings and softer stamp text

These images render the actual Flutter widgets with sample data. They are not phone screenshots and do not change device preferences.

- `custom-template.png`: a compact, content-sized preview (144 dp minimum), 40% smaller switches and collapsed Custom Text settings.
- `custom-text-expanded.png`: the same section expanded. Its fields retain their values when hidden; closing it dismisses the keyboard. Expansion uses the existing 220 ms standard curve and respects reduced motion.
- `display-units.png`: the shared smaller switch with a yellow active track and existing dark inactive colours.

All switch rows retain their 56 dp minimum height, native padded hit area, merged accessibility state and keyboard activation. Stamp text uses one 40% black shadow with 1 px blur and a 0.5 px vertical offset; the Android video text fallback matches it.

The camera photo viewport now starts directly below the safe-area-aware top controls instead of vertically centering in the available space. System insets, capture ratios and bottom control clearance are retained. Layout regression checks cover all photo ratios at widths of 320, 390 and 600 dp with nonzero system insets.

Validation: 162 Flutter tests passed and Flutter analysis found no issues. Device and iOS runtime checks were not performed for this change.
