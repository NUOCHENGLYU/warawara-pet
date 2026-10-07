# WarawaraPet

A tiny native macOS desktop-pet application (private birthday gift, not for
public distribution). The pet is a Warawara-like character that lives in a
transparent, borderless floating window above the desktop.

**Current status: Phase 2 — personality (curious/float/sleepy/sleeping),
awaiting real-Mac validation.**

What exists today:

- accessory app (no Dock icon), transparent borderless non-activating panel
  that can never become key/main — clicks never steal keyboard focus
- placeholder pet (procedurally drawn blob — no copyrighted artwork)
- gentle idle bob, randomized hops (6–14 s apart) with squash/stretch
- rare soft floats: slow lift, buoyant sway, gentle return; drag or click
  can interrupt at any time
- curiosity: after the cursor dwells nearby the pet leans/stretches toward
  it subtly (distance hysteresis — no flicker, no chasing); never engages
  while hopping, floating, settling, dragged, or sleeping
- sleep: after 4 min of system inactivity the pet gets sleepy, after 8 min
  it sleeps (slow breathing, tiny Z); click or drag wakes it smoothly
- click reaction (squash + rebound), right-click → Quit
- mouse dragging with soft-body-style deformation (Phase 1.6, M1-verified)
- position clamping inside the visible screen area (menu bar/Dock excluded),
  multi-display aware, re-clamps on display changes
- window position persisted across launches (falls back to a safe default if
  the saved display no longer exists)
- tight elliptical hit region around the pet body
- `.stationary` collection behavior so the pet stays visible during Show
  Desktop / Mission Control (unverified on a real Mac)

No group, gathering, ascent, or birthday behavior yet. No sprites, no
sound, no network, no third-party dependencies.

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
   was last left). Click it, drag it around, watch it hop. Right-click it →
   "Quit WarawaraPet".

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
| `floatChance` | 0.2 | probability of a float at each eligible fire |
| `floatCooldown` | 75 s | minimum time between floats; hops continue meanwhile |
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

## Developer controls (debug menu)

A right-click **Debug** submenu with Force Hop / Float / Curious / Sleepy /
Sleeping is available only when debug controls are enabled:

```bash
defaults write com.birthday.warawarapet warawarapet.debug -bool true
```

(or launch with the argument `-WarawaraPetDebug`), then relaunch. Each
Force action runs the real production state and motion path. Disable
before the final gift build:

```bash
defaults delete com.birthday.warawarapet warawarapet.debug
```

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
- [ ] right-click → Quit works
- [ ] right-click menu: dismiss it without choosing anything → the pet
      stays visible (repeat several times); the active app keeps keyboard
      focus throughout menu interaction
- [ ] relaunch restores the last position (and falls back safely if that
      display was removed)
- [ ] Curious: slow cursor approach engages subtly; hovering near the
      threshold never flickers; moving in/out repeatedly stays stable;
      no chasing; click/drag always wins immediately
- [ ] Float: use the Debug menu → Force Float repeatedly. The pet lifts
      slowly (~2 s), hovers clearly near peak height with a gentle bob and
      sway (~2.8 s, visibly distinct from a hop), descends slowly and lands
      extremely softly with no bounce; stays on-screen; clicking mid-float
      squashes in place then descends smoothly; dragging mid-float takes
      over immediately
- [ ] Debug menu: Force Hop / Float / Curious / Sleepy / Sleeping all work
      and follow normal wake/exit rules; the menu is absent when the debug
      defaults key is removed
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
