# Warawara Phase 5A — exact-base layered artwork handoff v1

## Source / visual basis
All layers are based on the Phase 4B real-Mac-approved `warawara_neutral_1024.png`. This is not an independent new redesign. The neutral body is the approved artwork with ONLY its original eyes/mouth removed by local color-field reconstruction. Eye and neutral mouth masks are separated from the original. Expressions are bounded, registration-preserving derivative shapes for Phase 5A experimentation. No official movie frame is included.

## Canvas and mapping
Every `assets/*.png` is a **true-transparent 1024×1024 RGBA PNG** with identical global registration, not tightly cropped. Pixel origin TOP LEFT. Body, eyes, mouth must render in the same full canvas coordinate system without independently recentering/trimming. Do not use image bounding rectangles to automatically center eyes/mouth on top of body.

Canonical anchor and bodyBounds: take existing approved Phase 4B `sprites.json` metadata (do NOT replace with guesses). The source body shape and canvas stay unchanged. `asset_registration.json` records measured face centers as validation references.

Required rig assets:
- `body_base.png` = entire body with no facial marks.
- `eyes_open.png` and `eyes_closed.png` = rig's mandatory open/closed.
- `mouth_soft.png`, `mouth_neutral.png`, `mouth_relaxed.png`, `mouth_open.png`, `mouth_pressed.png`, `mouth_sleepy.png` = mouth variants.
Optional:
- `eyes_half.png`, `eyes_focused.png`, `eyes_pressed.png`, `mouth_o_extra.png` = future expression layers / pressed eyes support, not necessarily required by current rig schema.

**IMPORTANT** SwiftPM resource flattening: filenames are globally unique (e.g. `eyes_open.png`, `mouth_open.png`). Copy into the project's Assets/WarawaraRig tree using the EXACT names your rig manifest and loader require; map these names explicitly in the actual JSON manifest. The current code's rig schema wins if it requires additional keys/normalizations. Do not assume the example here is a valid in-app rig manifest.

## Integration guardrails
- Phase 4B is accepted and must remain rollback-safe. Implement on Phase 5 branch only; leave `main` and stable tags unchanged.
- Compare `PREVIEW_OLD_VS_RECOMPOSED.png` to approved full artwork; no jump in default idle when rig activates.
- Rig idle = (body_base + eyes_open + mouth_neutral), not stacked over the already facially painted full sprite.
- Confirm `--verify-sprites` reports rig=present, NOT `rig=absent`.
- Source body must maintain same apparent center, transparency, body bounds, and hit region as Phase 4B.
- Eyes should animate `eyeOpenness` continuously; half, focused, pressed layers may be used only if schema supports them, otherwise synthesize continuous animation without hard sprite snapping.
- Mouth crossfades may exhibit ghosting; prefer geometry-aware scaling and easing, avoid simultaneous opaque mouths persisting for too long.
- Note `mouth_open` is a taller version of the neutral mouth for first rig pass; do not assume detailed facial animation is accepted without user review.
- Do NOT overwrite approved main sprite or redraw new artwork procedurally.
- For future limbs, separate limbs from body with a clean revision so rotation does not create duplicated or leaking outline; the body at this stage STILL CONTAINS THE ORIGINAL ARMS/FEET. Avoid rendering detached hands/feet above it until masking completed.

## Deliverable previews
- `PREVIEW_OLD_VS_RECOMPOSED.png`: approved neutral vs rebuilt neutral.
- `PREVIEW_6_EXPRESSIONS.png`: neutral, curious, drowsy, sleep, pressed, delighted.
- `asset_registration.json`: centers and file list.

## Test instructions
Implement rig loading in the app, add art-preview CI using real layers, and verify 1024/1024 alpha, coordinate registration, PNG decoding, and no fallthrough on main/companions. Preserve the Phase 4B sprite fallback, do not touch accepted state machine.
