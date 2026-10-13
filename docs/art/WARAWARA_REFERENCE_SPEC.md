# Warawara Reference Specification — The Boy and the Heron (2023)

**Status: CANDIDATE references. Visual fidelity is NOT accepted until the
user completes the review checklist below against the referenced stills.**

## Verified sources

- **PRIMARY (user-verified):** official Studio Ghibli film still
  <https://www.ghibli.jp/gallery/kimitachi007.jpg>
  (official source page: <https://www.ghibli.jp/works/kimitachi/>)
- **SECONDARY (user-verified):** Warawara floating scene clip
  <https://tenor.com/view/warawara-the-boy-and-the-heron-wara-wara-studio-ghibli-gif-16810839560147500943>
- Studio Ghibli's official still-distribution notice:
  <https://www.ghibli.jp/info/013772/> — dated 2023-08-18, with the usage
  note 「常識の範囲でご自由にお使いください」 ("Please use them freely
  within the scope of common sense").

A local copy of the primary still is kept for reference only at
`research/kimitachi007.jpg` (gitignored — **never committed, never
bundled into the app**).

## Objective measurements from the primary still (machine-made, 2026-10)

These are measurements, not aesthetic claims:

- Image size: 1920 × 1038 px.
- Sampled color histogram is dominated by mid-grays (RGB ≈ 160,160,160);
  **no sampled pixel is brighter than RGB 200**. The still is muted/graded;
  the character reads as light gray rather than pure white in this frame.
- Dark pixels (< 80 luminance) ≈ 16 % of the sample — consistent with dark
  eyes and shaded background areas.

### Region segmentation pass (2026-10-13, `Scripts/analyze-warawara-regions.ps1`)

The still is a crowded night ascent; connected components merge
neighboring bodies, so individual measurements are noisy:

- Bright (lum ≥ 168) components are dominated by merged pairs/groups:
  bboxes of 180–260 px tall, fill 0.55–0.72 (oval-ish, not rectangles).
- A vertical stack of bodies (bbox `(0,663) 98×289`) suggests an
  individual body is roughly **90–100 px wide and tall** in this still →
  body aspect ≈ **1.0** (roundish/plump, not a slim oval).
- Enclosed dark holes (candidate eyes) inside bright bodies have areas
  ≈ 10–370 px on bodies of ≈ 90 px → eye diameter ≈ **15–25 % of body
  width** when the hole is a single eye; several clean holes land in the
  **lower-middle of the face (rel Y ≈ 0.35–0.55 of merged bboxes)**.
- Faces are turned at varied angles (floating/rotating), so exact eye
  spacing and mouth geometry could not be measured reliably from this
  still. Arms and feet are not measurable here (crowded floating shot).

## Phase 4A neutral sprite — design decisions (2026-10-13)

The neutral sprite (`idle/idle_00.png`, `idle_01.png` breathing,
`sleeping/sleeping_00.png` closed eyes) replaces the old symmetric oval
candidate. Changes made, each mapped to evidence:

| Feature | Previous oval candidate | Phase 4A candidate |
| --- | --- | --- |
| Silhouette | symmetric ellipse, no limbs | asymmetric egg (widest at ~55 % height, soft flat bottom, gentle top); body 172 × 192 px on the 400 × 452 canvas |
| Arms / feet | none (unknown) | small stubby side arms + tiny feet peeking below (from film design; NOT measurable in the still — assumption) |
| Eyes | small ovals at upper-middle, spacing 34 pt | round near-black dots, Ø 30 px (17 % of body width), centers 56 px apart, at 60 % of body height (below midline — matches hole measurements) |
| Mouth | tiny pink oval below center | small dark smile curve 24 px wide (from film design; exact shape unmeasurable — assumption) |
| Shading | flat gradient + gray outline | warm white base, cool bottom crescent, right-side soft shadow, top-left highlight, soft contour (Ghibli-style soft cel) |
| Palette | #FDFDFF → #D5DAE8, pink mouth | body #FCFAF6 → #F0F0F4 with #D6DAE6 → #BEC2D6 shadows; eyes #1C1C24; mouth #40404C |

The still is night-graded (no pixel brighter than RGB 200), so the
sprite's warm white is based on the character's daylight film look, not
on still pixel colors.

## Review checklist — Phase 4A neutral sprite (TO VERIFY by the user)

Each item is an ASSUMPTION of the Phase 4A candidate until checked:

- [ ] Silhouette: asymmetric egg with soft flat bottom; widest at ~55 %
      height
- [ ] Arms: small stubby side nubs (size/position — assumption)
- [ ] Feet: tiny feet peeking below the body (shape — assumption)
- [ ] Eyes: round dots Ø 17 % of body width, 56 px apart, at 60 % of
      body height (below midline)
- [ ] Mouth: small dark smile curve (exact shape — assumption)
- [ ] Shading: warm white + cool bottom crescent + soft contour
- [ ] Breathing pair: subtle squash between idle_00 / idle_01
- [ ] Sleeping variant: closed-eye arcs

## Explicit unknowns (not to be invented)

- Exact arm and foot shapes (unmeasurable in the floating crowd still).
- Exact eye spacing, eye size and vertical placement (noise from face
  angles in the still).
- Exact mouth shape and color (too small to segment reliably).
- Sleeping/expression variants in the film (drawn from general film
  knowledge only).

Until the user completes the checklist, all artwork in this project is
labeled **CANDIDATE — awaiting visual approval**.
