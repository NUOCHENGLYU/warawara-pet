# Warawara rig assets (Phase 5A)

This directory is the future home of the **layered character rig**. When
`manifest.json` is present the app renders the layered character (body +
eyes + mouth, limbs reserved); when absent the app logs that clearly and
continues with the single-sprite pipeline — no code changes needed to
activate the rig.

## Directory convention

```
Assets/WarawaraRig/
├── manifest.json
├── body/base.png
├── eyes/open.png
├── eyes/closed.png
└── mouth/{soft,neutral,relaxed,open,pressed,sleepy}.png
```

All layer images must share ONE canvas aspect (declare the canvas size in
`manifest.json`; the renderer scales by body height exactly like the
sprite pipeline). Transparent PNGs. Retina: provide >= 2x the logical
canvas.

> SwiftPM flattens resource subdirectories into the bundle root, so every
> filename must be unique across all rig folders (the loader tries the
> declared path and then the flat basename).

## manifest.json format

```json
{
  "version": 1,
  "canvas": [1024, 1024],
  "anchor": [0.5, 0.5],
  "bodyBounds": [[0.10, 0.09], [0.80, 0.82]],
  "layers": {
    "body":  { "kind": "body",  "images": { "base": "body/base.png" },
               "anchor": [0.5, 0.5] },
    "eyes":  { "kind": "eyes",  "images": { "open": "eyes/open.png",
               "closed": "eyes/closed.png" },
               "anchor": [0.5, 0.41], "gazeRange": [0.06, 0.03] },
    "mouth": { "kind": "mouth",
               "images": { "soft": "mouth/soft.png",
                           "neutral": "mouth/neutral.png",
                           "relaxed": "mouth/relaxed.png",
                           "open": "mouth/open.png",
                           "pressed": "mouth/pressed.png",
                           "sleepy": "mouth/sleepy.png" },
               "anchor": [0.5, 0.50] }
  },
  "optionalLayers": ["limbs"]
}
```

Rules:

- `version` must be 1; `canvas` width/height > 0; `anchor` and every layer
  anchor inside 0...1; `bodyBounds` inside the unit rect with positive
  size; a `body` layer is required.
- Layer dictionary keys must equal the layer `kind`.
- `images` maps roles to paths relative to this directory. Roles:
  - body: `base`
  - eyes: `open`, `closed` (single-image rigs degrade gracefully —
    missing role = no visual for that state, never a crash)
  - mouth: one entry per style: `soft`, `neutral`, `relaxed`, `open`,
    `pressed`, `sleepy`
  - limbs (reserved, next phase): to be defined
- `gazeRange` (eyes only, optional): maximum gaze offset as fractions of
  canvas width/height. The renderer offsets the eye layer by
  `gazeX * range.width * renderWidth` (continuous, eased).
- CG geometry uses CoreGraphics Codable array format: `CGPoint` =
  `[x, y]`, `CGSize` = `[w, h]`, `CGRect` = `[[x, y], [w, h]]` — object
  dictionaries are NOT accepted.

## Behavior the rig enables

The layered renderer consumes continuous performance parameters
(`WarawaraPerformanceParameters`) produced by the state -> parameter
mapper and eased by `WarawaraParameterAnimator`:

- eye openness crossfades `open`/`closed` continuously (blinks included)
- gaze offsets the eye layer smoothly (curious cursor following)
- mouth styles crossfade over ~0.22 s; `mouthOpenAmount` scales the shape
- body breathing scale, internal squash and lean are applied around the
  bodyBounds center

The state machine, drag/hop/float deformation and hit testing are
unchanged — the rig layers are composed INSIDE the existing character
view, under the same deformation pipeline.

## What is still needed for the next phase

1. User-approved layered artwork: body, eyes (open/closed) and the six
   mouth styles, all on a shared canvas.
2. Optional limbs layer (roles + anchor) once the limb phase lands.
