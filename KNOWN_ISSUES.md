# Known Issues — Phase 3 freeze

Phase 3 (multi-Warawara group behavior) is **functionally accepted** and was
frozen at commit `eea4413` / tag `phase3-frozen`. The following imperfections
are intentionally deferred:

## Visual

1. **Companion top-edge exit — awaiting final real-Mac confirmation.**
   The exit was reworked several times. The current implementation hands the
   companion off to a screen-contained viewport panel whose top edge sits
   exactly at `visibleFrame.maxY`; the character rises inside the panel and
   is clipped by the panel's top edge (a geometric wipe, not a fade). All
   previous off-screen-panel approaches produced an abrupt disappearance on
   real hardware that CI could not reproduce. This viewport approach has not
   yet been re-tested on the M1 Air. If it still reads abruptly, do not add
   more boundary workarounds — revisit the clipping-container/coordinate
   assumptions instead.

2. **Group choreography timing.** Gather/hover/ascent timings are single
   defaults in `GroupTuning`; they have not been tuned against the final
   artwork scale and pacing.

3. **Companion entry edges.** Entry from the top edge is not implemented
   (left/right/bottom only, by design).

## Artwork

4. **All characters now use the installed neutral artwork (Phase 4B).**
   `warawara_neutral.png` is referenced by every state; motion comes from
   the pose pipeline. `WarawaraSpriteLoader.loadDefaultResources()` is
   called from app startup before the first render (AppDelegate); a
   failed load is logged via NSLog and the placeholder fallback is marked
   with a small amber badge — never a silent fallback. CI additionally
   runs the packaged `.app` binary with `--verify-sprites` to prove the
   release bundle resolves. The procedural placeholder blob remains only
   as the fallback for missing/invalid assets, and the Phase 4A candidate
   frames are kept on disk for rollback (see
   `Sources/WarawaraPet/Resources/Sprites/README.md`).

5. **Drag deformation envelope: worst-case corner overshoot.**
   The neutral artwork's body (≈115 pt wide × 118 pt tall) is wider than
   the Phase 1.6 placeholder (96 × 118) the deformation tuning was
   verified against. Phase 5C firmed the drag feel (maxStretch 0.35 →
   0.24, velocity at max stretch 600 → 800 pt/s, slightly quicker release
   spring), which also shrinks the theoretical extreme-corner overshoot
   to a few points. All normal-range deformation stays fully inside the
   window; revisit only if real-Mac testing shows visible clipping.

6. **Phase 5B layered rig is active; limb art still pending.**
   The layered character system (continuous performance parameters,
   state->parameter mapper, easing animator, body/eyes/mouth renderer,
   rig loader) is implemented, tested, and now ACTIVE with the
   ChatGPT-supplied rig assets (Assets/WarawaraRig, 12 registered
   1024x1024 layers; --verify-sprites reports rig=loaded). Phase 5D fixed
   the blink/gaze rendering defects: blink is now a fast unsmoothed
   channel composed at render time (full closure guaranteed), eye-layer
   composition uses normalized mutually-exclusive weights (no additive
   double eyes), and curious gaze is a coordinated head-turn hierarchy
   (Phase 5E): body silhouette bias -> shared face-group lead -> minimal
   eye-local gaze -> whole-group lean/squash, with a single documented
   Y-up parameter convention converted to screen space exactly once.
   Remaining limitations: the blink schedule is a
   deterministic two-period pattern awaiting real tuning; independent
   limb artwork (with shoulder/foot pivots and a masked body revision)
   is required before limbs can animate without duplicating the painted
   arms/feet — see the rig README for the exact contract.

## Platform

5. **NSMenu is intentionally absent.** An unresolved AppKit interaction
   hides the nonactivating pet panel whenever any NSMenu closes on real
   hardware. The quit control is a direct-click menu-bar status button.
   Do not reintroduce menus without a real-Mac fix.
