# WarawaraPet

A tiny native macOS desktop-pet application (private birthday gift, not for
public distribution). The pet is a Warawara-like character that lives in a
transparent, borderless floating window above the desktop.

**Current status: Phase 0 — Bootstrap.**

What exists today: a minimal macOS app that launches as an accessory
application (no Dock icon), shows a placeholder pet in a transparent,
borderless, non-activating floating panel, and can be quit via right-click.
No motion states, no sprites, no birthday logic yet.

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
4. A placeholder pet appears near the bottom-right of the main display.
   Right-click it → "Quit WarawaraPet".

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
  Pet/                        NSPanel window behavior
  UI/                         SwiftUI placeholder pet rendering
  Support/                    pure testable helpers (frame math)
Tests/WarawaraPetTests/       unit tests (run on CI via swift test)
Scripts/package-app.sh        assembles, ad-hoc signs, and zips the .app
Resources/Sprites/            future sprite frames (see its README)
.github/workflows/ci.yml      macOS CI: build → test → package → artifact
```

## Signing and notarization (future)

The artifact is currently ad-hoc signed (`codesign --sign -`), which is
enough for a private tester after removing quarantine. To distribute more
broadly later: add a Developer ID certificate as a GitHub Actions secret,
sign with `codesign --options runtime`, staple, and notarize with
`notarytool`. No secrets are stored in this repository.

## Manual test checklist (real Mac, to be completed)

- [ ] app launches without crashing
- [ ] transparent background, no title bar
- [ ] does not steal keyboard focus
- [ ] placeholder pet is visible
- [ ] right-click → Quit works
- [ ] app does not block clicks elsewhere on the desktop
