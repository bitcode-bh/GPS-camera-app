# PinShutter — Stash reference concepts

Preview only. No application icon, font, splash screen or running UI was replaced.

- **01 / Spectrum P:** closest to the current Stash launcher identity; white script P inside a multicolour glass lens, with matching script wordmark.
- **02 / Amber P:** the same family in warm yellow/gold to relate to PinShutter's capture and adjustment controls.
- **03 / Pin Lens:** a location pin and geometric shutter opening, paired with a quieter pearl script wordmark.

Review the [concept board](/Volumes/Bitcode/GitHub/GPS-camera-app/gps-camera-next/design/logo/pinshutter-stash-reference-v1/concept-board.png). Each concept also has separate icon and wordmark SVG/PNG files here. PNG wordmarks have transparent backgrounds; SVG wordmarks use shaped glyph outlines, without requiring a font installation.

## Reference and creation

The local Stash project supplied visual references:

- [Current launcher artwork](/Volumes/Bitcode/GitHub/Stash/app/src/main/res/mipmap-xxxhdpi/ic_launcher_art.png)
- [GlassWord implementation](/Volumes/Bitcode/GitHub/Stash/app/src/main/kotlin/app/stash/ui/Glass.kt:439)
- [Pacifico font](/Volumes/Bitcode/GitHub/Stash/app/src/main/res/font/pacifico.ttf), whose embedded licence metadata identifies SIL Open Font License 1.1.

The new marks were drawn as SVG geometry. The wordmark is the exact approved text **PinShutter**, shaped with HarfBuzz and outlined with fontTools using the same Pacifico face as Stash. The glass look is a new static SVG treatment; the Stash raster icon and shader implementation were not edited or copied into the app. Renders use local rsvg-convert. No image-generation service or external upload was used.

Reproduce with `python3 generate.py` from this directory using the installed local tools and reference font. The script asserts valid SVG structure and glyph availability. The board and individual icons were visually reviewed. Final selection, Android mask/size checks and any app integration remain for a subsequent approved step; this preview does not settle the outstanding project/brand rights review.
