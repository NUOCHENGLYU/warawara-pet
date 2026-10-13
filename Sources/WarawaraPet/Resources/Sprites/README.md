# Sprite assets

## Current contents

### Phase 4B: ChatGPT-provided neutral artwork (installed, awaiting user visual approval)

`warawara_neutral.png` (1024 × 1024, transparent) from
`art_handoff/Warawara_Art_Handoff_v1/` is installed byte-for-byte and is
referenced by **every** state in `sprites.json`. Motion for each state
comes from the existing pose/deformation pipeline (hop squash/stretch,
float, drag deformation, breathing scale, sleep squash), not from
distinct artwork. The manifest layout is:

- canvas `[1024, 1024]`, anchor `[0.5, 0.5]`,
  bodyBounds `[[0.10, 0.09], [0.80, 0.82]]`
  (measured from the PNG's opaque pixels + small margin).

### Rollback: Phase 4A candidate frames

The Phase 4A procedural frames remain on disk under `idle/`, `hop/`,
`float/`, `curious/`, `clicked/`, `dragged/`, `settling/`, `sleepy/`,
`sleeping/`, `wake/` and can be restored with:

```
git checkout 8f58845 -- Sources/WarawaraPet/Resources/Sprites/sprites.json
```

Replace any of these with hand-corrected, user-approved frames by
dropping new PNGs here and editing `sprites.json` — no Swift changes.

## Manifest format

One JSON file at the bundle root:

```
sprites.json
{
  "version": 1,
  "layout": {
    "canvas": [200, 226],      // logical points
    "anchor": [0.5, 0.5],               // normalized, top-left origin
    "bodyBounds": [[0.26, 0.24], [0.48, 0.52]]  // normalized
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

Subdirectory paths in `frames` (e.g. `idle/idle_00.png`) match the source
tree here. SwiftPM flattens resource subdirectories when it copies files
into the app bundle, so the loader also tries the file's basename
(`idle_00.png`) — keep filenames unique across directories.

## Asset rules

- No film frames, thumbnails, or unlicensed material may be committed or
  shipped. Reference material belongs only in a gitignored local folder
  (see `docs/art/WARAWARA_REFERENCE_SPEC.md`).
- Candidate artwork is labeled CANDIDATE until the user approves visual
  fidelity against the official stills.
