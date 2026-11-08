# Cafuné mark

The mark pairs a gently flowing C-shaped stroke with a small fingertip accent: motion, then a light touch. It stays abstract and readable without depicting a hand or a literal letterform.

- `logo.svg` uses a warm cream tile (`#fbf3e8`), deep plum stroke (`#4a2845`), and terracotta accent (`#cf7051`).
- `Sources/GestureCLI/MenuBarIcon.swift` mirrors the same path in a monochrome template image. macOS supplies the menu-bar tint at 22 × 22 points.
- Paused state keeps the mark and adds the existing two-bar pause badge at the lower right.

The SVG and AppKit path use the same 256-point canvas and C-curve control points. Keep them visually aligned when editing either representation. The status item remains a template image with its state-specific accessibility description.
