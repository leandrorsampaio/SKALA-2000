# SKALA-2000 — handover

**SKALA-2000 · Operator Console for Claude Code · type DD-72**

You are building a new, standalone, native macOS app in a **new repository**. It is a
performance-first rebuild of an existing console that already works, with its tested logic,
inside the *Mac Command Center* app. The console looks like a 1972 East German operator desk
and lets its owner watch up to four Claude Code sessions at once. The existing app stays
untouched: you read and copy from it, you never change it.

Read this whole document before writing code. Then read the files in "Read first".

---

## 1. Mission in one paragraph

Rebuild the PK-4 console as **SKALA-2000**, a single-purpose app with one window and one
fixed layout (no skins, no menu-bar panel, no configs). It must look exactly like the
existing desk: same design system, same layout, same behaviour. And it must be fast:
- **resizing, moving, minimising and full screen** must never stutter;
- **pressing a button** shows the cap going down in the next frame;
- **an idle console** costs close to nothing, even with many other apps running.

The existing SwiftUI implementation lags because of how it draws, not what it computes. You
keep its logic (about 250 tests) and replace its drawing with an AppKit + Core Animation
renderer.

## 2. The name

The owner chose: **"SKALA-2000 - Operator Console for Claude Code DD-72"**.

| Where | Text |
| --- | --- |
| App / bundle display name | `SKALA-2000` |
| Window title | `SKALA-2000 · Operator Console for Claude Code` |
| Header title plate (replaces `OPERATOR CONSOLE PK-4 · CLAUDE CODE`) | `OPERATOR CONSOLE SKALA-2000 · CLAUDE CODE` |
| Header subtitle (replaces `4 SESSIONS · DESK TYPE · 1972`) | `TYPE DD-72 · 4 SESSIONS · 1972` |
| Factory nameplate, 3 lines | `INSTRUMENT WORKS NO 4 · DRESDEN` / `CONSOLE SKALA-2000 DD-72 · SERIAL NO 0047 · 1972` / `220 V 50 HZ 0.6 KVA · MADE IN GDR` |
| Data folder | `~/Library/Application Support/SKALA-2000/` |
| Suggested bundle id | `com.leandrorossisampaio.skala2000` |

The plate wordings in rows 3–5 are **proposals**: show the owner a render and confirm
before you polish. "DD" reads as Dresden and "72" as 1972. The design system is still
called "PK-4 Console" in its own files; that is its source name and needs no change.

## 3. Where things are

- **Reference repository (read-only for you):**
  `/Users/leandrorossisampaio/Desktop/+++/LeandroGit/MacCommandCenter`, branch `pk4-console`,
  at commit `3742e8e` or later. GitHub: `leandrorsampaio/MacCommandCenter`, PR #1.
- **Everything for this handover** is in that repository under `docs/skala-2000/`:
  - `HANDOVER.md`: this file.
  - `design-system/`: the complete design system, copied from its claude.ai artifact:
    - `README.md` (the brand book), `10-interaction.md`, `20-signal-map.md`, `30-macos.md`;
    - `tokens.json`;
    - `components/*/README.md` (one per component) and `components/*/preview.html`;
    - `components/bundle.js` and `bundle.css` (a web reference implementation of every
      instrument, with exact gradients and timings);
    - `reference/live-console.html`: the whole desk as an interactive web page, running
      fake data. Open it in a browser.
    - `reference/signal-map.html`: every Claude Code field and the instrument it drives.
    - `reference/telemetry-inventory.html`: what Claude Code exposes, and what it doesn't.
  - `reference-renders/*.jpg`: the current desk rendered by the existing code, as your
    visual target:
    - `desk-full.jpg`: 2500×1800, day, the scripted day at 09:05;
    - `desk-night.jpg`, `lamp-test.jpg`, `mains-off.jpg`, `ivory.jpg`, `graphite.jpg`.
- **Source artifacts** (the same content, if you have the claude.ai Artifact tool):
  - design system: https://claude.ai/artifact/2LbGUNVv9wfMai69k5ysJ3
  - live console: https://claude.ai/artifact/MhXrUUphhFazoh3UA1bnsj
  - signal map: https://claude.ai/artifact/1vBxK7KYuTsshfEHgVh5br
  - telemetry inventory: https://claude.ai/artifact/Yasan1n1CuP3gS1cfAkdot
- **To regenerate reference renders** at full resolution, from the reference repository:
  `PK4_RENDER=/some/folder swift test --filter RenderTests` writes PNGs, including
  `desk-full.png` at 2500×1800.

**Precedence when sources disagree:**
1. the owner, now;
2. the reference **code** and section 10 of this file (the latest decisions);
3. the design system documents (written earlier; some details have since changed).

## 4. Read first, in this order

1. `docs/skala-2000/design-system/README.md`, `10-interaction.md`, `20-signal-map.md`,
   `30-macos.md`.
2. `docs/skala-2000/reference-renders/desk-full.jpg`. Keep it open.
3. In the reference repository:
   - `CONTRIBUTING.md` (module map);
   - `Sources/ConsoleKit/InstrumentID.swift`: every instrument id and the wiring;
   - `Sources/ConsoleKit/ConsoleSnapshot.swift`: what the view gets, plus every timing
     constant;
   - `Sources/ConsoleKit/ConsoleModel.swift` and its `+Commands`, `+Render` and
     `+Telemetry` files.
4. `Sources/PK4Skin/*.swift`: the SwiftUI drawing you replace. It is your spec for every
   gradient, radius and offset:
   - `PK4Desk.swift`: the layout and every panel;
   - `PK4Plates.swift`: enamel, plates, screws, bevels;
   - `PK4Lamps.swift`: lamp windows and lenses;
   - `PK4Readouts.swift`: nixies, drums, meters;
   - `PK4Controls.swift`: buttons, guard, key, selector, toggle, pencil;
   - `PK4Sound.swift`: sound engine and director;
   - `PK4Tokens.swift`: palette, fonts, sizes.
5. `Sources/MacCommandCenterApp/ConsoleHost.swift` and `ConsoleWindowController.swift`,
   for how the console is wired and hosted today.

## 5. What the product is (requirements)

**One window, one desk.**
- A fixed drawing, 2500 × 1800 desk units, scaled uniformly to the window.
- The window's aspect ratio is locked to 2500:1800, minimum width 1280 points.
- Resizable, movable, minimisable, zoomable, full screen. The intended home is full screen
  on a second display; the owner uses a Samsung 5K.
- Nothing ever re-lays itself out for the window size.

**No skins and no alternative layouts.** The three paint finishes (grey-green, ivory,
graphite) and the day/night theme are the only appearance options. Both come from the
design system, and both already exist.

**Everything the current console does, unchanged in behaviour:**
- four session slots and the alarm board: flash, buzzer, SIL, ACK, LAMP TEST, BUZZER TEST;
- the selected-session instruments: meters, nixies, lamp groups, drum totals;
- routine keys F1–F7, and guarded F8–F10 with key and hold;
- computer controls: SLEEP MODE, MONITOR OFF, FC1 and FC2 Keep Awake, battery and power
  source;
- MAINS and the power-up sequence;
- PRINT TEXT and its text-log window;
- the safety log, persistence of the desk's memory, the scripted demo day, VoiceOver and
  keyboard, and sounds.

**App behaviour.** These are proposals; confirm with the owner.
- A regular Dock app with a standard menu bar.
- Closing the window keeps the console running, so drum totals and hours in service keep
  counting. Clicking the Dock icon reopens the window; ⌘Q quits.
- Optional launch at login.
- A small Settings window. It can use SwiftUI, because it isn't the performance surface.
  It holds:
  - finish, sound on/off and volume, buzzer muted, lamp designators on/off;
  - scripted demo day on/off, launch at login;
  - hook status (last event received) with install and remove, and "open data folder".

**Direct distribution only.** It must read `~/.claude`, so no App Sandbox. Ad hoc signing
is fine for development; Developer ID later.

## 6. Stack and architecture (decided)

**Swift + AppKit + Core Animation. No SwiftUI on the desk.** Rust was considered and
rejected:
- the model costs almost nothing already: hidden, the whole current app with its Claude
  Code reader measured **0.52% of one core**;
- the lag is SwiftUI re-evaluating and re-laying-out about 600 decorated views on the main
  thread;
- Rust would also mean rewriting all tested logic and rebuilding every macOS integration
  (VoiceOver, password prompt, IOKit power, pmset, FSEvents, audio), with no speed gain.

Keep the reference's three-layer rule (see `30-macos.md`):

1. **Sources** (TelemetryKit and friends): read Claude Code and the Mac and emit typed
   `Reading`s with a time-to-live. Copy them.
2. **Console model** (ConsoleKit): a pure, clock-injected `@Observable` model that turns
   readings and operator intents into a `ConsoleSnapshot`. It holds every rule; it has no
   UI and no I/O. Copy it with its tests.
3. **Instruments** (new): a layer tree that renders a snapshot. It holds animation state
   only.

### Proposed package layout (Swift Package Manager, like the reference)

| Module | Origin | Notes |
| --- | --- | --- |
| `TelemetryKit` | copy | Claude Code readers, hooks parsing, IOKit machine source, `ClaudeSummary` |
| `ConsoleKit` | copy | model, rules, snapshot, instrument ids, nixie formatting, persistence types |
| `ConsoleRuntime` | copy, adapt | files (`console.json`, `safety.log`, `text.log`), driver timer, `SystemCommands` (pmset), `SessionCommands` (F-keys). Drop its `AppSupport` dependency: only `ConsoleFolder` used it; point it at `SKALA-2000/`. |
| `FakeSources` | copy | the scripted day, used by tests and demo mode |
| `DeskSound` | copy from `PK4Sound.swift` | engine and `PK4Director` (it needs `PK4Words` and `Haptic` from the skin: move them here) |
| `DeskArt` | **new** | tokens, fonts, Core Graphics painters for static art and sprites, layout table |
| `DeskView` | **new** | `NSView` hosting the layer tree: snapshot diff, animations, hit testing, keyboard, accessibility |
| `HookServer` | **new**, small | receives Claude Code hook events (section 12) |
| `KeepAwake` | adapt `CommandCore/SleepAssertion.swift` | FC1 and FC2 as IOPM assertions (section 11) |
| `SKALA2000App` | **new** | `NSApplication`, one window controller, menus, Settings, wiring (like `ConsoleHost`) |

Copy each copied module's tests too (`Tests/TelemetryKitTests`, `ConsoleKitTests`,
`ConsoleRuntimeTests`) and keep them green from the first commit.
- **Language mode:** the reference builds with the Swift 6.2 toolchain in language mode
  v5. Keep v5 for the copied code until it builds; strict concurrency can come later.
- **Renaming:** the instrument namespace is `enum PK4` (e.g. `PK4.silence`). Renaming it
  (to `Desk`, say) is optional: do it in one mechanical pass after tests are green, or
  leave it.
- **Fonts** (all OFL/Apache, licences included): copy `Resources/Fonts/PK4/*`, i.e.
  Barlow Condensed 600/700, Dosis 600, Nixie One, Permanent Marker, Caveat. Register them
  process-wide with CoreText. Digits are never set in a system font.
- **Build:** adapt `scripts/build-app.sh` (it assembles the `.app` and copies fonts), plus
  `swift format lint --recursive --strict`.

## 7. The renderer (the heart of the job)

The rule: **draw the art once; afterwards, only move, swap and fade layers.** Core
Animation interpolates animations in the render server, off your main thread and at the
display's refresh rate. Your main thread works only when the snapshot changes, and then
only on the layers that changed.

### 7.1 Coordinate space and scaling
- **Layer-hosting view.** One `NSView`: `wantsLayer = true`, your own root `CALayer`,
  `layerContentsRedrawPolicy = .never`, `acceptsFirstMouse(for:) → true`.
- **One desk layer.** Everything is laid out in 2500×1800 desk units, top-left origin
  (set `isGeometryFlipped` or convert once).
- **Scaling.** The view's size only changes one scale transform on the desk layer, inside
  `CATransaction.setDisableActions(true)`. Live resize is therefore a GPU transform, with
  no drawing and no layout.
- **Sharpness after resize.** When live resize ends (`viewDidEndLiveResize`), or 150 ms
  after the last size change, re-render the static art at the exact new pixel size. Do it
  off the main thread and swap it in, with a short crossfade if needed. Until then the old
  bitmap is scaled by the GPU, with `minificationFilter = .trilinear` where it helps.
- **Backing scale.** Track `backingScaleFactor` and screen changes (`viewDidChangeBackingProperties`)
  the same way.

### 7.2 Static art, drawn with Core Graphics off the main thread
- **Painters.** Write `DeskPainter` functions that draw into a `CGContext` with Core
  Graphics and Core Text. They are thread-safe, so render on a background queue.
- **What is static.** Everything that never changes, drawn in its dark/off state:
  - the desk and panel enamel: ground, grain, coat unevenness, lighting falloff, bevels,
    drop shadows, screws;
  - plates, tags, instruction plates, blanking plates;
  - bezels, and unlit lamp glass with its off-ink lettering;
  - nixie glass, drum windows;
  - meter housings and dials with scales;
  - button frames and holes, the guard's hazard well, the toggle plate, the selector dial;
  - the fuses, the ground bolt, the factory nameplate and the INV. No.
- **Resolution.** Render at `desk units × scale × backingScale`. One image per (theme,
  finish, scale), or one per panel if texture sizes or partial re-renders call for it.
  Cache the most recent one on disk (`~/Library/Caches/SKALA-2000/`), keyed by app
  version, theme, finish and pixel size, so launch shows the desk at once.
- **Porting.** Port the SwiftUI drawing faithfully from `PK4Skin`, including its
  gradients, radial glows, bevel strokes and the enamel texture (`EnamelTexture` in
  `PK4Plates.swift` builds the grain; reproduce it or reuse its bitmap). The web
  `bundle.css` and `bundle.js` give the same recipes in CSS terms when the Swift is
  unclear.
- **Shadows:** bake them in. `CALayer.shadow*` at runtime is expressly not allowed,
  because it is expensive offscreen rendering.

### 7.3 Dynamic parts: small layers, pre-drawn sprites

| Instrument | Layers and images | Animation (timings from `10-interaction.md`) |
| --- | --- | --- |
| Lamp window (≈90) | one "lit" overlay per window: lit glass, the two hot spots, on-ink lettering, glow spill, all drawn per window because each has its own lettering | on: opacity 0→1, 90 ms ease-in; off: 1→0, 220 ms ease-out; **flash**: see below |
| Lens (8, on the round buttons) | lit overlay per colour | same |
| Push button cap (square) | cap-up image and lit-cap overlay; a darkening layer and a hole-shadow layer for "down" | down/up: scale 1↔0.89, brightness 1↔0.8 (darkening opacity), hole shadow on/off, 45 ms linear; lit 90/220 ms; **no-answer**: 6 blinks of 160 ms (brightness ×1.5), stepped |
| Round button cap | same idea | same |
| Nixie tube | one layer per tube; contents are glyph images (0–9, `:`, `.`, blank) with the halo baked in, regular and XL | swap; the old digit's ghost at 35% for 60 ms |
| Moving-coil needle (3) | needle sprite, anchor at the pivot | spring rotation: response 0.55, damping 0.55 (≈700 ms, one overshoot); on power off, fall to zero, 900 ms ease-in |
| Edgewise pointer (battery) | pointer sprite | spring: response 0.45, damping 0.65 |
| Drum wheel (6 per counter, 5 counters) | a digit-strip sprite in a masked window | roll **forward** only, 320 ms spring with a slight overshoot, +45 ms stagger per wheel leftward; wrap 9→0 by snapping the strip back without animation after the roll; a `tick` sound per wheel |
| Guard flap (F8, F9, F10) | translucent red acrylic sprite, anchor at the top edge, perspective via `m34` | lift 0→121→112° in 260 ms; fall 112→0 with gravity, bounce 15° then 4°, 520 ms total |
| Key switch (F10) | slot sprite | rotate 90°, 140 ms, back-out (`CAMediaTimingFunction(controlPoints: 0.4, 1.6, 0.6, 1)`) |
| Rotary selector | knob sprite (knurl, bar, index, screw) rotating about the plate centre; the dial is static | 60° per detent, 170 ms back-out; at an end stop lean 6° and return with a dull click |
| MAINS toggle | lever sprite | scaleY +1↔−1, 100 ms ease-in-out, clunk at 60 ms |
| Buzzer grille | its own layer | while sounding, x ±0.6 at 25 Hz (`repeatCount = .infinity`); off with Reduce Motion |
| Pencil strips (4), PROGRAM BUILD card | a text image re-rendered on change | none; when editing a pencil, place a real borderless `NSTextField` over it, 12 characters maximum |

**Flash** is the one place the reference burns CPU: every flashing lamp runs its own 30 fps
`TimelineView` on the main thread. Do it as a single `CAKeyframeAnimation` on the lit
layer's opacity:
- keyTimes `[0, 0.16, 0.5, 0.9, 1]`, values `[0, 1, 1, 0, 0]`, period 0.5 s (1.0 s with
  Reduce Motion), `repeatCount = .infinity`;
- the lettering takes the lamp's light for the first 60% of each period;
- **all flashing lamps are in phase:** set every flash animation's `beginTime` to the same
  phase origin, e.g. `CACurrentMediaTime()` rounded down to a multiple of the period,
  converted into the layer's time.

**The snapshot bridge.**
1. Observe `ConsoleModel.snapshot` with `withObservationTracking`, re-arming after each
   change as `ConsoleWindowController.follow()` does in the reference.
2. Diff old against new: lamps, nixies, meters, drums, buttons, guards, keys, selector,
   mains, finish, pencils, program build, buzzer.
3. Touch only the changed layers, in one `CATransaction`.

The model already coalesces to 10 snapshots a second and throttles each nixie readout to
4 digit changes a second, so the view needs no timers of its own. Sound is driven by the
same diff through `PK4Director`.

**Themes.**
- Night follows the system's Dark appearance: watch `effectiveAppearance`.
- A theme or finish change re-renders the art off the main thread and swaps it in.
- Increase Contrast: unlit glass one step darker, and lettering on unlit glass switches to
  `engraving`.
- Reduce Motion: needles, pointers, wheels, flap, key and knob jump to their targets; the
  flash slows to 1 Hz.

**Power-up sequence** (model-driven; the view just renders it):
1. MAINS clunk.
2. +250 ms: POWER ON.
3. Nixie rows strike top to bottom, 40 ms apart, 120 ms of all eights each.
4. The needles rise.
5. A 1000 ms lamp test with an 80 ms buzzer chirp.
6. Live data.

## 8. Input, keyboard and accessibility

**Hit testing: explicit, never derived from drawing.**
- Keep a table of control rectangles in desk units, each with its id and kind: push
  button, round button, guard flap, key, selector (plus its four numeral hotspots),
  toggle, pencil.
- Convert the mouse point through the inverse desk transform and look it up.
- A unit test must prove that no two control rectangles overlap and that every rectangle
  lies inside its panel.
- This is the fix for the worst bug the reference had (section 14).

**Press semantics.**
- Mouse-down on a button sends `.press(id)` and shows the cap down in the same frame, with
  a click.
- Mouse-up **anywhere** sends `.release(id)`: dragging off the cap still sends, because a
  real button has no cancel.
- Track the pressed control from down to up; a release must never be lost.
- Guarded buttons work only with the guard up.
- The key turns only with the guard up.
- Hold-to-fire is the model's job (2 s, then a relay clunk; nothing visual).

**Selector.** Clicking a numeral walks the knob there one detent at a time, 110 ms apart.
Clicking the right half turns it clockwise and the left half back; it stops at 1 and 4.

**Keyboard.**
- Tab moves through the controls in panel order A→E: push and round buttons, guard flaps,
  key, selector, MAINS, pencils.
- Space or Return presses, down on keydown and up on keyup; the arrows turn the selector.
- The focus ring is a layer: 3 pt `lamp-amber-on`, offset 3 pt, shown only when focus came
  from the keyboard. **A mouse click never moves keyboard focus.**
- Guarded buttons are not focusable while their guard is closed.

**VoiceOver.**
- Every instrument is one accessibility element (`NSAccessibilityElement` children of the
  desk view), with the plate text as label and the value in words. `PK4Words` in
  `PK4Desk.swift` has the wording: "dark", "lit", "alarm, unacknowledged", "62 percent",
  "no reading".
- Panels are groups, ordered A, B, C, D, E.
- An alarm posts an `NSAccessibility` announcement when it is raised.
- Buttons expose a press action; the selector is adjustable.

## 9. The desk: layout and instruments

**Sources of truth for positions.** `PK4Desk.swift` (the SwiftUI layout) and
`reference-renders/desk-full.jpg`. Reproduce positions exactly, and don't approximate them
by eye.

**Recommended: export them.** In your repo, add a dev-only tool target that contains a
copy of the reference `PK4Skin` sources. Tag each instrument with an anchor preference,
render the desk with `ImageRenderer` at 2500×1800, and write `layout.json`: instrument id →
rect in desk units. Check `layout.json` in; both the painters and the hit table use it.
The same tool can produce golden reference images for comparison tests.

**Desk geometry.**
- Desk padding 22, gap 16.
- A header row, then three columns:
  - **A (650 wide)** over **E**. E takes its natural height; A takes the rest.
  - **B (1190 wide)** takes the full height.
  - **C (580 wide)** over **D**. C takes its natural height; D takes the rest.
- Internal spacing:
  - panel A: 30 between groups, 16 between annunciator rows;
  - panel B: 30 between groups, padding 18/26;
  - panel C: 26;
  - panel D: 30;
  - panel E: 26.

**Check it fits.** An earlier version overflowed 1800 units and clipped the header. Assert
in a test that every panel's content fits its column.

**Panels.**
- **Header:**
  - screws;
  - title plate and subtitle (section 2);
  - PROGRAM BUILD: a typed paper card showing the highest Claude Code version among
    running sessions;
  - the riveted aluminium factory nameplate (section 2);
  - `INV. No 0417` in red stockroom marker, rotated −3°.
- **A · All sessions — annunciator:**
  - session numerals 1–4, and a pencil strip per slot (a project name, 12 characters,
    handwritten);
  - 8 rows × 4 lamp windows: RUN (white), BUSY (green), WAIT (red, alarm), DONE (green),
    AGENT (white), BKGD (white), BLOCK (red, alarm), CMPCT (amber);
  - an instruction plate;
  - nixies: SESSIONS RUNNING, SESSIONS BUSY;
  - the buzzer grille, then **SIL, ACK (amber cap), TEST, BZR (BUZZER TEST)**.
- **B · Selected session — instruments:**
  - left column: **SELECTED** (XL nixie, plate below it), then the **session selector**,
    then **PRT** (PRINT TEXT);
  - meters: CONTEXT REMAINING (red zone 0–20%), with the 200K and 1M lamps under it; API
    SHARE OF TIME; TOOL SHARE OF TIME;
  - nixies, 8 tubes each: CONTEXT USED, INPUT, OUTPUT, THINKING, CACHE READ ×1000, CACHE
    WRITTEN ×1000;
  - the right nixie column, **all six the width of COST**: QUEUE DEPTH `000000`, TOOL
    CALLS `000000`, LAST TURN `0000:00`, TURN MESSAGES `000000`, SESSION UPTIME `0000:00`,
    COST, LAST CHECKPOINT `0000.00`;
  - lamp groups (colour in brackets):
    - PERMISSION MODE: Default, Accept edits, Plan, Auto (amber), Bypass (red)
    - EFFORT: **Low (green), Medium (green), High (amber), X-high (amber), Max (amber),
      Ultra code (red)**
    - MODEL: **Opus, Sonnet, Haiku, Fable, Other (amber)**
    - MODE: Normal, Other mode (amber)
    - KIND: Interactive, Detached
    - SERVICE TIER: Standard, Other tier (amber)
    - WARNINGS: Price unknown (red), Data stale (red, alarm), Subagent active, Pre-compact
      (amber)
  - drum counters: TOTAL COST $, TOTAL OUTPUT ×1000, LINES ADDED, LINES REMOVED, plus two
    blanking plates for the quota;
  - DISRUPTIVE COMMANDS: COMMAND GOES TO SESSION (nixie), an instruction plate, and
    guarded F8, F9 and **F10 END SESSION** (with its key).
- **C · Control — selected session:**
  - COMMAND GOES TO SESSION (XL nixie);
  - ROUTINE COMMANDS: a 3×3 grid: F1 Open folder, F2 Terminal here, F3 Copy resume, F4
    Safety log, F5 Show transcript, F6 `[Function 6]`, F7 `[Function 7]`, and two SPARE
    blanking plates;
  - an instruction plate.
- **D · Computer controls:**
  - round buttons, each with ON (green) and OFF (white) lenses: SLP Sleep mode, MON Turn
    off monitor, FC1 Awake · display on, FC2 Awake · display off;
  - an instruction plate;
  - the BATTERY % edgewise meter;
  - the POWER SOURCE lamps: On mains (green), On battery (amber), Charging (white), Batt
    low (red, alarm).
- **E · Power and service:**
  - the MAINS 220 V 50 Hz toggle, with the POWER ON lamp (green);
  - HOURS IN SERVICE (drum);
  - the ground bolt with the IEC earth symbol;
  - six decorative fuses.
  - **No spare-lamps strip** (removed).

The exact lamp designators (HL1–HL73), tags (SB, HG, PA, PC, SA, FU) and ids are in
`PK4Desk.swift` and `InstrumentID.swift`.

## 10. Behaviour: the rules, and the latest decisions

The model owns every rule. Read `ConsoleKit` and its tests rather than re-deriving them.
- **Four slots.** A new session takes the lowest free slot and keeps it; a fifth is
  refused and logged once.
- **Alarm table.** A new alarm flashes and buzzes. SILENCE stops the buzzer until the next
  new alarm. ACK turns every flashing window steady. When its cause clears, the window
  goes off. See `Annunciator/README.md`.
- **The lamp answers the machine, never the finger.**
  - Buttons go `idle → down → sent → confirmed | noAnswer → idle`. Send on release.
  - They confirm only from an observed result; there's no answer after 3 s (F10 gets 90 s,
    below).
  - A confirm glows 0.6 s, or 1.5 s on a guarded button.
- **Guarded commands.** Lift the guard, turn the key where there is one, hold for 2 s. The
  guard falls by itself after 5 s untouched.
- **Staleness.** Every reading has a time-to-live. A source that stops reporting goes dark
  and raises DATA STALE; nothing stale is ever left lit.
- **Drum counters** count positive deltas only, roll forward only, and persist.
- **Nixies** are fixed width, with leading zeros; they show all nines on overflow.

**Decisions made after the design system was written** (the code has them; build them
this way):
- **Meters** with nothing to measure rest exactly **on zero**, not below it. The model
  still reports −0.03 as "no reading"; the view clamps to 0…1, and VoiceOver says "no
  reading".
- **LAMP TEST** lights **every lamp, every button cap and every digit of every nixie
  (8s)**, while held and for **at least 1.5 s** after a click. The nixies' 4-per-second
  throttle is bypassed when the test starts and ends.
- **BUZZER TEST** (new button) sounds the buzzer while held, for at least 1.5 s, **even
  when BUZZER MUTED is on**. Its cap burns while it sounds. It sends nothing and logs no
  command.
- **The routine keys:**
  - F1 opens the session's folder in Finder.
  - F2 opens Terminal there.
  - F3 copies `cd '<cwd>' && claude --resume <session-id>`, with the folder single-quoted.
  - F4 opens the safety log.
  - F5 reveals the transcript in Finder.
  - F6–F9 stay **unassigned on purpose**. `SIGSTOP`/`SIGCONT` was tried for two of them
    and rejected: `SIGCONT` resumes a terminal's job in the background, where it stops
    again at the first key.
- **F10 END SESSION:**
  1. guard, key, 2 s hold;
  2. a check that the pid still belongs to that session (its session file names it);
  3. **the Mac's password or Touch ID** (LocalAuthentication, `.deviceOwnerAuthentication`,
     reason "end the Claude Code session in “<folder>”");
  4. `SIGTERM`, then watch up to 2.5 s for the process to go.

  It confirms only when the session is gone. Its command timeout is 93 s, to allow for
  typing the password. See `SessionCommands.swift` and its tests.
- **EFFORT** has six windows, above. Claude Code writes `low`, `medium`, `high`, `xhigh`
  and `max`. **Ultracode** is written as `xhigh` in each record. The transcript marks it
  with `attachment` records of type `ultra_effort_enter` and `ultra_effort_exit`, and
  `TranscriptAccumulator` turns those into effort `ultracode`.
- **MODEL** gains **FABLE**, matched as a substring like the others: `claude-fable-5-1`
  lights FABLE, and anything unrecognised lights OTHER.
- **SELECTED** sits above the selector, with its plate under the tubes.
- **The maker's plate** says Dresden and Made in GDR (section 2).
- **Demo mode** plays the scripted day (`FakeSources.FakeDay.opening(at:)`): it opens at
  08:55 on the wall clock and catches up to real time. It uses its own data folder (`…/Demo`).
  In demo mode, the only buttons that reach outside the desk are FC1 and FC2 (Keep Awake).
- **Open question:** the owner asked whether 200K/1M are redundant next to MODEL. My
  recommendation was to keep them, because the same model runs with either window
  (`[1m]`) and the window sets what the context needle means. Unconfirmed, so ask.

## 11. Machine integrations

- **Power** (battery %, source, charging, low): `TelemetryKit/MachineSource.swift` (IOKit),
  copy as-is.
- **SLEEP MODE** runs `pmset sleepnow`; **MONITOR OFF** runs `pmset displaysleepnow`. Both
  are in `ConsoleRuntime/SystemCommands.swift`. Their lenses answer from observed state.
- **FC1 and FC2 are Keep Awake.** The reference routed them through its config system,
  which you don't have. Implement them with IOPM assertions (adapt
  `CommandCore/SleepAssertion.swift`):
  - FC1 "Awake · display on": an assertion of type `PreventUserIdleDisplaySleep`, which
    also keeps the system awake;
  - FC2 "Awake · display off": `PreventUserIdleSystemSleep` only.

  Each toggles, and the two are mutually exclusive. Report the state as the readings
  `keepAwakeDisplayOn` and `keepAwakeDisplayOff` (see `keepAwakeReadings()` in
  `ConsoleHost.swift`), so the lenses answer the machine.
- **Sleep and wake, display changes.** The owner runs a MacBook **lid-closed on AC with an
  external Samsung 5K**; losing the monitor forces sleep. Handle `NSWorkspace` sleep/wake
  and screen-change notifications gracefully: re-render the art for the new backing
  scale, and don't flood the model on wake.

## 12. Claude Code telemetry: facts and pitfalls (hard-won)

All readers exist in `TelemetryKit/Claude/`. Copy them, and don't re-derive.
- **`claude agents --json` is the only authority on which sessions exist.**
  - Each run costs about 0.1 s of CPU, so polling it every 2 s would be 5% of a core. The
    feed (`ClaudeCodeFeed`) runs it **on file events** under `~/.claude` (FSEvents on the
    root; `sessions/` files are rewritten the moment a status flips) and on a **30 s
    heartbeat**, never more than once a second.
  - Between runs it reports the last good answer; after a failed run it reports nothing,
    which becomes DATA STALE.
- **Transcripts** (`~/.claude/projects/<slug>/<session-id>.jsonl`) can run to tens of MB.
  - **Follow** them: read the new bytes only. Never re-read or tail-window them; the
    `cost-state` checkpoint can sit megabytes back from the end.
  - Deduplicate usage by `requestId`: one request is written as several records, and
    counting per record inflates totals 2.4×.
  - The **context window** (200K or 1M) comes from the `[1m]` suffix on the billed model,
    in the identity attachment or `cost-state`. The assistant record leaves it off.
- **Jobs:** `~/.claude/jobs/*/state.json` gives `tempo == "blocked"` → BLOCKED, and
  `needs` goes to the text log.
- **Hooks** give what disk can't: waiting, turn done, subagent done, start and end,
  compaction, tool use.
  - The reference's installer (`scripts/install-claude-hooks.sh` with
    `scripts/claude-hooks.json`) adds **12 events**: SessionStart, SessionEnd,
    UserPromptSubmit, Stop, SubagentStart, SubagentStop, Notification, PermissionRequest,
    PostToolUse, PostToolUseFailure, PreCompact, PostCompact.
  - Each is an `async: true` command hook, so Claude Code never waits on it. It pipes the
    hook's JSON to the app.
  - `ClaudeHooks.swift` parses it: `session_id`; `agent_id`/`agent_type` for subagents;
    `notification_type`; `source` on SessionStart; `reason` on SessionEnd. Prompts that
    start with `<task-notification>` are machine-written and must not count as the
    operator answering.
  - Payloads can be megabytes (PostToolUse carries the tool output): parse off the main
    thread, cap at 8 MB.
- **Your hook receiver.** The reference receives hooks on its loopback HTTP API
  (`127.0.0.1:8787`, `POST /v1/events/claude`, header `X-MCC-Client: 1`). The old app may
  still be running, so **don't collide with it**.
  - Recommended: a **Unix domain socket** in the data folder, mode 0600, with the hook
    command `curl -sS -m 2 --unix-socket "<path>" -H 'X-SKALA-Client: 1' --data-binary @-
    http://localhost/v1/events/claude`. A browser can't reach it, it needs no port, and it
    can't clash.
  - Otherwise, a different loopback port with the same header guard (no `Origin`,
    required custom header).
  - Ship your own installer with **its own marker**, so both apps' hooks can live
    side by side in `~/.claude/settings.json`. Back up settings before writing, as the
    reference installer does.
- **The panel's Keep Awake integration** and `ClaudeSummary` (the old menu bar panel's
  signals) aren't needed. The feed runs only while MAINS is on.

## 13. Security and privacy rules (non-negotiable)

- **Never** read, store, log or display `ide.authToken`, and never open
  `~/.claude/ide/*.lock`.
- **Never** open `~/.claude/sessions/*.key`.
- **Never** read, store or log `providerEnv` from job files.
- Verbatim prompt text (`lastPrompt`) and job `detail` go to the text log on PRINT TEXT
  only, never onto the desk surface.
- Session ids and pids are join keys: they go to the safety log and are never displayed.
- **The hook receiver:**
  - accepts connections from this user only;
  - requires the custom header;
  - rejects requests carrying `Origin`;
  - caps the size at 8 MB;
  - parses defensively. A malformed event costs nothing.
- **Don't send the owner's email or any local data** to external services.

## 14. Lessons from the reference: do not repeat these

1. **Invisible views stole clicks** (the worst bug). Each panel's enamel had two lighting
   gradients drawn far past its edges and clipped. In SwiftUI, clipped overflow is still
   hit-testable, so each panel drawn later lay invisibly over its neighbour's buttons.
   SIL, ACK, TEST and F1–F7 never received a click. Your explicit hit table makes this
   impossible; keep the non-overlap test.
2. **Every click moved keyboard focus**, drawing the amber ring on whatever was clicked.
   The ring is for the keyboard only.
3. **The first click on an inactive window was swallowed.** The console usually lives on
   another display, so accept first mouse.
4. **A flashing lamp ran its own 30 fps timer on the main thread.** Use render-server
   animations.
5. **A lost release left a cap stuck down**, ignoring every later press. Release on
   mouse-up anywhere, and on window resignation.
6. **The desk grew past 1800 units** and clipped its header. Test that the layout fits.
7. **Model deadline loop:** a coalesced publish plus a held-back nixie made
   `nextDeadline` report "due now" forever. It's fixed with `max(nixieDue, nextPublish)`.
   Keep that code and its test.
8. **Positions judged by eye drifted.** Measure them (section 9).
9. **`TextField` doesn't render in `ImageRenderer`** (relevant only to your export tool).

## 15. Performance budget (acceptance criteria)

Measure on the owner's Mac (Apple silicon, macOS 26), app process CPU as % of one core,
averaged over 60 s after 10 s of warm-up. Record every number in `PERFORMANCE.md`, and
compare with the reference app. Hidden, the reference measured 0.52% (all of it, including
the Claude feed). Visible, earlier builds measured 2–9%, and resizing visibly stutters.

| Scenario | Target |
| --- | --- |
| Visible, idle (MAINS on, sessions quiet, no alarms) | **≤ 0.3%** |
| Four lamps flashing, buzzer silenced | ≤ 0.5% |
| Busy telemetry (several changes a second) | ≤ 2% |
| Hidden or occluded | ≤ 0.3% (the feed dominates) |
| Live resize, 1280 wide to 5K full screen | no dropped frames at 120 Hz (Instruments "Animation Hitches"); ≤ 2 ms of main-thread work per resize frame |
| Click → cap visibly down | next frame (≤ 8 ms on ProMotion, ≤ 16 ms at 60 Hz) |
| Launch → interactive desk | ≤ 0.5 s warm, ≤ 1.5 s cold |
| Memory, 5K full screen | ≤ 250 MB |

**Tools.** Instruments (Time Profiler, Animation Hitches, Core Animation), `os_signpost`
around snapshot apply and art rendering, and a `ps`-based CPU sampling script (the
reference session used `ps -o time=` deltas over 60 s).

## 16. Plan: phases, each ending in a report to the owner

Work in phases. End each with a short report: what works, measured numbers, open
questions, screenshots or renders. Then wait for a go.

0. **Bootstrap.**
   - New repo; copy TelemetryKit, ConsoleKit, ConsoleRuntime, FakeSources and their tests;
     all green.
   - Fonts, the build script, lint.
   - An app that opens one aspect-locked window.
1. **Spike (go/no-go).**
   - Static art for the whole desk. Fidelity may be rough at this stage, but it must have
     every panel, plate, window and dial in the right place.
   - A layer-hosting view with transform scaling.
   - Ten live lamps flashing in phase, one needle, one drum, one working push button.
   - **Measure** resize, idle and flash CPU against the reference, and report before going
     on.
2. **Art fidelity.**
   - Port every painter; both themes and all three finishes.
   - Golden-image comparisons against the reference renders, with a perceptual or SSIM
     tolerance; the owner judges the final look.
   - Re-render after resize; the disk cache.
3. **Every live instrument.** Sections 7.3 and 10: power-up, lamp test, buzzer test, the
   no-answer blink, guards, key, selector, toggle, pencils, nixie ghosts, drums.
4. **Input.** The hit table with its tests, press semantics, keyboard focus, VoiceOver,
   Reduce Motion, Increase Contrast.
5. **Wiring.** The model and runtime, the feed, the hook receiver, the machine source,
   Keep Awake, pmset, the F-keys (including F10 authentication), sound, the safety and
   text logs (with the PRINT TEXT log window), persistence, demo mode.
6. **App shell.** Menus, Settings, launch at login, hook install and status, and a
   first-run offer to import the old desk's memory (below).
7. **Hardening.**
   - All budgets met and documented.
   - 5K full screen, sleep and wake, monitor unplug.
   - Dark mode switching; long runs (a day of demo mode) without drift or growth.
   - README, CHANGELOG, packaging.

## 17. Decisions to confirm with the owner early

- The plate wordings in section 2.
- App lifecycle (section 5): Dock app, keep running when the window closes.
- **Importing the old desk's memory.** The reference keeps drum totals, hours in service,
  pencils, selector, finish and buzzer-muted in
  `~/Library/Application Support/MacCommandCenter/PK-4/console.json`. Offer a one-time
  copy into `SKALA-2000/` so the counters carry on. Copy that file only, never the logs.
- The hook transport (a socket, recommended) and whether to keep the old app's hooks
  installed in parallel.
- Whether to keep 200K/1M (section 10).

## 18. Working with this owner

- **Who they are.** Leandro. They write short, informal messages, often with typos, and
  often send a screenshot with one line ("this is wrong", "make these the same width").
  They care intensely about the look and about snappiness.
- **They want decisions.** They often say "decide for me". Then decide, state the
  decision in one line, and move on; ask only when a choice is genuinely theirs.
- **Honesty.** Report failures with the evidence. Never claim a fix works before it's
  verified. If a problem can't be reproduced, say so plainly and instrument it: in the
  reference, a click recorder plus reading the logs found the stolen-clicks bug.
- **Asking for confirmation.** Confirm hard-to-reverse or outward-facing actions: pushing,
  installing hooks, editing `~/.claude/settings.json`, anything that signals processes.
  **Commit or push only when asked.**
- **Git.** On GitHub the owner is `leandrorsampaio`. On this Mac the active `gh` account
  may be a different one (`LeandroSampaioSolenis`), which gets a 403 on push. Push with
  the owner's token without switching accounts:
  `GH_TOKEN="$(gh auth token --user leandrorsampaio)" git push`, and the same prefix for
  `gh pr create`.
- **Commit style.** Descriptive prose commit messages that explain why, like the
  reference's history.
- **Lettering.** English, uppercase, terse. Only the middle dot · as punctuation on
  plates. No SF Symbols, emoji or pictograms anywhere on the desk.

## 19. Quick reference

| Thing | Where in the reference repo |
| --- | --- |
| Instrument ids and wiring | `Sources/ConsoleKit/InstrumentID.swift` |
| Snapshot and timings | `Sources/ConsoleKit/ConsoleSnapshot.swift` (`ConsoleTiming`) |
| Rules | `Sources/ConsoleKit/ConsoleModel*.swift`, `AlarmBoard.swift`, `SlotTable.swift`, `SessionState.swift` |
| Model tests (scripted day, alarms, commands, mains) | `Tests/ConsoleKitTests/` |
| Claude Code readers | `Sources/TelemetryKit/Claude/`, `TranscriptAccumulator.swift`, `ClaudeHooks.swift` |
| Mac power | `Sources/TelemetryKit/MachineSource.swift` |
| Files, logs, driver, F-keys, pmset | `Sources/ConsoleRuntime/` |
| Scripted day | `Sources/FakeSources/FakeDay.swift` |
| Drawing spec | `Sources/PK4Skin/*.swift` |
| Sounds | `Sources/PK4Skin/PK4Sound.swift` (RBJ band-pass noise bursts; 420 Hz square buzzer) |
| App wiring today | `Sources/MacCommandCenterApp/ConsoleHost.swift`, `ConsoleWindowController.swift` |
| Keep Awake assertions | `Sources/CommandCore/SleepAssertion.swift` |
| Loopback HTTP (if you avoid sockets) | `Sources/CommandCore/HTTPKit.swift`, `ControlServer.swift` |
| Hook installer | `scripts/install-claude-hooks.sh`, `scripts/claude-hooks.json` |
| App bundle build | `scripts/build-app.sh` |
| Fonts and licences | `Resources/Fonts/PK4/` |
| Live-data probes (opt-in) | `PK4_LIVE=1 swift test` (real `~/.claude`) |
| Reference renders | `PK4_RENDER=<dir> swift test --filter RenderTests` |
