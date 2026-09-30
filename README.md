# WarawaraPet

A tiny native macOS desktop-pet application (private birthday gift, not for
public distribution). The pet is a Warawara-like character that lives in a
transparent, borderless floating window above the desktop.

**Current status: Phase 1 — One interactive pet (placeholder artwork).**

What exists today:

- accessory app (no Dock icon), transparent borderless non-activating panel
- placeholder pet (procedurally drawn blob — no copyrighted artwork)
- gentle idle bob, randomized hops (6–14 s apart) with squash/stretch
- click reaction (squash + rebound), right-click → Quit
- mouse dragging with a slight body lean, soft bounce/settle on release
- position clamping inside the visible screen area (menu bar/Dock excluded),
  multi-display aware, re-clamps on display changes
- window position persisted across launches (falls back to a safe default if
  the saved display no longer exists)
- tight elliptical hit region around the pet body

No curiosity, floating, sleep, group, or birthday behavior yet. No sprites,
no sound, no network, no third-party dependencies.

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
- [ ] dragging moves the pet; body leans slightly; release bounces softly
- [ ] pet cannot be dragged or hop off-screen (menu bar/Dock respected)
- [ ] pet stays put when dragged to a second display (if available)
- [ ] right-click → Quit works
- [ ] relaunch restores the last position (and falls back safely if that
      display was removed)
- [ ] does not steal keyboard focus on any interaction
- [ ] clicks on the transparent corners of the window pass through to
      whatever is underneath (NOT assumed to work — verify)
- [ ] clicks elsewhere on the desktop are never blocked
- [ ] no visible CPU usage while idle
