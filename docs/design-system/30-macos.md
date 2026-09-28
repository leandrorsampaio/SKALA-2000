# Notes for the native macOS implementation

**Stack.** Swift, SwiftUI for composition, `Canvas` or Core Animation layers for instruments. One fixed coordinate space 3352 units wide scaled with a single `scaleEffect` / layer transform; never re-lay-out for window size. Lock the aspect ratio (`window.contentAspectRatio`), minimum width 1280. Support full screen on a second display: that is the intended home of the console.

**Do not use** `Button`, `Toggle`, `Gauge`, `ProgressView`, SF Symbols, materials/vibrancy, system accent colour, tooltips, context menus, popovers or alerts on the console surface. Preferences live in a normal macOS Settings window, which may look like macOS.

**Architecture.** Three layers, kept apart:
1. *Sources*: file watchers and pollers for the telemetry inventory, the hook endpoint, IOKit power. Each emits typed readings with a timestamp and TTL.
2. *Console model*: one `@Observable` store holding slot assignment (1 to 4), selected slot, per-window alarm state (`off | on | flash | test`, acknowledged flag), readout strings, meter fractions, counter totals, command states. All rules in `10-interaction.md` and `20-signal-map.md` live here and are unit-testable without any view.
3. *Instruments*: dumb views that render one value with the specified motion. They hold animation state only.

**Tokens.** Read `tokens.json`; generate a Swift enum of colours (both themes → asset catalog colours with Any/Dark appearances), type styles, spacing, radii and sizes. Glow = a blurred duplicate of the lit shape (blur radius 7pt, the `glow-*` colour), not `shadow()` on text, so it can be cached.

**Performance.** Static plate artwork (enamel, screws, plates, tags, dials, scales) is rendered once into one bitmap per sub-panel per theme. Only lit layers, digits, wheels, needles and caps are live layers. A shared 2 Hz clock drives every flashing lamp in phase; throttle each nixie readout to 4 updates per second; idle CPU target under 1%.

**Fonts.** Bundle Barlow Condensed (600, 700), Dosis (600), Nixie One, Permanent Marker, Caveat; register with `CTFontManagerRegisterFontsForURL`. Pre-render nixie glyphs with glow to an atlas.

**Sound and haptics.** `AVAudioEngine` with four pre-rendered buffers (click, clunk, tick, buzzer loop). Haptics: `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, …)` on cap down and on confirm; `.alignment` on selector detents.

**Accessibility.** Each instrument is one accessibility element with a label from its plate and a value in words ("Context remaining, 62 percent", "Waiting for operator, session 2, alarm, unacknowledged"). Alarms post `NSAccessibility` announcements. VoiceOver order follows designator order. Honour Reduce Motion and Increase Contrast (Increase Contrast: unlit glass one step darker, lettering on unlit glass switches to `engraving`).

**Persistence.** Drum counter totals, hours in service, pencil strips, selector position, key-switch position.

**Safety log.** Append-only file: every command sent, its confirmation or no-answer, every guard lift and key turn, every alarm raise, silence, acknowledge and clear, with timestamps and session id.

**Depth and finish.** All bevels, sheens, recess shadows and drop shadows are part of the cached static artwork; none of them animate. See the brand book's Depth and Panel finish sections; the finish is a user preference (1, 2 or 3) applied console-wide.
