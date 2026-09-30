# Sprite assets

Placeholder sprites are not required yet — Phase 0 renders a programmatic
placeholder. When final artwork is available, drop PNG frames here following
this convention:

```
idle/
  idle_00.png
  idle_01.png
  ...
hop/
float/
click/
sleep/
birthday/
```

Images must have transparency. Animation definitions (frame lists, durations,
looping) will live in code under `Sources/WarawaraPet/Animation/` and must not
be hard-coded across UI code.
