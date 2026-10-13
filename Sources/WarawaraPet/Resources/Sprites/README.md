# Sprite assets

Final artwork lives here (SPM-processed into the app bundle). The app
renders the procedural placeholder until real, user-approved artwork is
added.

## Manifest format

One optional JSON file at the bundle root:

```
sprites.json
{
  "version": 1,
  "layout": {
    "canvas": { "width": 200, "height": 226 },      // logical points
    "anchor": { "x": 0.5, "y": 0.5 },               // normalized, top-left origin
    "bodyBounds": { "x": 0.26, "y": 0.24, "width": 0.48, "height": 0.52 }  // normalized
  },
  "animations": {
    "idle": { "frames": ["idle/idle_00.png", "idle/idle_01.png"],
              "frameDuration": 0.5, "loop": true },
    "hop":  { "frames": ["hop/hop_00.png", ...], "frameDuration": 0.08, "loop": false },
    ...
  }
}
```

Animation keys used by the app (see `WarawaraAnimationMapper`):
`idle`, `hop`, `float`, `curious`, `clicked`, `dragged`, `settling`,
`sleepy`, `sleeping`, `wake`.

Frames are transparent PNGs. The loader decodes and caches images once;
missing or invalid assets fall back to the procedural placeholder — the
app never crashes on missing art.

## Asset rules

- No film frames, thumbnails, or unlicensed material may be committed or
  shipped. Reference material belongs only in a gitignored local folder
  (see `docs/art/WARAWARA_REFERENCE_SPEC.md`).
- Candidate artwork is labeled CANDIDATE until the user approves visual
  fidelity against the official stills.
