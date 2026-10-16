# Warawara Birthday CelFilm v5 — art handoff

## Status
Original inspired-by-animation foreground prop artwork. Not a Studio Ghibli official asset set. This is a **candidate** for the real application; final M1 Air validation remains necessary.

## Main files (names match birthday engine)
- `cake_lit.png`: handmade cake, candle flame baked in. NEVER overlay an extra flame.
- `envelope_closed.png`, `envelope_open.png`: aligned canvas (1024×1024), near-identical envelope width, bottom-aligned. Both share **one extracted wax stamp** as source; opened variant splits it mechanically, preserving the source pigment and stamp footprint. Do not separately regenerate the stamps.
- `letter_paper_blank.png`: blank neutral cream letter paper; UTF-8 letter content must remain in existing birthday_letter.txt resource.
- `sparkle_gold_star.png`, `sparkle_gold_large.png`, `sparkle_gold_lower.png`: previous pack, optional, visually provisional.

## New optional carry helpers
- `cake_tray.png`: a simple natural wooden tray to be carried by a lead companion; put cake above the tray with proper occlusion.
- `birthday_hat.png`: small simple hat, OPTIONAL; must not replace existing character Rig.
- `wax_seal_master.png`: reference exact shared seal source; don't render it ON TOP of existing full stamped envelope again.

## Crucial carrying composition
Layer order while carrying cake: companion back/body → cake tray at front-middle → cake at front → accepted companion arm/hand portion (using current Rig, if possible) as front occluder. Do not just center the whole cake PNG on companion as a sticker. Have a 1–2 s soft handoff to a floor-fixed position.
For letter: optional pocket/half-occlusion using current Rig and rig's body part; prefer real existing arms rather than inventing extra prop graphics. The envelope must be visibly held between pet and its arm/side or supported on a companion-sized tray, not pasted to face/torso.

## Coordinates and resource engineering
All primary PNG are transparent square 1024×1024; actual painted content occupies an inset area. Preserve aspect ratio and use alpha/content bounding box for anchor positioning, NOT the raw pixel canvas bounds. Recommended display sizes in manifest are initial guesses, not fixed rules. Local actor states should drive position and object ownership.
Don't replace existing Warawara character, renderer, or artwork. Only copy real candidate prop PNGs to SwiftPM app resource bundle, update expected SHA256 values, regenerate preview and tests. Run `--verify-birthday` and inspect actual Mac 2× rendering. Closing the letter must never close the main pet panel.

## Delivery
Keep this pack in `art_handoff/Warawara_Birthday_CelFilm_v5/` at repo root. Do not overwrite old art folders until acceptance. Do not ship the preview as a production sprite.
