# Interaction, motion and sound

Every interactive behaviour is demonstrated live in the component previews (click them) and implemented in `components/bundle.js` as a reference. The numbers here are the specification; the web code is only an illustration of them.

## What the pointer can do

Only five things respond: pushbuttons, the guard flap and key, the rotary selector, the mains toggle, the pencil strips. Lamps, windows, readouts, counters and meters never respond to hover or click. The cursor stays an arrow everywhere; there are no hover states (a steel panel does not know a finger is near it).

Keyboard: Tab moves through the five kinds of control in panel order A to E; Space or Return presses a button (down on keydown, up on keyup); arrows turn the selector (it stops at 1 and 4). Guarded buttons are not focusable while their guard is closed. Focus ring: 3pt `lamp-amber-on`, offset 3pt.

## Timing table

| Thing | Behaviour | Duration | Curve |
| --- | --- | --- | --- |
| Lamp on | lit layer opacity 0 → 1 | 90 ms | ease-in |
| Lamp off | 1 → 0 | 220 ms | ease-out |
| Lettering on glass and caps | `ink-*-off` ↔ `ink-*-on`, halo on light ink | with its lamp: 90 / 220 ms | same as lamp |
| Alarm flash | 2 Hz; rise 80, hold to 250, decay 200, dark 50 | 500 ms period | linear segments, one shared clock |
| No-answer blink | cap brightness ×1.5, 6 blinks | 160 ms each | stepped |
| Button cap (square and round) | sinks into its hole: scale 1 → 0.89, brightness 1 → 0.8, own shadow off, hole shadow on; no translation | 45 ms each way | linear |
| Guard lift | rotate about top edge 0 → 121° → 112° | 260 ms | ease-out |
| Guard fall | 112° → 0 (270 ms, accelerating), bounce 15°, bounce 4°; on click of the lifted flap, after 5 s idle, or on confirm | 520 ms | gravity segments |
| Key switch | rotate 90° | 140 ms | back-out (1.6) |
| Hold-to-fire (guarded buttons) | no visual at all; cap stays sunk; relay `clunk` at 2000 ms, then send | 2000 ms | none |
| Selector detent | rotate 60° about the plate centre; only knurl, bar, index and screw turn; no wrap | 170 ms | back-out (1.7) |
| Selector at end stop | lean 6° on the pin and return, dull click | 90 + 170 ms | same |
| Selector to a clicked numeral | one detent at a time | 110 ms apart | same |
| Mains toggle | lever scaleY +1 ↔ −1 through 0 (foreshortening) | 100 ms | ease-in-out; clunk at 60 ms |
| Nixie digit | swap; old digit ghost at 35% | 60 ms | none |
| Drum wheel | roll forward to digit | 320 ms, +45 ms stagger per wheel | spring, slight overshoot |
| Meter needle | rotate to value, one overshoot ≈6% | ≈700 ms | spring response 0.55, damping 0.55 |
| Edgewise pointer | slide to value | 500 ms | spring response 0.45, damping 0.65 |
| Needles on power-off | fall to left stop | 900 ms | ease-in |

Reduce Motion: needles, pointers, wheels, flap, key and knob jump to their target; flash slows to 1 Hz; nixie flicker off. Filament timing stays (it is a fade, not motion).

## Command state machine (every button)

`idle → down → sent → confirmed | no-answer → idle`. Down and up are separate events with separate clicks. Sending happens on up. While `sent`, further presses are ignored. `confirmed` is driven only by the observed state of the machine (the next telemetry read or the command's own result), never by the fact that the command was dispatched. `no-answer` after 3000 ms.

## Power-up sequence

1. MAINS up: lever throw, loud clunk. 2. +250 ms POWER ON window. 3. Nixie rows strike top to bottom, 40 ms apart, each showing all eights for 120 ms. 4. All needles rise from the stop together. 5. Automatic lamp test for 1000 ms (every window, lens and button cap lit, buzzer chirps 80 ms). 6. Live data. Drum counters show their stored values from the first frame.

## Sound

Five sources, all short, all dry, mixed mono, played at the position of nothing in particular (no spatial audio).

| Sound | When | Character |
| --- | --- | --- |
| `click` | button contact, down and up | 18 ms noise burst, band-pass 2.6 kHz |
| `clunk` | relay on every window change, confirm, selector detent, key, guard, toggle (loudest) | 70 ms burst, band-pass 320 Hz |
| `tick` | each drum wheel that moves | 10 ms burst, 1.4 kHz, quiet |
| `buzzer` | the signals below, once each as the state begins; continuous only while BUZZER TEST is held | 420 Hz square wave, low gain, 3 ms edges |
| `beep` | LOW CONTEXT coming on (under 5% of the context left); a plan usage window's NEAR LIMIT (80%) or AT LIMIT (95%) coming on | 150 ms sine, 1.6 kHz, soft ends: higher and rounder than the buzzer, never taken for it |

**Signals.** DONE: one buzz, 300 ms. WAIT: two quick buzzes, 110 ms on and 90 off. CMPCT: three quick buzzes. BLOCK, DATA STALE and BATT LOW: one long buzz, 1.2 s. LOW CONTEXT: one beep. Each plays once, in turn, never over another. SILENCE is a mode: while on, no signal plays and its cap and the SILENCED lamp (amber, under the buzzer) burn; pressed again, it ends. BUZZER MUTED holds the signals back too, and lights SILENCED.

More than eight clunks within 100 ms collapse into one (a selector change relights many lamps). Preferences: master volume, BUZZER MUTED. The system mute switch is respected. Visual alarm behaviour never depends on sound.
