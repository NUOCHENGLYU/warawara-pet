# Warawara Birthday Props — Hand-painted Candidate v3

**Status:** candidates for user visual acceptance. Do not claim studio-authored art or exact film artwork.

This package replaces `Warawara_Birthday_Props_NaturalLavender_v2` **only after explicit user approval**. It retains the same 12 filenames and canvas dimensions as v2. No Swift source changes should be necessary if resource IDs are filename-based; update embedded asset bytes, hashes, and packaged bundle verification.

## Visual intention
Traditional hand-painted animation feel: simple objects, irregular watercolor texture, paper grain, little hand-painted flowers, practical small props. Cream/paper tones, dusty lavender, warm candlelight, natural greens. No princess jewelry, no oversized bows, no generated Warawara characters.

## Caveat / provenance
The four main birthday illustrations were extracted from a newly generated watercolor visual-reference sheet, manually masked to transparent RGBA and packaged as independent sprites. Native painted source detail is roughly 150–220 pixels across; 1024px canvases preserve SwiftPM compatibility, **not native 1024px illustration sharpness**. Intended prop sizes are ~55–100 pt on Retina desktop. Inspect outlines at actual desktop size before acceptance. Supplemental sparkle/flame pixels remain sourced from the prior v2 package, not newly painted.

`cake_lit.png` ALREADY includes painted candle flame. Do not overlay `candle_flame_standalone.png` on top. Separate closed/open envelope illustrations are not hinge-registered. Use a brief opacity/scale transition. Text on `letter_paper_blank.png` must be native SwiftUI text and may use a plain cream background if readability requires.

Do not modify the existing approved Warawara Rig. Keep v2 as a reversible fallback.

## QA
- Read ASSET_MANIFEST.json and verify SHA256 / alpha corners.
- Verify actual packaged macOS resources resolve.
- Compare real-app actual-size light and dark background frames.
- The artwork has not been through user's Mac visual acceptance.
