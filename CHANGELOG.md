# Changelog

## 0.1.0

The first version: the PK-4 console from Mac Command Center, rebuilt as a standalone app
that draws its art once and only moves it afterwards.

- **The desk.** All five panels and the header, every instrument of the reference, in both
  themes and all three paints, held by golden tests to within antialiasing of the reference
  SwiftUI desk (a mean of about 3.4 levels in 255). The plates say SKALA-2000, type DD-72.
- **Behaviour.** The reference's rules and readers unchanged, with their 152 tests: four
  session slots, the alarm board, LAMP TEST and BUZZER TEST, the routine and guarded keys
  (F10 ends a session after the key, a 2 s hold and your password), Keep Awake, sleep and
  monitor off, MAINS and the power-up sequence, PRINT TEXT, the safety log, the desk's
  memory and the scripted day.
- **Speed.** 0.02% of a core idle, 0.77% playing the scripted day, 0.04 ms of main thread
  per resize frame with no frames missed, 0.41 s from launch to desk, 161 MB at 5K full
  screen. See PERFORMANCE.md.
- **Hooks** on a Unix socket of the app's own, beside Mac Command Center's, installed from
  Settings or a script.
- **Input.** An explicit hit table (no two controls overlap, tested), press on mouse-down
  and release on mouse-up anywhere, keyboard focus for the keyboard only, VoiceOver for
  every instrument.
- **Fixed from the reference:** panel B overflowed the desk by 40 units and its lower edge
  was cut off; it now ends at 1778 like D and E. The four POWER SOURCE lamps had no
  instrument ids in the layout and would never have lit.
