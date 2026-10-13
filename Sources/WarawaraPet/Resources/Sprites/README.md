# Sprite assets

## Current contents: CANDIDATE assets (awaiting visual approval)

The PNGs and `sprites.json` currently committed here are **procedurally
generated candidate artwork** (originally created, not traced, not
downloaded). They exist to exercise the sprite pipeline end-to-end and
for visual review — they make NO claim of film fidelity and must not be
shipped as final artwork without the user's approval.

Regenerate the candidates (Windows):

```
powershell -ExecutionPolicy Bypass -File Scripts\generate-candidate-sprites.ps1
```

Replace them with hand-corrected, user-approved frames at any time by
dropping new PNGs here and editing `sprites.json` — no Swift changes.

## Manifest format

One JSON file at the bundle root:

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
