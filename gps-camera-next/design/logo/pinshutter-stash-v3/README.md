# PinShutter — approved PS identity

Owner approved **“go with ps one”** on **16 November 2026**. Applied to launcher, loading and library assets; deployment validation is recorded separately below.

The owner requested brighter, more vibrant colours, Stash's original background/texture/appearance and less resemblance to Pinterest. The previous independent SVG approximation was replaced in this preview with the original local Stash canvas renderer:

`/Volumes/Bitcode/GitHub/Stash/docs/skills/compose-liquid-glass/assets/drop-icon.html`

The unmodified source, rendered with Stash's Pacifico font and Chrome canvas, reproduces the shipped Stash icon **pixel for pixel**. The PS proposal changes only the lettering and its fit within the lens. Every pixel outside the lens remains identical to the shipped Stash icon. Stash's original vibrant teal/coral/blue/violet fields, blur and refraction are retained. The wordmark remains outlined Pacifico with brighter matching tints.

The approved PS mark replaces the standalone P. This review does not resolve the existing ownership/rights gate for material derived from Stash. No trademark clearance is claimed.

Reproduce with local Chrome, Node, rsvg-convert and access to Stash's local font:

```sh
node design/logo/pinshutter-stash-v3/render.cjs design/logo/pinshutter-stash-v3/stash-original-render.html design/logo/pinshutter-stash-v3/pinshutter-ps.html
python3 design/logo/pinshutter-stash-v3/board.py
```

HTML references the existing local font; the font file is not embedded or redistributed here. `validation.json` records the pixel comparison. The board uses Stash's `#19151B` ink canvas and compares its actual reference icon with the proposed PinShutter icon. Screen layouts and asset names remain those of the previous integration; only the approved artwork changes. The adaptive icon follows Stash’s full-artwork background with transparent foreground; its themed alternative uses a white PS and lens outline.

Export the approved assets after rendering the PS master and wordmark:

```sh
python3 design/logo/pinshutter-stash-v3/export.py
node design/logo/pinshutter-stash-v3/render.cjs design/logo/pinshutter-stash-v3/assets-export.html
dart run flutter_launcher_icons
```

The asset exporter uses local browser canvas to draw the original master into native size variants. No image-generation service, external upload, runtime branding shader or new package is used. The build contains static raster artwork only.

## Integration validation

The approved PS assets are installed on Motorola Edge 70 through secure wireless ADB. The same update includes the owner's requested bottom Library/Map bar and lower stamp placement. Analysis is clean, all 157 Flutter tests pass and the Android debug APK builds. `docs/device-evidence-2026-11-16/ps-layout-deployment.json` records artifact identity, actual device observations and the remaining controlled exit-retest limit. No iOS build or production release was performed.
