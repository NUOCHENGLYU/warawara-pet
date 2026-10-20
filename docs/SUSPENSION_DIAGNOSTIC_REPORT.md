# Lid-Close Disappearance — Suspension Diagnostic Report

Branch: `phase7/final-gift` · Commits `f5b2956..e2b548a` · Run:
https://github.com/NUOCHENGLYU/warawara-pet/actions/runs/39382703799 (completed, success)

## 1. What was tested and how

All verification ran on the GitHub Actions `macos-14` runner (real Sonoma 14
image) plus the macos-15 universal job. Three mechanisms simulate the
receiver's "long lid-close sleep" symptom:

| Mechanism | Where | What it proves |
|---|---|---|
| Virtual wall-time jumps (10 min … 72 h) | `SuspensionSimulationTests` | Every transient pet motion, state machine, birthday and meteor path survives a big `Date()` jump without NaN, duplicate completion, window moves/closure, or hangs |
| Recovery fault matrix (A–J) | `WindowRecoveryFaultMatrixTests` + existing `WindowRecoveryTests` | Off-screen/hidden/screen-removal/resize/wake-storm recovery math and real-panel restore behavior |
| Real SIGSTOP/SIGCONT freeze of the live test process | CI job `Sonoma 14 Sleep/Wake Simulation` | The host process genuinely frozen mid-execution for 8 s (verified in `T` state at both ends of the pause), resumed, and exited cleanly |

The freeze step freezes the running xctest process
(`pkill -STOP -f 'WarawaraPetPackageTests|xctest'`), checks `ps -o state=`
shows `T` (stopped), waits 8 s, re-checks `T` (the freeze proof — SIGSTOP
can only be undone by SIGCONT, so `T` at both ends proves a real ≥ 8 s
freeze), then CONTs and requires exit 0, `SUSPENSION_HOST_BEGIN/END`
markers, and a non-zero spin counter (measured 733 000 000 iterations).
Markers are written straight to a file (`SUSPENSION_HOST_MARKER`) because
XCTest's harness captures test stdout/stderr until the test ends, which the
CI script cannot react to live.

Evidence artifacts: `Sonoma14-SleepWake-Simulation-Logs`
(`sonoma-sim.log`, `stopcont.log`, `stopcont.marker`).

## 2. Confirmed behaviors (source audit + tests)

Severity relative to the disappearance symptom.

### A. Mild — in-flight motion teleports to completion after a long jump (no crash)
`PetMotionController` times hop/float/settle from wall-clock `Date()` with
progress clamped to [0, 1] (`Sources/WarawaraPet/Pet/PetMotionController.swift:107-170`).
After any long suspension the next timer tick computes t = 1 and finishes
exactly once. Verified for 10 min/1 h/8 h/24 h/72 h jumps. Consequence:
at most one visible "teleport-finish" per in-flight motion after wake —
no disappearance, no NaN, no duplicate completion.

### B. Mild — a backward clock jump resets in-flight progress to 0
The same clamp maps negative elapsed to 0, so the current motion visually
restarts from its start pose, then completes once when time moves forward
again (`testBackwardClockClampsProgressToZeroWithoutCrash`). Bounded and
cosmetic; wall clocks rarely move backward (NTP).

### C. Moderate (potential false recovery) — empty screen list triggers recovery
`WindowRecovery.needsRecovery` returns true for an EMPTY screen list
(`!screens.contains { … }`), and `recoveryFrame` falls back to
`NSScreen.main?.visibleFrame` or a hardcoded 1280×800 box. A wake-time
race where `NSScreen.screens` is briefly empty could therefore MOVE a
healthy visible panel into the fallback box. Recorded as a known weakness
in `testEmptyScreenListIsAKnownWeakness`. **Minimal fix (not applied):**
`guard !screens.isEmpty else { return false }` and skip the restore,
retrying on the next event.

### D. Info — recovery cannot detect wrong-Space/Stage-Manager placement
`needsRecovery` only inspects frame geometry + `isVisible`. A panel that is
"visible with normal coordinates" but stranded on a hidden Space or
over-zoomed Stage cluster is undetectable from within the app. CI cannot
exercise Spaces; this needs the receiver's real Mac.

### E. Info — mixed clock bases cause scheduling drift, not disappearance
Meteor flight uses monotonic `systemUptime` (pauses during lid sleep → the
meteor effectively pauses and resumes); the `.noticing` boundary and float
cooldown use wall `Date()` (fast-forward on wake). Group sequence dt is
monotonic while phase timing is wall-clock (phases fast-forward). All
verified to complete without touching the main pet panel
(`testBirthdayEventCompletesAfterDayLongSuspensionWithoutTouchingPetWindow`,
`testMeteorCompletesAfterLongMonotonicJumpWithoutTouchingPetWindow`).

### F. Info — sleeping/idle/curious states survive long jumps unchanged
`testSleepingPetStaysSleepingAndWindowUntouched`,
`testIdleAndCuriousSurviveLongJumpsWithoutDuplicateWindows`,
`testSleepyProgressesToSleepingAcrossLongSuspensionByDesign`,
`testClickedStateDoesNotAutoRecoverFromLongSuspension`.

### G. Info — no production path closes the main pet panel
The only `orderOut` of the main panel in production sources is the
fault-injection hook (`--fault-inject`), which is off by default.

## 3. Direct answers

- **Was the pet disappearance reproduced?** **No.** No source-audit path,
  virtual time-jump, recovery-fault injection, or real process freeze on
  Sonoma 14 reproduced the pet (or the status icon) disappearing.
- **Most likely real-world cause given the evidence:** the process itself
  terminated during sleep (system/AppKit crash or force-quit), not a
  hidden window. Symptom signature: BOTH the pet panel and the menu-bar
  status icon are gone. Only a terminated process removes the status icon.
- **How to confirm on the receiver's Mac:** open
  `~/Library/Logs/WarawaraPet/lifecycle.log`. If the last entry is
  `LIFECYCLE_LAUNCH` without a following `LIFECYCLE_QUIT`, the process
  died during sleep (crash). A crash report would appear under
  `~/Library/Logs/DiagnosticReports/` with `WarawaraPet` in the name.

## 4. Untestable in CI (require the real Mac)

- Spaces / Stage Manager placement (see D above).
- True lid-close power state (SIGSTOP models CPU freeze, not the full
  S3/sleep + WindowServer teardown/rebuild cycle).
- Any Sonoma-specific WindowServer behavior on wake.

## 5. Proposed minimal fixes (NOT applied — behavior-change confirmation pending)

1. **Empty-screen-list guard in `WindowRecovery`** (finding C) — no-op when
   `screens` is empty; retry on the next lifecycle event.
2. Optional hardening for finding B: hold (monotonic) progress instead of
   clamping negative elapsed to 0.
3. Ask the receiver to send `lifecycle.log` after the next occurrence —
   one file decides between "crashed" and "window misbehaved".

## 6. What green CI does NOT claim

Green CI proves the code paths under test complete without NaN, hangs,
duplicate windows, or panel moves under virtual jumps and a real 8 s
process freeze. It does **not** prove wake-correctness on the receiver's
hardware; that still requires the real-Mac checklist in the README.
