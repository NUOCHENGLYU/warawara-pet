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

4. **All characters still use the procedural placeholder blob.** Phase 4
   introduces the sprite asset pipeline and faithful-artwork candidates.
   Until the user visually approves real artwork, the placeholder remains
   the shipped look.

## Platform

5. **NSMenu is intentionally absent.** An unresolved AppKit interaction
   hides the nonactivating pet panel whenever any NSMenu closes on real
   hardware. The quit control is a direct-click menu-bar status button.
   Do not reintroduce menus without a real-Mac fix.
