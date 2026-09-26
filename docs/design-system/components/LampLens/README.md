A 44px round signal lamp: a polished chrome collar, a domed coloured glass with fresnel rings, and the caption engraved underneath instead of painted on the glass. Used where a separate lamp reports the state of a round pushbutton (panel D), always as an ON (green) / OFF (white) pair.

**Built in four layers, back to front.** (1) Chrome collar: a conic sweep of light and dark bands, 6px wide, with a 1.5px `bezel` outline and a short drop shadow. (2) Dark glass: the `-off` lamp colour pushed well down (28% black at the centre rising to 80% at the rim) so an unlit lamp is clearly dead, with a deep inner shadow at the top so it reads as recessed. (3) Lit layer: the `-on` colour with a white-hot filament spot at the centre (white to 9%, fading out by 52%) and a slight rim vignette, a thin catch of lamp colour on the collar's inner edge, and the same faint `glow-*` spill onto the paint as a LampWindow (no neon halo); only this layer's opacity animates. (4) Dome: a fixed specular highlight top-left, a faint counter-highlight bottom-right and a single moulded step at 60% of the radius (one faint light line with a dark line outside it). No repeated rings. Layer 4 never changes, which is what keeps the lamp looking like glass in every state.

Same filament timing and colour meanings as LampWindow (90 ms up, 220 ms down, shared 2 Hz flash clock). The pair has three readings: ON lit, OFF lit, and **both dark = no answer from the machine**. Both lit never happens outside LAMP TEST.

**Consumer provides:** caption (one word), colour, state.

**Native.** Render layers 1, 2 and 4 once into a bitmap per colour; the lit layer and its bloom are a second bitmap whose opacity animates.
