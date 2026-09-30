# Warawara Desktop Pet — Project Instructions

## 1. Project goal

Build a polished native macOS desktop-pet application as a private birthday gift.

The pet is based on **Warawara (哇啦哇啦) from _The Boy and the Heron_**. The app is not intended for commercial release or public distribution. Do not scrape, bundle, or redistribute copyrighted movie footage, official GIFs, soundtrack, screenshots, or extracted studio assets. Keep artwork as project-local user-provided/originally-created sprite assets.

The recipient uses a Mac. The developer uses Windows, so the project must be able to:
1. be developed largely from Windows;
2. compile automatically on a macOS CI runner;
3. produce a downloadable macOS build artifact;
4. be easy to test later on a real Mac.

The experience matters more than feature count. Prefer a small, stable, charming desktop pet over an overengineered app.

---

## 2. Product concept

The desktop pet should feel like a Warawara living on the user's desktop rather than a normal application window.

Core behavior:
- transparent background;
- no normal title bar;
- pet floats above normal desktop content without behaving like a conventional app window;
- pet can idle, bounce, float, react to the pointer, be clicked, and be dragged;
- movement should feel soft, elastic, light, and slightly irregular;
- avoid generic "walking character" behavior;
- preserve Warawara's recognizable visual language: soft body deformation, bobbing, gathering, and floating upward.

The app should be quiet and non-intrusive. It must never hijack keyboard focus during normal pet interaction.

---

## 3. Technical direction

Use a **native macOS application**.

Preferred stack:
- Swift
- SwiftUI for simple UI/state presentation where convenient
- AppKit where required for desktop-window behavior
- NSPanel / NSWindow for transparent, borderless floating pet windows
- Core Animation / SwiftUI animation / timer-driven sprite animation as appropriate
- No Electron
- No Python runtime dependency
- No browser wrapper
- No third-party dependency unless it materially simplifies the implementation

Keep the dependency surface minimal.

Target:
- macOS 13 or newer unless a concrete compatibility issue requires another minimum
- Apple Silicon first-class support
- ideally universal arm64 + x86_64 build if CI/tooling makes this straightforward

Never hard-code one screen resolution, one Mac model, or one Dock location.

---

## 4. Architecture requirements

Keep visual rendering, pet state, movement physics, event handling, and birthday logic separate.

Suggested structure:

```text
WarawaraPet/
  App/
  Models/
    PetState.swift
    PetMood.swift
  Pet/
    PetController.swift
    PetWindowController.swift
    PetMotionController.swift
    PetInteractionController.swift
  Animation/
    SpriteAnimator.swift
    AnimationDefinition.swift
  Birthday/
    BirthdayEventController.swift
  UI/
    PetView.swift
    LetterView.swift
  Resources/
    Sprites/
    Sounds/
  Support/
    ScreenGeometry.swift
    DateProvider.swift
Tests/
```

Exact names may change, but responsibilities must stay separated.

Avoid one giant view or controller containing all logic.

---

## 5. Pet state machine

Implement an explicit state machine rather than a collection of unrelated timers.

Minimum states:

```text
idle
hop
float
curious
clicked
dragged
sleepy
sleeping
gathering
ascending
birthday
```

Transitions should be event-driven and probabilistic where appropriate.

Examples:
- idle -> curious when pointer remains nearby;
- idle -> hop after a randomized quiet interval;
- idle -> float occasionally;
- curious -> idle when pointer leaves;
- any normal state -> dragged while mouse drag is active;
- dragged -> idle/bounce recovery on release;
- idle -> sleepy after prolonged inactivity;
- sleepy -> sleeping if undisturbed;
- sleeping -> clicked/wake after deliberate interaction;
- normal -> gathering/ascending only as a rare ambient event or birthday sequence.

Do not let two mutually exclusive motion states run simultaneously.

All random behavior must use bounded delays so the pet does not twitch constantly.

---

## 6. Animation language

### Idle
- gentle vertical bob;
- tiny side-to-side sway;
- occasional soft squash/stretch;
- long periods of almost no movement are acceptable.

### Hop
- compress downward;
- launch upward and slightly sideways;
- stretch subtly during ascent;
- squash on landing;
- settle with one small rebound.

### Float
- slowly leave the ground;
- drift upward with slight horizontal variation;
- remain soft and buoyant;
- return naturally or transition into a short ascent event.

### Pointer curiosity
- notice the pointer only when it is reasonably close;
- turn/lean toward it rather than snapping instantly;
- optional tiny hop toward the pointer;
- do not chase aggressively.

### Click
- quick squash;
- rebound;
- short recovery animation;
- repeated rapid clicks may trigger a playful dodge rather than infinite bouncing.

### Drag
- user can drag the pet freely;
- body should lag/stretch very slightly in the drag direction if practical;
- on release, perform a soft bounce/settle;
- clamp final position to a safe visible region.

### Sleep
- settle into a low-energy pose;
- subtle breathing/body movement;
- optional tiny "Z" visual;
- do not spam text.

### Group / ascent
This is one of the most important signature sequences:
- additional Warawara may appear near the main one;
- they softly crowd together;
- after a short pause they begin floating upward;
- each follows a slightly different curved path;
- they disappear cleanly beyond the screen edge;
- the main pet may remain behind unless the sequence specifically calls for it.

Avoid using pelicans, fire attacks, or distress imagery in the birthday gift.

---

## 7. Birthday event — October 17

The birthday sequence is a first-class feature.

Trigger:
- local calendar date is October 17;
- sequence should normally happen once per calendar year per installation;
- provide a developer/debug override to trigger it on any date.

Suggested sequence:
1. main Warawara notices something;
2. several additional Warawara appear one by one;
3. they gather together;
4. a small birthday object appears (cake, star, or envelope — use project-created artwork);
5. short celebratory animation;
6. most of the group slowly float upward;
7. one Warawara remains;
8. an envelope/letter interaction becomes available;
9. clicking it opens the personal birthday letter.

The final personal letter content must be stored separately from animation logic, preferably in a simple resource file or clearly isolated constant so it can be edited immediately before delivery.

Do not write the final birthday letter text unless the user supplies it.

Persist birthday-event completion in UserDefaults.

Developer controls must allow:
- force birthday mode;
- reset birthday-event completion;
- spawn group;
- force sleep;
- show letter.

Debug controls must not be visually exposed in the final gift unless enabled by a development flag.

---

## 8. Optional ambient behavior

Only add these after the core pet is stable:
- second/third temporary Warawara appears occasionally;
- rare group ascent;
- midnight/late-night sleeping behavior;
- reacting to screen edges;
- playful dodge after repeated clicks;
- simple speech bubble with a very small curated line set.

Do not add:
- AI chat;
- network calls;
- analytics;
- login/account systems;
- invasive permissions;
- auto-updaters;
- unnecessary background services.

The finished app should work offline.

---

## 9. Window behavior

The pet must:
- render over a transparent background;
- have no title bar/chrome;
- avoid appearing as a normal document window;
- not steal focus on passive interactions;
- support click and drag on the visible pet;
- remain usable around multiple displays where practical;
- respect visible screen bounds;
- account for menu bar and Dock safe areas;
- handle display-size changes gracefully.

Choose the appropriate NSWindow/NSPanel level only after testing. Do not make the app obnoxiously stay above full-screen applications unless explicitly desired.

When uncertain, prefer a less intrusive window level.

---

## 10. Input hit testing

Transparent regions around the sprite should not feel like a giant invisible rectangle.

Preferred behavior:
- pointer interaction is limited to the pet's meaningful visible area;
- if per-pixel hit testing is too costly for v1, use a tight hit region approximating the sprite;
- the app must not block unrelated desktop clicks outside the pet.

---

## 11. Assets

Animation code must not depend on final artwork being complete.

Support placeholder assets during development.

Use a predictable resource convention, e.g.:

```text
Resources/Sprites/
  idle/
    idle_00.png
    idle_01.png
  hop/
  float/
  click/
  sleep/
  birthday/
```

Sprite images should support transparency.

Animation definitions should specify:
- frame list;
- frame duration;
- looping/non-looping;
- optional anchor point;
- optional transition target.

Do not bury frame timing across arbitrary UI code.

If final sprite assets are missing, create simple geometric placeholder sprites sufficient to verify motion and packaging.

---

## 12. Persistence

Use UserDefaults for lightweight state only:
- birthday event completed for year;
- optional pet position;
- optional sound enabled flag;
- optional launch-at-login preference if added later.

Do not add a database.

---

## 13. Privacy and security

The application must:
- make no network requests;
- collect no telemetry;
- collect no personal data;
- not access contacts, photos, camera, microphone, or location;
- require no account;
- request no permissions unless macOS technically requires one for an explicitly implemented feature.

Keep entitlements minimal.

---

## 14. Build and Windows-development constraints

The developer's main machine is Windows.

Therefore:
- source code and project files must be editable normally on Windows;
- do not require the Windows developer to run Xcode locally;
- add a GitHub Actions workflow using a macOS runner;
- CI must build the app on every relevant push/manual dispatch;
- CI should upload the built `.app` packaged as a `.zip`;
- later, optionally create a `.dmg`.

The first priority is a reliable unsigned/ad-hoc-signed test artifact.

Do not block progress on Apple Developer notarization.

Document separately:
1. how to download CI artifact;
2. how a tester opens the unsigned/ad-hoc app on macOS;
3. how final Developer ID signing/notarization could be added later.

Never commit secrets, certificates, API keys, or signing credentials.

---

## 15. Testing strategy

Because most development occurs without a Mac, maximize automated verification.

Add unit tests for logic that does not require UI:
- state transitions;
- date/birthday triggering;
- event "once per year" behavior;
- motion boundary calculations;
- random-delay bounds;
- position clamping.

CI requirements:
- compile successfully on macOS;
- run unit tests;
- fail on compiler/test errors;
- save app artifact.

Real-Mac manual test checklist must cover:
- launch;
- transparent window;
- no unwanted focus stealing;
- clicking;
- dragging;
- movement;
- Dock/menu-bar boundaries;
- multiple display behavior if available;
- birthday debug trigger;
- letter opening;
- app quit behavior;
- relaunch persistence.

Do not claim a macOS UI behavior is verified until it has actually been tested on macOS.

---

## 16. Development phases

Work incrementally. Each phase must leave the repository buildable.

### Phase 0 — Bootstrap
- create native macOS project;
- minimal app launches;
- placeholder transparent pet window;
- CI macOS build;
- README build instructions.

### Phase 1 — One pet
- transparent window;
- placeholder sprite;
- idle;
- hop;
- drag;
- click;
- safe positioning.

### Phase 2 — Personality
- state machine;
- curiosity;
- float;
- sleep;
- restrained randomized behavior.

### Phase 3 — Group behavior
- temporary additional Warawara windows/entities;
- gathering;
- group ascent;
- cleanup of temporary entities.

### Phase 4 — Birthday
- October 17 trigger;
- once-per-year persistence;
- debug override;
- celebratory group sequence;
- letter UI.

### Phase 5 — Polish
- final sprite assets;
- motion tuning;
- optional sound;
- edge cases;
- real-Mac test fixes;
- packaging.

Do not begin Phase N+1 while Phase N has compile-breaking issues.

---

## 17. Coding standards

- Prefer simple Swift over clever abstractions.
- Use descriptive type and method names.
- Keep UI code declarative where practical.
- Keep motion calculations deterministic/testable where possible.
- Inject date/time/randomness behind small abstractions when needed for tests.
- Avoid global mutable state.
- Avoid force unwraps except for demonstrably invariant resources.
- Handle missing sprite resources gracefully during development.
- Add comments only where the "why" is non-obvious.
- No dead code or speculative framework layers.

---

## 18. Performance

This is a tiny desktop utility.

Goals:
- negligible CPU when sleeping/idle;
- no busy loops;
- animation timers stop or slow when not needed;
- avoid constant high-frequency polling;
- do not redraw the entire screen;
- clean up temporary pet windows/entities after group events.

Battery usage matters on MacBook.

---

## 19. UX constraints

The pet should feel:
- soft;
- quiet;
- slightly unpredictable;
- recognizable;
- affectionate without being intrusive.

Avoid:
- constant bouncing;
- frequent popups;
- repeated dialogue;
- loud audio;
- screen-covering effects;
- exaggerated particle spam;
- anything that interrupts normal work.

When choosing between "more impressive" and "more charming/subtle", choose subtle.

---

## 20. Definition of v1 done

v1 is complete when:

- macOS CI builds successfully from the repository;
- a `.zip` containing the app is produced;
- app launches on a real Mac;
- one Warawara renders with transparent background;
- idle/hop/float/click/drag/sleep work;
- interaction outside the pet does not block desktop usage;
- group gathering + ascent works;
- October 17 birthday event can be triggered normally and via debug override;
- birthday sequence opens a separate editable personal letter;
- birthday completion persists;
- no network/data collection exists;
- manual Mac test checklist is documented;
- no known crash occurs in normal interaction.

---

## 21. Agent workflow

### PLAN agent
The PLAN agent must:
1. inspect the current repository before proposing changes;
2. produce a concrete implementation plan for the next smallest working milestone;
3. identify macOS-specific assumptions that cannot be verified on Windows;
4. state which files should be created/modified;
5. state tests and CI verification;
6. avoid editing implementation files;
7. avoid planning multiple future phases in detail when the current phase is not stable.

Plans should be implementation-ready, not essays.

### BUILD agent
The BUILD agent must:
1. read the current plan and repository state;
2. implement only the current milestone;
3. keep the repository compiling;
4. add/update tests;
5. add/update CI when required;
6. run all locally available checks;
7. clearly distinguish:
   - verified by local/static checks,
   - verified by macOS CI,
   - still requiring real-Mac manual verification;
8. never fabricate test results.

If CI cannot be run from the current environment, make the workflow correct and state that it still requires execution on GitHub.

### When blocked
Do not redesign the whole project immediately.
Prefer:
1. isolate the failing behavior;
2. implement a minimal fallback;
3. preserve buildability;
4. document the remaining Mac-only verification.

---

## 22. First task

Start with **Phase 0 only**.

PLAN should propose:
- exact project structure;
- deployment target;
- how AppKit and SwiftUI will be combined;
- transparent panel/window strategy;
- placeholder pet rendering;
- GitHub Actions macOS build workflow;
- test target;
- artifact packaging;
- README instructions for a Windows-based developer.

BUILD should then implement that plan.

Do not implement the full pet in the first pass.
