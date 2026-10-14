# Warawara Phase 5F — Light 2.5D Turn: Art/Engineering Handoff v1

## Purpose
The user approved the Phase 5E character and wants a subtle **out-of-screen-plane (3D-like)** body turn toward the cursor, approximately ±20° to ±30° yaw, with mild pitch. The existing Phase 5E character at zero yaw must look **pixel-identical** to the accepted frontal neutral.

## Contents
- `references/neutral_approved_phase4b.png`: the accepted 1024×1024 flat neutral, authoritative appearance at yaw=0.
- `references/body_base_approved_current.png`: approved front body-only layer, useful to confirm the current Rig's original artwork; no new facial pixels.
- `references/yaw_left_approx25_reference_only.png` and `references/yaw_right_approx25_reference_only.png`: normalized transparent full-character **visual guides** for light yaw. The left guide is a horizontal mirror of the right guide to avoid mismatched shape/style between independent generations. Sizes are 1024×1024, visually centered to neutral, but ARE NOT geometrically registered runtime layers.
- `PREVIEW_3_ANGLES.png`: on-gray comparison of the three orientations.
- `SHA256SUMS.json`: hashes of the included PNGs.

## Crucial qualification
These two side-view reference images are **NOT approved production Rig assets**. They contain baked-in eyes/mouth, somewhat different proportions, and hand-illustrated perspective. Never insert them as the Rig body, never place them behind or in front of the existing face layers, and never crossfade full-body images to simulate yaw (would produce ghost eyes/edge double-exposure and PPT-like flips).

They define visual intent: far eye becomes perceptually narrower, near eye becomes more dominant, facial features follow the curved front surface, head/body volume turns together, tiny arms and silhouette subtly reflect the orientation; pitch should simulate looking slightly up/down. Maintain consistent texture/shading and proportions of the **existing real app artwork**, not the alternative design details in these generated references.

## Continuous implementation guidance
1. Preserve the accepted front when `yaw=0, pitch=0`; neutral art and existing face behavior should be unchanged.
2. Derive yaw from the stationary cursor's relative horizontal position in the same canonical screen coordinate system already fixed in Phase 5E; maintain gaze as long as Curious stays active.
3. Apply an actual 2.5D depth *illusion*, not a screen-Z roll. Gradually vary silhouette/side width, facial perspective spacing (including near/far asymmetry), nose-less face curvature, arm occlusion/size and subtle shading with yaw. Same concept for small pitch up/down.
4. Use a stable image-mesh/deformation model (or a justified simpler 2.5D approximation) with numerical continuity. Do not replace existing normal sprites, blink/eye weights, mouse hold tracking, rig loading, scene/controller states, or accepted soft-body drag.
5. Keep all face transformations in a single consistent local coordinate space. A tiny secondary local eye gaze may supplement the 3D-like body turn, but never dominate it.
6. No external runtime image generation, server, network dependency, or additional third-party packages merely for turning.
7. If continuous silhouette and occlusion cannot be delivered credibly by existing layers/geometry, report a precise additional **body-only** art specification. Do not quietly substitute the complete side-guide PNGs.

## Intended visual acceptance
- Mouse at right: creature *turns its volume* gently toward right, with asymmetric facial perspective. Not just flat 2D clockwise/counterclockwise rotation.
- Mouse at left: mirror response.
- Mouse above/below: very subtle head-up/head-down illusion, correct Y direction.
- Mouse stationary: no drifting or ghost images, holds pose.
- Cursor moves away: eased natural return.
- Normal idle / other animations: Phase 5E remains identical.
- At desktop size, turning should be visible but soft, without distracting squash or warped character identity.

## Process
Develop and test on a separate Phase 5F working branch created from the inspected current Phase 5E tip; DO NOT merge into main until real M1 acceptance. Keep the existing stable app build available. Provide timestamped contact sheets and CI artifacts. Don't claim the user accepted art or real-Mac appearance without inspection.
