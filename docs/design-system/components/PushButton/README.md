The 64px square illuminated pushbutton: a dark metal frame, a black hole inside it, and a translucent cap with three or four painted letters that sits in the hole. Label plate and SB tag underneath.

**The cap goes into the hole; it does not slide down the panel.** At rest the cap fills the hole and stands proud: it throws a soft shadow (`cap-up`) down onto the frame and has a bright top edge. Pressed, it sinks: the cap shrinks to 89% about its centre so a ring of black hole wall appears around it, it darkens to 80%, its own shadow disappears, and the hole throws a hard shadow across its top and sides (`cap-down`). Nothing translates. Used for the routine commands F1 to F7 (acting on the selected session) and for SILENCE, ACKNOWLEDGE, LAMP TEST and PRINT TEXT.

**The rule of this console: the lamp answers the machine, never the finger.**

1. *Down* (pointer down or Space/Return): the cap sinks into the hole in 45 ms, contact `click`.
2. *Up*: the cap returns in 45 ms, second `click`, and the command is sent. The lamp does not change.
3. *Confirmed*: when the machine reports the new state, relay `clunk` and the lamp lights with filament timing (90 ms up). Latching functions stay lit while the state holds; momentary ones glow for 600 ms.
4. *No answer within 3 s*: the cap blinks six times at 6 Hz, `clunk`, and stays dark. Nothing else reports the failure, so this must not be skipped.

While a command is pending the button ignores further presses. Dragging off the cap before release still sends (a real button has no cancel).

**Tones.** Default cream; `amber` for ACKNOWLEDGE only; `red` only inside a GuardedButton. Every button sits on plain enamel: no rings, halos or wear marks around the frame.

**Cap lettering follows the window rule.** Cream and amber caps carry dark ink (`ink-white-*`, `ink-amber-*`), red caps light ink (`ink-red-*`), lit or not, pressed or not. When the cap lights, the ink moves from its `-off` to its `-on` value with the lamp; pressing only dims the whole cap to 80%. A lit cap has one bulb: a soft `lamp-*-hot` centre fading out by 62% of the cap.

**Consumer provides:** cap text, plate label, latching or momentary, the command, and the confirmation signal.

**Native.** A custom `ButtonStyle` is not enough because press and release are separate events: use a `DragGesture(minimumDistance: 0)` or an NSView subclass. Add `NSHapticFeedbackManager` `.levelChange` on down and on confirm. Keyboard focus ring is 3pt `lamp-amber-on`.
