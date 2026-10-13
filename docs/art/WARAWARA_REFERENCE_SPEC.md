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

## Candidate sprite palette (procedural, for verification)

- Body: near-white gradient #FDFDFF → #D5DAE8 with a subtle cool
  bottom shading (#A8B0C6 at low alpha) and a soft gray outline.
- Eyes: near-black #1A1A1E.
- Mouth: soft pink #E2848A.
- Canvas 200 × 226 logical (400 × 452 px), body 96 × 118, anchor (0.5, 0.5),
  bodyBounds (0.26, 0.239, 0.48, 0.522) — identical geometry to the
  procedural placeholder.

## Review checklist — TO VERIFY by the user against the references

Each item is an ASSUMPTION of the current candidate until checked:

- [ ] Silhouette: simple rounded plump blob (no limbs drawn in the
      candidate — arm/foot shapes are currently **UNKNOWN** and omitted)
- [ ] Proportions: body 96 × 118 logical vs the still
- [ ] Eye shape/size/position: small dark ovals, spacing 34, placed in the
      upper-middle (assumption)
- [ ] Mouth: tiny pink oval at (0, +26) below center (assumption)
- [ ] Outlines and shading: soft gray outline + bottom shading (assumption)
- [ ] Individual variation: the candidate set varies only body size per
      frame; film variation across characters is unmodeled

## Explicit unknowns (not to be invented)

- Arm and foot shapes (whether Warawara show them in the principal still).
- Exact eye geometry (angle, aspect ratio).
- Exact mouth shape and color.
- Any sleeping/expression variants in the film.

Until the user completes the checklist, all artwork in this project is
labeled **CANDIDATE — awaiting visual approval**.
