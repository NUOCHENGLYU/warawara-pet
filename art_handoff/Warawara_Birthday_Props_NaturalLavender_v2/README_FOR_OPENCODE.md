# Phase 6A — Natural Lavender Birthday Props v2

**Status: candidacy for real-Mac visual approval, not final accepted art.**

This package replaces the earlier pink/ornate birthday prop candidate package for Phase 6A. It tones the decorations toward muted lavender and warm everyday handmade materials, and replaces the busy balloon/bow letter paper with plain parchment. It does not change the accepted Warawara.

## Integration
Use artwork under `assets/` according to `ASSET_MANIFEST.json`. The file basenames are intentionally the same as in v1, so existing resource IDs and UI can stay unchanged. SHA256 values have changed. Do not trust v1 hashes.

Use only `cake_lit.png`, `envelope_closed.png`, `envelope_open.png`, `letter_paper_blank.png`, and very sparse gold or lavender sparkle sprites. `cake_lit.png` already contains a painted candle flame; do not add `candle_flame_standalone.png` on top.

The closed and open envelopes are separate static compositions and do not share fold geometry. Use a gentle reveal transition, not fake articulated frame-by-frame hinge motion.

Render actual user-authored birthday text via native SwiftUI, not baked into the paper image. Keep a plain native background fallback for accessibility/readability. Keep the existing Phase 5 Rig for main and companion characters.

Suggested sizes: cake 75–95pt, envelope 55–80pt, sparklers <=20pt and only a few simultaneously; adjust with real-Mac preview. No NSMenu, no new character assets, no random-event sprites in Phase 6A.

These are revised art candidates, **not** an assertion that the props are exact Studio Ghibli production art. Verify on both dark/light desktops and at actual desktop size.
