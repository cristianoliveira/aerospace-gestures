# Icon concepts

**Selected: 1. Triple Swipe.** Current assets and usage guidance live in [../brand/](../brand/README.md). This folder preserves the original design exploration.

Open [comparison.png](comparison.png) to compare all four directions. [comparison.svg](comparison.svg) is the editable vector sheet.

| Option | Source | Idea |
| --- | --- | --- |
| 1. Triple Swipe | [SVG](01-triple-swipe.svg) | Three touch trails sweep toward a command. |
| 2. Trackpad Arrow | [SVG](02-trackpad-arrow.svg) | A trackpad with a directional swipe. |
| 3. Workspace Glide | [SVG](03-workspace-glide.svg) | Move between window tiles. |
| 4. Gesture A | [SVG](04-gesture-a.svg) | An A with a swipe for its crossbar. |

Individual icons have transparent backgrounds, a 256 × 256 viewBox, and `currentColor` strokes (black by default). Inline SVG can inherit a CSS color. The mint backgrounds belong only to the comparison sheet.

The sheet includes monochrome studies at 16, 22, and 32 pixels. View it at native size to judge these original samples. The app now draws Triple Swipe as a template image with a pause badge for paused actions; this historical sheet does not show the state variants.

To regenerate the PNG with ImageMagick:

```sh
magick -background none docs/icon-options/comparison.svg docs/icon-options/comparison.png
```
