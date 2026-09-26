A sub-panel is one painted steel plate screwed into the desk: one of the three finishes, a bright top-left and dark bottom-right edge, a 1px border in the finish's edge colour, a soft drop shadow onto the desk, four screws and a centred bakelite title plate. Everything on the console lives inside one.

**Parts.** Title plate (`panel-title`, bakelite + engraving). Label plate (`plate`, `plate-sm`): always uppercase, always centred, never wraps to more than two lines. Instruction plate (`instruction` ground, two rivets): any sentence that tells the operator how something behaves; loose text on enamel is not allowed. Designator tag (`tag`): every lamp HL, button SB, meter PA, nixie row HG, drum counter PC, switch SA, buzzer HA, fuse FU, numbered left to right, top to bottom, per console. Blanking plate (`enamel-recess`): a reserved cut-out, says RESERVED and what for.

**Consumer provides:** the title (letter, middle dot, name), a fixed width, children. Gap between groups `space-5`, padding `space-3`, gap between sub-panels `space-4`.

**Screws.** 18px: a dark countersink ring with a shadow below it, a domed head shaded by a radial gradient lit from top-left, a dark slot with a thin bright lower lip. Each slot sits at its own random angle, fixed per screw for the life of the console.

**Plates** are raised: vertical bakelite gradient, bright top edge, dark bottom edge, `plate-raise` shadow, engraved lettering (dark line above, faint light line below). Tags are stamped aluminium with a bright-to-grey gradient. Instruction plates have two domed rivets.

**Native.** Generate each finish once as a 512pt tiling bitmap: `CIRandomGenerator`, desaturated, contrast reduced to the amplitudes in the brand book's Panel finish section, one copy at 1pt grain and one blurred to a 150 to 200pt scale, composited over the ground colour in overlay mode. The two light-falloff gradients are drawn per sub-panel on top. No height maps, no lighting filters, no bumps. Do not regenerate per frame. Panels never animate, resize or scroll.
