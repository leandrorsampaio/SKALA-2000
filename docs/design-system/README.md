# PK-4 Console

Instruments for watching four thinking machines at once.

PK-4 is the design system of a native macOS app that shows Claude Code telemetry as a physical operator console, as if it had been built in 1972 by an instrument works that normally made reactor control desks. Nothing in it is a "UI": there are lamps, counters, meters, switches and buttons bolted into steel plates. The implementer's job is to reproduce hardware, not to restyle macOS controls.

The assembled console, built only from the instruments in this system, fully interactive with fake telemetry running through it (layout and behaviour reference, all five sub-panels A to E): https://claude.ai/artifact/MhXrUUphhFazoh3UA1bnsj

## Principles

1. **Reliable before pleasant.** Every reading has one fixed place. Nothing moves, resizes, scrolls, collapses, shows a tooltip or opens a popover. If a value has no instrument, it is not shown.
2. **The lamp answers the machine, never the finger.** A press moves the cap and makes a click. Light changes only when the machine confirms the new state. No answer in 3 s is shown as a fault.
3. **One meaning per colour.** Red: the operator must act. Amber: abnormal, not urgent. Green: working, on, power present. White: plain status. Lettering and position always carry the same meaning as the colour.
4. **A dead source goes dark.** Every signal has a time-to-live. A session that stops reporting loses its lamps and raises DATA STALE; a stale number is never left standing.
5. **Dangerous things take three acts.** Guard, key, hold. No keyboard shortcuts, no confirmation dialogs.
6. **Cheap, sturdy, 1972.** Incandescent lamps, nixie tubes, drum counters, moving-coil meters, bakelite, enamel. No LEDs, no seven-segment digits, no dot matrix, no text display of any kind. Free text exists only as pencil on a paper strip.

## Voice and lettering

All lettering is uppercase, engraved or painted, and terse: a noun or a state, never a sentence, never punctuation except the middle dot. `WAITING FOR OPERATOR`, `LAMP TEST`, `CONTEXT REMAINING`, `ON MAINS`. Window lettering is abbreviated to six characters: RUN, BUSY, WAIT, DONE, AGENT, BKGD, BLOCK, CMPCT. Button caps are three or four letters: ACK, SIL, TEST, PRT, F1. Unknown functions are written in square brackets, `[FUNCTION 8]`, until named. Sentences appear only on yellow instruction plates and describe behaviour: `BUTTON LAMP LIGHTS ON CONFIRMATION FROM THE MACHINE, NOT ON PRESS`. English only.

Sub-panels are lettered and named: `A · ALL SESSIONS — ANNUNCIATOR`, `B · SELECTED SESSION — INSTRUMENTS`, `C · CONTROL — SELECTED SESSION`, `D · COMPUTER CONTROLS`, `E · POWER AND SERVICE`.

## Depth (one light, three levels)

The console is lit by one lamp above and to the left of the operator. Every part sits at one of three levels and is shaded accordingly; nothing is flat and nothing floats.

1. **Raised**: anything screwed onto the paint (label plates, tags, instruction plates, meter housings, dial plates, toggle plates, button frames, lens collars, whole sub-panels). Bright top and left edge, dark bottom edge, a short soft drop shadow (`plate-raise`, `panel-raise`).
2. **Flush**: the painted steel itself, with its texture.
3. **Recessed**: glass set behind a bezel (lamp windows, nixie filters, drum windows, meter dials), button caps in their holes, screw heads in their countersinks. The bezel is bevelled (light top-left, dark bottom-right) and throws a shadow onto the top of the glass (`recess`); the glass carries one diagonal sheen that never changes with state.

Engraved lettering is cut in: a dark line above each letter, a faint light line below.

## Panel finish (choose one per console)

Three paints are specified; pick one for the whole console, never mix. All three are **smooth sprayed satin enamel on flat steel**. There is no relief, no hammer pattern, no wrinkle, no speckle: a real control desk is flat paint, and it looks real because of three quiet things, in this order of importance:

1. **Room light falling off across the plate**: a soft highlight from the top-left corner (white, 20%, gone by 60% of the way across) and a soft darkening toward the bottom-right corner (black, 16%). Each sub-panel has its own, so plates read as separate sheets.
2. **Fine grain**: monochrome noise about one pixel in size, centred on mid-grey and composited in overlay mode so the paint colour stays exact; amplitude ±8% (grey-green), ±6% (ivory), ±15% (graphite). Visible only up close.
3. **Unevenness of the coat**: the same, at a scale of 150 to 200px, amplitude about ±10% at half strength. You should not be able to point at it.

| Finish | Ground | Border | Painted text |
| --- | --- | --- | --- |
| 1 Grey-green enamel (default) | `enamel-panel` | `enamel-edge` | `ink` |
| 2 Ivory enamel | `finish-ivory` | `finish-ivory-edge` | `ink-on-ivory` |
| 3 Matte graphite | `finish-graphite` | `finish-graphite-edge` | `ink-on-graphite` |

If a texture can be noticed from normal viewing distance, it is too strong.

The finish switch at the top of every component preview changes all of them, so each instrument can be judged on each paint.

## Materials (colour)

- **Paint**: one of the three finishes above. `enamel` is the desk under finish 1. Blanking plates are the same paint as their sub-panel, raised one level. Text painted on the panel uses that finish's ink.
- **Bakelite**: `bakelite` plates with `engraving` lettering; also round button caps, meter housings, fuse caps.
- **Metal**: `aluminium` collars, toggles, and the factory nameplate; `tag` + `tag-ink` for designators; `brass` for the ground bolt and bulb bases.
- **Paper**: `paper` pencil strips, `instruction` plates, `meter-face` dials, all with `tag-ink`.
- **Glass**: the four lamp colours, each with an `-off`, `-on` and `-hot` value (hot = the two soft bulb spots behind every lit window, the single centre of a lit cap). Lettering on glass is paint: light ink on red and green, dark ink on amber and white, never flipping; each has an `ink-*-off` and `ink-*-on` value so the ink takes on the lamp's light.
- **Glow**: `nixie-glass`, `nixie-glow`, `nixie-halo`. The `glow-*` shadows are the faint light a lamp spills onto the surrounding paint: wide, low, edge-less, stronger in the night theme. Nothing on the console has a neon outline.
- `stockroom-red` is for the hand-painted inventory number and nothing else.

Two themes: **day** (room lights on) and **night** (room lights dimmed: enamel darkens, unlit glass darkens, lit glass and nixies keep full value, so glow dominates). Map night to macOS Dark appearance.

## Type

Dosis 600 (`engraved`) for everything cut into bakelite or stamped on a tag; Barlow Condensed 600/700 (`label`) for everything painted on glass, caps, scales and enamel; Nixie One (`nixie`) for tube digits; Permanent Marker for the inventory number; Caveat for pencil. All five are OFL: bundle them in the app, never fall back to a system font for digits.

## Layout

The console is a fixed drawing 3352 units wide and 1800 tall, scaled uniformly to the window; aspect ratio locked; minimum window width 1280. SKALA-2000 has four columns: A (836) over E, B (1004), C (580) over D, and F (836), the Mac's own load; the figures that follow are the reference's first three. Desk padding 22, gap between sub-panels `space-4`, sub-panel padding `space-3`, gap between groups `space-5`. Three columns of equal height: A (650 wide) over E on the left; B (1190) alone in the middle, with generous spacing (34 between groups, 44 to 48 between instrument columns) and the disruptive commands as its last row; C (580) over D on the right. Side panels use 28 to 34 between groups. Instruments are never packed edge to edge: when in doubt, add space. Every control sits above its label plate, and its designator tag sits below the plate, `space-1` apart. Controls in a group align on a grid: 96px windows with `space-2` gaps, 112px button cells with `space-5` gaps.

Finish details that belong to the system: four domed slotted screws per sub-panel, each in a dark countersink with its slot at a random angle (never aligned); a riveted aluminium factory nameplate and a crooked `INV. No` in stockroom paint in the header. No wear marks or rings around controls.

## Iconography

None. The only symbols are the IEC earth symbol beside the ground bolt and digits. No SF Symbols, no emoji, no pictograms.

## Read next

`10-interaction.md` (states, motion, sound), `20-signal-map.md` (which Claude Code signal drives which instrument), `30-macos.md` (implementation notes for the native app).
