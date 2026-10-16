# Warawara Phase 6B — Event Timing and Story Specification

Status: **implementation plan**. Not yet integrated into the macOS app. Assets are independently transparent PNG candidates pending M1 visual acceptance.
Birthday Phase 6A is already accepted except the two explicitly requested birthday changes below. Preserve the existing birthday engine, art v5, local calendar, letter interaction, and event state.

## Event priority and timing principles

- Strict priority: Birthday (existing) > Chinese New Year > Christmas > Gregorian New Year > Daily random events.
- Never overlap two scripted events. A high-priority event waits for safe cleanup, no abrupt despawning.
- Use the Mac's **current local calendar/timezone**, and re-evaluate after system wake, local midnight, date or timezone change, and app relaunch. Do not use UTC day boundaries for local festivals.
- Holiday events: **at most one automatic full performance per occurrence/year**. Store persistent completion under stable keys; manual replay and debug dates must not consume the annual flag.
- Respect dragging, nonactivating panel focus, Show Desktop, letter reading, existing sleep mode, app inactivity and low-distraction expectations. Do not prompt for location or internet access.
- No full-screen overlays; no NSMenu; no unexpected keyboard focus; respect multi-monitor visible bounds.
- Audio: no sudden holiday sound or explosion effects; silence by default.
- Gracefully suspend/finish events when OS sleeps or displays change; durable completion only at recoverable end.

## 1. Chinese New Year / Spring Festival

Use `Calendar(identifier: .chinese)` with timezone set to `TimeZone.current`, evaluating local Gregorian days. Lunar 1st month, day 1–3 are eligible; optionally Lunar New Year's Eve is supported but should not be the only trigger. Never hardcode a Gregorian holiday date or assume the zodiac. For 2027, Lunar Jan 1 is Feb 6 (Gregorian), for testing only. Handle leap lunar months by checking `.isLeapMonth` and do not confuse ordinary first month with any other month.

Trigger on the first calm eligible moment once per Chinese New Year occurrence, preferably daylight/early evening, avoid after 23:00 unless user explicitly replays. If the user misses the eligible window, don't unexpectedly trigger weeks later.

Performance approx 25–40 seconds: main Warawara notices -> 1–2 companions gently hop in carrying a small red envelope and lantern/plum branch -> brief presentation, slight lantern sway, main character curious glance -> companions depart naturally -> props gently retire (no permanent decoration). Firecracker asset is decorative only; NO explosive sound or loud pyrotechnics.

Assets: `cny_lantern.png`, `cny_hongbao.png`, `cny_plum_branch.png`, optional `cny_firecracker_hanging.png`.

## 2. Christmas

Eligible local dates Dec 24–26 (allow 24 from 18:00 local time), one automatic performance per calendar year. No need for any religious framing or assumptions; the scene is simply a gentle winter gift exchange.

Performance approx 25–40 seconds: curious noticing -> companion approaches with `xmas_gift.png` -> soft reveal near pet -> small pause -> wreath briefly appears / subtly sways -> companion floats away -> all Christmas props retire without leaving obstacles. No sound by default.

Assets: `xmas_wreath.png`, `xmas_gift.png`. Do not invent a Santa character.

## 3. Gregorian New Year / New Year's Day

Eligible Jan 1, local Gregorian calendar; once per Gregorian calendar year. (Dec 31 midnight countdown is an optional *future* capability, not required or simulated.) Do not use hardcoded year text in art: calendar shows only `1`.

Performance approx 20–30 seconds: pet notices the little calendar -> companion brings calendar -> calendar rests near pet -> one tasteful muted confetti popper appears and safely fades -> two little hops -> props retire.

Assets: `newyear_calendar_jan1.png`, `newyear_party_popper.png`. Silent and never overproduce particle effects.

## 4. Low-frequency daily micro-events

Daily event types (8–20 seconds each; no text UI; no new characters):

- `umbrella`: 12–18 s. A playful paper umbrella arrives, one pet tilts under it, then it departs. No weather claim. Fully offline. No real rain detection.
- `hot_cocoa`: 12–18 s. Mug arrives and pet hovers/leans as if appreciating the smell; subtle steam already baked into image; no extra steam overlay unless verified.
- `sprout`: 10–16 s. Tiny seedling appears near pet, curious gaze, subtle scale/tilt sway, then retires.
- `paper_airplane`: 8–15 s. A little paper airplane glides in a smooth continuous arc near pet, pet watches it, then exits safely. Keep it clickable only if intentional.

Suggested scheduler for an unintrusive desktop companion:
- Don't schedule a daily event until the app has been up for at least 20 minutes and the pet is awake and not engaged in another interaction.
- Global minimum gap: 120 minutes of eligible app time between completed automatic daily events, with an optional randomized additional 0–60 minutes; **maximum 2** daily events per local calendar day.
- Same daily event type should not repeat within the last 24 hours when possible; use persisted recent history and weighted random choice.
- Avoid daily events between 23:00 and 08:00 local time, during pet sleep, user drag, fullscreen-sensitive activity where detectable without invasive permissions, active birthday/holiday, or letter reading.
- Use lightweight occasional tick and centralized coordinator, not a high-frequency animation timer waiting for randomness.
- No reliance on actual weather, location, online APIs, Calendar, or user data; `umbrella` is whimsical, not a weather prediction.
- Daily random events can use existing curious/hop/float animations; no changes to the accepted Warawara Rig. No permanent props.

## 5. State, recovery, tests

- State IDs: `holiday:cny:<occurrence-year>`, `holiday:christmas:<gregorian-year>`, `holiday:newyear:<gregorian-year>`, `daily:<kind>:<timestamp>`; persistent auto-completion distinct from manual replay. Ensure CNY year references the actual Chinese New Year occurrence, not the current lunar cyclic numeric calendar year alone.
- Provide deterministic injected clocks/calendar/seeded RNG; validate e.g. 2027 Feb 5 vs Feb 6, timezones, DST and Dec31–Jan1 boundary, leap-month correctness, duplicate launch prevention, interruption/restart/replay independence.
- Debug entry `--replay-event cny|christmas|newyear|umbrella|hot-cocoa|sprout|paper-airplane` or an existing compatible CLI. Document exact commands. Do not use NSMenu.
- Run full existing birthday and pet tests; packaged universal `.app` verifies `EVENT_ASSETS_OK` and existing `BIRTHDAY_OK`, `SPRITES_OK`, `rig=loaded`.
- Hand off screenshot sequence previews using **production** Warawara Rig and these exact resources on light and dark desktops.

## 6. Existing birthday v5 remaining polish (DO FIRST)

1. **Companion entrance should visibly hop/bob**, not slide at constant height. Use a continuous smooth trajectory with independent staggered phase, small hop heights/roll and body easing; honor real companion velocity, maintain group arrangement and preserve all carried prop transforms during the motion. Don't run generic random hop timers concurrently. Keep the final slowdown graceful.
2. **Cake must be visibly supported in front of its carrier companion.** Current pet body unexpectedly occludes carried cake. Render cake+tray *in front of the companion's body silhouette*, ideally behind any true foreground hands/arms if already in the approved Rig. If foreground arms don't exist, don't synthesize new ones. The cake and tray must remain one transform and clearly rest together, with a believable contact anchor and no floating/pasting/jitter. During delivery/after placing, preserve correct layering, shadow safety, click behavior and all accepted birthday v5 scene choreography.
