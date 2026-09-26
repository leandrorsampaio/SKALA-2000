A row of gas-discharge digits behind one shared dark-orange filter window, with a label plate (and its HG designator) on the left and an optional painted unit on the right. For every number that changes while you watch: tokens, queue depth, tool calls, turn time, cost at last checkpoint, session counts.

**Fixed width, leading zeros, no thousands separators.** A readout has a fixed number of tubes; all token rows share eight so their columns align. Separators `:` and `.` take a 10px cell. Overflow shows all nines, never a wider window.

**A nixie does not roll or fade.** Each digit is a separate cathode: the old one goes dark and the new one lights. Spec: swap instantly, keep the old digit as a 35% ghost for 60 ms, then remove it. Only the digits that changed do this. Throttle updates to at most 4 per second per readout; between updates the glow may flicker by ±3% brightness at random (optional, off under Reduce Motion).

**Sizes.** Standard cell 28×48, digit 34px. XL cell 54×84, digit 60px, used only for SELECTED and COMMAND GOES TO SESSION.

**Consumer provides:** label, a string of exactly the readout's length, unit.

**Native.** Pre-render glyphs 0-9 with their glow into a texture atlas per size; a digit change is then two sprite opacity changes. Bundle the Nixie One font (OFL); do not substitute a system font.

**Depth.** The filter window is recessed behind a bevelled 4px bezel like a LampWindow: deep shadow across the top of the glass (the tubes sit well back), a faint fixed sheen over the upper 40%, bright line and `plate-raise` shadow under the frame.
