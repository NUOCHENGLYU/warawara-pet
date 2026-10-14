# Warawara rig assets (Phase 5B)

The layered character rig is **installed and active**. When the app
launches, `WarawaraRigLoader` loads `manifest.json` and the layered
renderer (body + eyes + mouth) takes over; `--verify-sprites` on the
packaged app must report `rig=loaded`. The Phase 4B single-sprite
pipeline remains the automatic fallback for missing/invalid rig
resources.

## Installed tree

```
Assets/WarawaraRig/
├── manifest.json
├── body/body_base.png
├── eyes/eyes_open.png   eyes_half.png  eyes_closed.png
│      eyes_focused.png  eyes_pressed.png
└── mouth/mouth_soft.png   mouth_neutral.png  mouth_relaxed.png
         mouth_open.png    mouth_pressed.png  mouth_sleepy.png
```

All 12 PNGs are the ChatGPT-supplied handoff layers
(`art_handoff/Warawara_Phase5A_Art_Handoff_v1/`), copied byte-for-byte
(SHA256SUMS verified), each a registered transparent 1024 × 1024 canvas.
`mouth_o_extra.png` is intentionally not installed (no role in the
current schema).

## manifest.json format (implemented contract)

```json
{
  "version": 1,
  "canvas": [1024, 1024],
  "anchor": [0.5, 0.5],
  "bodyBounds": [[0.10, 0.09], [0.80, 0.82]],
  "layers": {
    "body":  { "kind": "body",  "images": { "base": "body/body_base.png" },
               "anchor": [0.5, 0.5] },
    "eyes":  { "kind": "eyes",
               "images": { "open": "eyes/eyes_open.png",
                           "half": "eyes/eyes_half.png",
                           "closed": "eyes/eyes_closed.png",
                           "focused": "eyes/eyes_focused.png",
                           "pressed": "eyes/eyes_pressed.png" },
               "anchor": [0.5, 0.5], "gazeRange": [0.04, 0.02] },
    "mouth": { "kind": "mouth",
               "images": { "soft": "mouth/mouth_soft.png",
                           "neutral": "mouth/mouth_neutral.png",
                           "relaxed": "mouth/mouth_relaxed.png",
                           "open": "mouth/mouth_open.png",
                           "pressed": "mouth/mouth_pressed.png",
                           "sleepy": "mouth/mouth_sleepy.png" },
               "anchor": [0.5, 0.5], "pivot": [0.495, 0.510] }
  },
  "optionalLayers": ["limbs"]
}
```

Rules:

- `version` must be 1; `canvas` width/height > 0; all anchors inside
  0...1; `bodyBounds` inside the unit rect with positive size; a `body`
  layer is required; layer keys must equal the layer `kind`.
- CG geometry uses CoreGraphics Codable array format: `CGPoint` =
  `[x, y]`, `CGSize` = `[w, h]`, `CGRect` = `[[x, y], [w, h]]`.
- `anchor` is the REGISTRATION anchor. All handoff layers are registered
  to one full canvas, so positioning anchors are `[0.5, 0.5]` for every
  layer — layers are never re-centered from their alpha bounding boxes.
- `pivot` (optional): transform pivot for mouth width/height scaling
  (falls back to `anchor`). Mouth pivot = measured mouth center.
- `gazeRange` (eyes): maximum gaze offset as canvas fractions.
- SwiftPM flattens resource subdirectories into the bundle root; every
  filename must be unique across rig folders (the loader tries the
  declared path, then the flat basename).

## Continuous expression contract

The renderer consumes `WarawaraPerformanceParameters` (eased by
`WarawaraParameterAnimator`):

- eye openness crossfades open(1.0) <-> half(0.5) <-> closed(0.0)
  continuously; `focused` fades in with gaze magnitude (curious);
  `pressed` fades in with press amount (click).
- gaze offsets the eye layer within `gazeRange`, eased, never snapped.
- mouth styles crossfade (~0.18 s) and scale by `mouthOpenAmount` around
  the mouth pivot (width 1 + 0.10x, height 1 + 0.22x).
- body-level transforms (breath, squash, tilt) wrap ALL layers so the
  face stays registered to the deformed body.

## Future limb layer requirements (art not yet produced)

The body still contains the original painted arms/feet. A future
independent limb layer must provide, on the same 1024 canvas
registration:

- required filenames (roles to be finalized in the manifest when art
  arrives; the loader only requires unique basenames):
  e.g. `limbs/arm_left.png`, `limbs/arm_right.png`,
  `limbs/foot_left.png`, `limbs/foot_right.png`
- per-part pivot in the manifest (`pivot` key): shoulder pivots and foot
  pivots in normalized canvas units;
- layer order in the manifest: limbs rendered ABOVE body, BELOW eyes
  and mouth (the renderer stacks body -> eyes -> mouth; limbs will be
  inserted between body and eyes);
- deformation masks: the body revision used with limbs must have the
  painted arms/feet removed (clean silhouette) so rotated limbs do not
  duplicate or leak the original outline — do not overlay limbs on the
  current body until that mask revision exists.

Do not draw limbs procedurally in the app.
