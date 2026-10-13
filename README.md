# WarawaraPet

A tiny native macOS desktop-pet application (private birthday gift, not for
public distribution). The pet is a Warawara-like character that lives in a
transparent, borderless floating window above the desktop.

**Current status: Phase 4 — faithful Warawara artwork (candidate branch;
placeholder art remains the default).**

What exists today:

- accessory app (no Dock icon), transparent borderless non-activating panel
  that can never become key/main — clicks never steal keyboard focus
- procedural placeholder pet (blob + eyes — NOT the final artwork)
- gentle idle bob, randomized hops with squash/stretch
- soft floats: slow lift, sustained hover with bob/sway, slow descent
- curiosity: subtle lean/stretch toward a lingering cursor
- sleep: sleepy after inactivity, sleeping with breathing and a tiny Z
- click reaction (squash + rebound); quit via a single click on the
  menu-bar quit button
- mouse dragging with soft-body-style deformation (Phase 1.6, M1-verified)
- position clamping inside the visible screen area (menu bar/Dock excluded),
  multi-display aware, re-clamps on display changes
- window position persisted across launches (falls back to a safe default if
  the saved display no longer exists)
- tight elliptical hit region around the pet body
- `.stationary` collection behavior so the pet stays visible during Show
  Desktop / Mission Control
- **Phase 3 (frozen, functionally accepted):** a manually triggered
  companion group sequence — 3–5 temporary non-interactive Warawara enter
  from outside the display, gather with spring inertia, hover, ascend
  along individual fan-out paths, exit through a screen-contained
  top-edge viewport, and park off-screen (panels pooled, never closed)
- **Phase 4 (in progress):** a production sprite asset pipeline
  (`WarawaraSpriteManifest` / `WarawaraSpriteLoader` /
  `WarawaraCharacterView`) that renders transparent PNG sprite frames for
  every pet state with the procedural placeholder as the automatic
  fallback; CI generates a `WarawaraPet-Art-Preview` artifact with
  contact sheets for offline review

No group randomness in the scheduler yet, no birthday behavior, no final
artwork, no sound, no network, no NSMenu (menu-bar quit is a direct
button), no third-party dependencies.

---

## Developing from Windows

You cannot build or run this app on Windows — it depends on AppKit/SwiftUI.
That is by design. The Windows workflow is:

1. Edit Swift / YAML / shell files in any editor. (`.gitattributes` enforces
   LF line endings so shell scripts survive Windows CRLF.)
2. Commit and push to GitHub.
3. GitHub Actions builds, tests, and packages the app automatically
   (`.github/workflows/ci.yml`, runs on `macos-15`).
4. Download the finished app from the Actions page:
   **Actions → latest run → Artifacts → `WarawaraPet-macOS`** (a zip,
   kept for 30 days).

Local checks you *can* run on Windows:

```powershell
# Verify the Info.plist is well-formed XML
[xml](Get-Content Support\Info.plist); "plist OK"

# Verify the packaging script syntax (requires Git Bash)
& "C:\Program Files\Git\bin\bash.exe" -n Scripts\package-app.sh; "script OK"
```

Build/test correctness can only be verified by CI on macOS. Do not assume
macOS UI behavior works until it has been observed on a real Mac.

## Running on a Mac (tester)

1. Download the `WarawaraPet-macOS` artifact from GitHub Actions.
2. Unzip it.
3. The app is ad-hoc signed (unsigned). Remove the quarantine flag, then
   double-click:

   ```bash
   xattr -dr com.apple.quarantine WarawaraPet.app
   open WarawaraPet.app
   ```

   If macOS still blocks it: System Settings → Privacy & Security →
   "Open Anyway".
4. The pet appears near the bottom-right of the main display (or where it
   was last left). Click it, drag it around, watch it hop. To quit, click
   the **menu-bar quit button** (ⓧ icon) once — the app exits immediately
   with no menu. Right-clicking the pet does nothing.

## Running from source on a Mac

```bash
swift build                # debug build
swift run WarawaraPet      # launch (no .app bundle — development only)
swift test                 # unit tests
open Package.swift         # optional: open in Xcode
```

Release build + packaging (mirrors CI):

```bash
swift build -c release --arch arm64 --arch x86_64
bash Scripts/package-app.sh   # produces dist/WarawaraPet.zip
```

## Requirements

- macOS 13 or newer
- Apple Silicon and Intel (CI builds a universal binary)

## Project layout

```
Package.swift                 Swift Package Manager (repo root = package root)
Support/Info.plist            app bundle template
Sources/WarawaraPet/
  App/                        entry point + AppDelegate
  Models/                     pet state machine (PetState, HopParameters)
  Pet/                        panel, window/motion/interaction controllers
  Animation/                  pure motion curves (hop, settle)
  UI/                         SwiftUI placeholder pet rendering
  Support/                    pure testable helpers (frame math, screens,
                              hit region, randomness, position store)
Tests/WarawaraPetTests/       unit tests (run on CI via swift test)
Scripts/package-app.sh        assembles, ad-hoc signs, and zips the .app
Resources/Sprites/            future sprite frames (see its README)
.github/workflows/ci.yml      macOS CI: build → test → package → artifact
```

## Threading model

All window mutations, state transitions, and SwiftUI pose updates happen on
the main thread (main-run-loop timers, main-queue dispatch). The idle hop
scheduler uses a single timer that is cancelled whenever the pet leaves the
idle state, so no motion ever runs concurrently.

## Drag deformation tuning

All constants live in `DeformationTuning.default`
(`Sources/WarawaraPet/Models/PetPose.swift`) and are tuned on a real Mac:

| Constant | Default | Meaning |
|---|---|---|
| `velocityTimeConstant` | 0.12 s | drag velocity smoothing |
| `maxGapDuration` | 1.0 s | event gaps longer than this decay velocity |
| `velocityAtMaxStretch` | 600 pt/s | speed for full stretch |
| `minimumSpeed` | 20 pt/s | speeds below this deform nothing |
| `maxStretch` | 0.35 | stretch along the drag axis |
| `maxRotation` | 0.12 rad | torque rotation cap |
| `rotationGain` | 0.0005 | torque → rotation gain |
| `grabAnchorLimit` | 0.84 | grab anchor clamp (UnitPoint 0.08…0.92) |
| `decayStartDelay` | 0.05 s | pause before held-still relaxation starts |
| `releaseSpringResponse` / `releaseSpringDamping` | 0.3 s / 0.45 | release return to neutral |

## Personality tuning (Phase 2)

All Phase 2 constants live in `PersonalityTuning.default`
(`Sources/WarawaraPet/Models/PersonalityTuning.swift`) and are tuned on a
real Mac. Key defaults:

| Constant | Default | Meaning |
|---|---|---|
| `curiosityEnterRadius` / `curiosityExitRadius` | 110 / 170 pt | hysteresis band for noticing the cursor |
| `curiosityDwellTime` | 1.2 s | cursor must linger before engaging |
| `curiosityTrackingInterval` | 1/30 s | visual-tracking cadence (only while curious; raise to 1/60 if needed) |
| `floatChance` | 0.75 (temporary) | probability of a float at each eligible fire |
| `floatCooldownMin` / `floatCooldownMax` | 20 / 35 s (temporary) | random cooldown between floats; hops continue meanwhile |
| `floatDuration` | 6.5 s | full lift/hover/descent/settle cycle |
| `floatLiftFraction` / `floatHoverFraction` / `floatDescentFraction` | 0.29 / 0.43 / 0.25 | phase split (~1.9 s / ~2.8 s / ~1.6 s) |
| `floatHeight` | 145 pt | hover height |
| `floatBobAmplitude` / `floatBobPeriod` | 16 pt / 2.2 s | low-frequency hover bob |
| `floatSwayAmplitude` / `floatSwayPeriod` | 45 pt / 3.5 s | slow horizontal sway |
| `floatHorizontalDrift` | 25 pt | slow smooth drift |
| `floatBodyStretch` / `floatSwayLean` | 0.06 / 0.03 | low-amplitude body deformation |
| `hopMinDelay` / `hopMaxDelay` | 6 / 14 s | hop cadence |
| `sleepyTimeout` | 240 s | system inactivity before sleepy |
| `sleepTimeout` | 480 s | before sleeping |
| `breathingPeriod` | 4 s | sleep breathing |
| `wakeTransitionDuration` | 0.3 s | wake spring response |
| `awarenessTickInterval` | 0.15 s | curiosity/inactivity sampling |

For quick sleep testing set `sleepyTimeout = 15` and `sleepTimeout = 30`.

## Phase 3 group sequence (test trigger)

The companion group sequence is manually triggered only (not part of the
random scheduler yet). To trigger one sequence at the next launch:

```bash
defaults write com.birthday.warawarapet warawarapet.forceGroupOnce -bool true
```

Then launch the app. The flag is consumed automatically: the app waits
2–4 seconds, runs one group sequence, and resets the flag so normal
launches are unaffected.

Phase 3 real-Mac checklist:

- [ ] companions start fully OUTSIDE the display and enter by physically
      crossing the screen boundary (left/right/bottom edges), staggered
- [ ] entry motion is soft and inertial, no teleporting, no opacity-only
      appearance
- [ ] gathering is smooth and eased; companions end up loosely grouped,
      not on one point
- [ ] companions do not move identically (different scale/bob/drift)
- [ ] hover looks organic (2–4 s, gentle bobbing)
- [ ] ascent is slow and soft; near the top each companion slows to a
      staged crossing — upper body, then half, then the last visible
      portion slides out of view — and only then disappears, independently
- [ ] companions visibly stretch/lean while moving and relax smoothly
      when stopping (moderate, softer than the main pet's drag)
- [ ] companion bodies never appear clipped while moving or deformed
- [ ] all companion windows are parked/gone after the sequence (zero
      visible leftovers)
- [ ] the main pet NEVER disappears during or after the sequence and
      resumes normal idle behavior after
- [ ] clicking the main pet during any phase cancels the sequence
      immediately with no orphan windows and no pet disappearance
- [ ] dragging the main pet during any phase cancels the sequence
      immediately
- [ ] fast vertical/horizontal drags never clip the pet's bottom silhouette
- [ ] keyboard focus remains with the previously active app
- [ ] Show Desktop still works
- [ ] menu-bar quit button still exits immediately

## Sprite asset pipeline (Phase 4)

Final artwork is added without code changes:

1. Drop transparent PNG frames into
   `Sources/WarawaraPet/Resources/Sprites/<animation>/`.
2. Create `sprites.json` at the bundle root (see the manifest format in
   `Sources/WarawaraPet/Resources/Sprites/README.md`): canvas, anchor,
   body bounds, and per-animation frame lists with durations and looping.
3. Rebuild — `WarawaraCharacterView` renders the sprites for the main pet
   and companions; missing or invalid assets fall back to the procedural
   placeholder automatically.

Animation keys: `idle`, `hop`, `float`, `curious`, `clicked`, `dragged`,
`settling`, `sleepy`, `sleeping`, `wake` (see `WarawaraAnimationMapper`).

Artwork fidelity rules: the film design is the sole authority. See
`docs/art/WARAWARA_REFERENCE_SPEC.md` for the official reference sources
and review checklist. No film frames may be committed or shipped; all
candidates must be originally created and visually approved by the user.
CI contact sheets: Actions → latest run → `WarawaraPet-Art-Preview`.

## Signing and notarization (future)

The artifact is currently ad-hoc signed (`codesign --sign -`), which is
enough for a private tester after removing quarantine. To distribute more
broadly later: add a Developer ID certificate as a GitHub Actions secret,
sign with `codesign --options runtime`, staple, and notarize with
`notarytool`. No secrets are stored in this repository.

## Verification status

| Verified by | Items |
|---|---|
| Windows (static) | plist XML, shell syntax, line endings |
| macOS CI | universal compile, all unit tests, packaging |
| Real Mac only | everything below — none of it is verified yet |

## Manual test checklist (real Mac, to be completed)

- [ ] app launches without crashing
- [ ] transparent background, no title bar
- [ ] placeholder pet is visible
- [ ] idle bob is gentle and continuous
- [ ] pet hops on its own every ~6–14 s, with stretch/squash
- [ ] clicking squashes and rebounds the pet
- [ ] FIRST click on the pet reacts immediately while another app is active
- [ ] clicking/dragging never removes the text cursor or keyboard focus from
      the active app; typing keeps going to that app
- [ ] dragging moves the pet; body deforms like a soft body:
      - slow drag → barely visible deformation, no jitter
      - fast drag → capped directional stretch with compression, no growth
      - horizontal/vertical/diagonal drag → deformation axis matches movement
      - grabbing above vs below center dragging the same way → opposite
        subtle rotation; grabbing the center → almost none
      - rapid direction reversal → smooth morph through neutral, no flicker
      - holding the mouse still mid-drag → pet relaxes back toward neutral
        around the held grab point; moving again responds immediately
- [ ] release springs deformation back to neutral elastically (< ~0.5 s,
      no long oscillation) and the settle bounce still works
- [ ] pet cannot be dragged or hop off-screen (menu bar/Dock respected)
- [ ] pet stays put when dragged to a second display (if available)
- [ ] menu-bar quit button (ⓧ) exists
- [ ] a single click on the menu-bar quit button exits the app
      immediately — no popup menu appears
- [ ] right-clicking the pet does nothing (no menu, no harm)
- [ ] relaunch restores the last position (and falls back safely if that
      display was removed)
- [ ] Curious: slow cursor approach engages subtly; hovering near the
      threshold never flickers; moving in/out repeatedly stays stable;
      no chasing; click/drag always wins immediately
- [ ] Float: leave the pet idle for a minute (floats are temporarily very
      frequent: floatChance 0.75, cooldown 20–35 s). The pet lifts
      slowly (~2 s), hovers clearly near peak height with a gentle bob and
      sway (~2.8 s, visibly distinct from a hop), descends slowly and lands
      extremely softly with no bounce; stays on-screen; occasional hops
      still appear for comparison; clicking mid-float squashes in place
      then descends smoothly; dragging mid-float takes over immediately
- [ ] Curious: slow cursor approach engages subtly; while curious the pet
      follows the cursor fluidly (no stepping/choppiness); hovering near the
      threshold never flickers; no chasing; click/drag always win immediately
- [ ] Sleep (with sleepyTimeout=15, sleepTimeout=30 for testing):
      idle → sleepy → sleeping; breathing is subtle; Z is subtle; click and
      drag both wake the pet smoothly; normal idle behavior resumes after
      waking; no permissions dialogs appeared
- [ ] with "Click wallpaper to reveal desktop" enabled, clicking the desktop
      leaves the pet visible in place (`.stationary` — unverified; if the pet
      still hides, that is expected macOS behavior)
- [ ] clicks on the transparent corners of the window pass through to
      whatever is underneath (NOT assumed to work — verify)
- [ ] clicks elsewhere on the desktop are never blocked
- [ ] no visible CPU usage while idle
