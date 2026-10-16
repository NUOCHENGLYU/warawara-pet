# Warawara Seasonal & Daily CelFilm v1 — OpenCode Handoff

## Scope
12 original event prop PNG assets (1024x1024 RGBA) are included in `assets/`. They are **not** replacement Warawara characters. They follow the same hand-painted cel-animation foreground-prop look as the user's accepted birthday CelFilm v5 art, but require real-Mac scale/visual acceptance.

### Install
Unpack this directory under `<repo>/art_handoff/Warawara_Seasonal_Daily_CelFilm_v1/`.
Read `ASSET_MANIFEST.json` and `EVENT_TIMING_AND_STORY_SPEC.md`. Copy only needed event assets into the SwiftPM production bundle, grouped by seasonal/daily category; do not copy this handoff folder verbatim into production code or include QA preview JPGs.

### Constraints
- Never redraw/replace the accepted Warawara Phase 5 layered Rig.
- Do not regress Birthday v5 artwork, triggering, manual replay, letter retirement / reopening.
- All sprite SHA256 hashes are recorded in manifest and should be tested against the packaged `.app`.
- All images are on 1024 transparent square canvases; use alpha-content bounds for apparent size and contact alignment.
- `cny_firecracker_hanging.png` is a stationary **decorative string**. No sound or explosion.
- `daily_umbrella.png` is an imaginary daily event. Do NOT infer real rain without actual weather data; fully offline.
- `newyear_calendar_jan1.png` shows only the day number "1", and is future-year-safe.
- All event appearances are ephemeral and should not leave click-blocking props on desktop.
- No surprise full screen windows; no NSMenu; direct-click status item Quit remains mandatory.
- *Art status:* candidate for testing; full actual-app event and scale still require M1 approval.

### QA
`PREVIEW_LIGHT.jpg`, `PREVIEW_DARK.jpg`, `PREVIEW_WITH_WARAWARA.jpg` are visual QA compositions, not production sprites nor screenshots from the app.
