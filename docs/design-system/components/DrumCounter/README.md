An electromechanical counter: white digit wheels behind a black window. For cumulative totals that must survive a restart (total cost, total output, lines added, lines removed, hours in service). The app persists these; on launch they show the stored value with no animation.

**Wheels roll, forward only.** Each changed wheel rolls upward to its new digit in 320 ms with a slight overshoot (`cubic-bezier(.45,0,.3,1.25)`), units wheel first, each higher wheel starting 45 ms later so a carry ripples leftward. One `tick` sound per wheel that moves. A wheel passing 9 → 0 continues in the same direction. Counters never run backward; a reset is a maintenance action, not an animation.

Top and bottom of each wheel window carry an inner shadow so the digit reads as a curved drum.

**Consumer provides:** label, digit count (6), integer value, unit.

**Native.** Each wheel is a vertical strip of 0-9-0 clipped to 22×32; animate the offset with a spring (response 0.32, damping 0.7). Coalesce updates: if a new value arrives mid-roll, retarget, do not queue.

**Depth.** Same bevelled bezel and recessed glass as the nixie window. Each wheel is shaded as a cylinder: dark at top and bottom, a bright band across the middle, so the digit visibly curves away.
