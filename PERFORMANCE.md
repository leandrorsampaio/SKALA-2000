# Performance

Every number here was measured on the owner's Mac, an Apple M4 Pro with macOS 26.5: first
driving a Samsung 5K display ("looks like" 2560 × 1440, **60 Hz**) with the lid closed,
and at the end on the MacBook's own 120 Hz display, after the 5K was unplugged. Each
number says which where it matters. CPU is the
app process as a percentage of one core, averaged over 60 s after 10 s of warm-up, from
`ps -o time=` deltas, the way the reference was measured (`scripts/measure-cpu.sh`,
`scripts/bench.sh`). "With children" adds the processes the app starts and waits for,
which is where the Claude Code feed spends its time (`claude agents --json`).

## Budget (handover §15) and where it stands

| Scenario | Target | SKALA-2000 | Notes |
| --- | --- | --- | --- |
| Visible, idle (MAINS on, no sessions, no alarms) | ≤ 0.3% | **0.02%** (final build: 0.03%) | `bench.sh static` |
| Four lamps flashing, buzzer silenced | ≤ 0.5% | **0.00%** (final build: 0.02%) | `bench.sh flash`; the render server animates. See WindowServer below |
| Busy telemetry (the scripted day) | ≤ 2% | **0.77%** (final build: 0.70%; 0.95% over a ten-minute soak) | `bench.sh demo` |
| Real Claude Code feed, this session busy | — | **0.10%** (0.53% with children) | `bench.sh real` |
| Hidden (minimised), real feed | ≤ 0.3% | **0.10%** (0.54% with children) | the feed's `claude agents` runs are the rest; the reference measured 0.52% in total |
| Hidden, no feed | ≤ 0.3% | **0.02%** | |
| Real feed with panel F reading the Mac (0.5.0) | — | **0.42%** | 60 s, settled; four needles and some twenty tubes change every 2 s. A pass of the load source is about 1 ms; the temperature sensors, read every 10 s, are 32 ms of waiting but 1 ms of CPU; the rest is drawing what changed |
| Live resize, 1280 wide to the widest the screen allows | no dropped frames; ≤ 2 ms main thread per frame | **0 of 272 frames missed**; DeskView **0.04 ms** per frame (max 0.12) | the whole `NSWindow.setFrame` step is 2.2 ms, of which an *empty* AppKit window takes 1.44 ms (p95 4.4 ms) |
| Click → cap visibly down | next frame | cap transform set inside `mouseDown`, committed with that turn of the run loop | see "Input" |
| Launch → interactive desk | ≤ 0.5 s warm, ≤ 1.5 s cold | **0.37–0.40 s warm**, **1.17 s** first launch after a build | from `exec` to the art on screen; the art comes from the disk cache in 12 ms |
| Memory, 5K full screen | ≤ 250 MB | **161 MB** | was 346 MB before the art moved into IOSurfaces |

The rows above panel F were measured on the 2500-unit desk, before it had a fourth
column.

The reference app as it runs on this Mac right now (Mac Command Center, console window
closed, menu bar panel only): **11.09%** of one core.

## Findings

### Art in IOSurfaces: one copy of every pixel

The first spike handed Core Animation `CGImage`s. At 5K full screen the footprint was
346 MB: the bitmap-context buffers (≈100 MB, `MALLOC_LARGE`), the images' raster copies
(≈100 MB, `CG raster data`) and Core Animation's own copies (≈100 MB, `CoreAnimation`).
The art now renders straight into IOSurfaces, which Core Animation shows without copying:
161 MB, of which the art is 75 MB. The art cache keeps only the set on screen.

### WindowServer pays for every animated frame, of any app

Four flashing lamps cost the app nothing, but WindowServer recomposites the window for
every frame in which anything moves. Measured on this Mac (WindowServer CPU, 30 s):

| What is animating | WindowServer |
| --- | --- |
| nothing (baseline) | 9.2–10.0% |
| SKALA-2000, four lamps flashing, smooth at 60 Hz | 30.2% |
| SKALA-2000, four lamps flashing, capped at 30 Hz | 21.6% |
| SKALA-2000, **one** lamp flashing at 30 Hz | 21.3% |
| a trivial test app: one 40 × 40 layer fading at 30 Hz | 23.7–24.4% |

The cost is per frame, not per pixel: one lamp costs what four do, and a bare test app
animating a single dot costs WindowServer more than the whole flashing desk. It is the
platform's price for animation on this display. The flash is therefore capped at 30 Hz,
as the reference drew it, which halves it; it lasts only until the alarm is
acknowledged, and a steady or dark desk costs WindowServer nothing (static app open:
9.49% against 9.22% with it closed). A stepped flash with eight held levels per period
was tried and cut only a further 2%, at a visible cost to the filament's smooth fade, so
it was not kept.

### Resize is a transform

`DeskView.setFrameSize` sets one scale and one position on the desk layer: 0.04 ms. The
art is re-rendered at the new pixel size off the main thread when the resize ends; until
then the GPU scales the old bitmap. The remaining main-thread time in a resize step is
AppKit's own window resize, and an empty window costs about the same.

### Drawing the art

The art is drawn off the main thread, then swapped in: the whole static desk and 272
sprites for one style at one pixel size.

| Pixels per desk unit | Where | Background | Whole set | Memory |
| --- | --- | --- | --- | --- |
| 1.024 | 1280-point window | 91 ms | 80 ms | 33 MB |
| 1.28 | 1600-point window | 89 ms | 98 ms | 52 MB |
| 1.6 | 5K full screen | 132 ms | 145 ms | 76 MB |
| 2.048 | 2560 points wide at 2× | 218 ms | 243 ms | 125 MB |

The background is drawn in eight horizontal bands at once, each a context over the same
IOSurface that reaches 48 units past its band but is clipped to it, so shapes just outside
still cast their shadows in (without the margin every band edge had a seam). The sprites
are independent jobs on every core. Before this, the 5K set took 686 ms on one core.

Installing a set on the main thread takes **6.3 ms** (28 ms when the art was `CGImage`s,
which Core Animation copied during the commit), so a resize ending or the Mac switching
to Dark costs no dropped frame. The last four sets are kept on disk in
`~/Library/Caches/SKALA-2000/`, keyed by build, layout, style and size; a launch reads its
set back in 12 ms instead of drawing it.

### Fidelity

`GoldenTests` renders the real layer tree offscreen (`DeskPrinter`, Core Animation into a
Metal texture) and compares it with the reference SwiftUI desk in the scripted day by day
and night, under LAMP TEST and with MAINS off: a mean difference of about 3.4 levels in
255 over the whole desk, mostly antialiasing, with every lamp, cap, tube, drum, meter and
guard checked on its own.

### Switching between day and night

When the Mac switches between Light and Dark, the art for the other theme is read from
the disk cache or drawn (145 ms at 5K, off the main thread) and swapped in with a 0.25 s
crossfade. Measured by flipping the appearance four times: installs took 5.7–9.4 ms of
main thread each, and the enamel read (84, 93, 85) by night and (162, 171, 153) by day.

### Hitches on a 120 Hz display

Measured later on the MacBook's own ProMotion display (120 Hz, an 8.3 ms frame), with the
scripted day running: Instruments' Animation Hitches flags about one commit in ten as a
single frame late (8.3 ms), none longer, apart from the first frame at launch. Time
Profiler puts the main thread at about 1% of a core after launch, most of it Core
Animation's own commit and the model's timers; nothing the view does per snapshot is
costly (0.56 ms mean, 4.6 ms at the 95th percentile). The late frames are commits landing
just after a vsync, not work, and no stutter is visible. At 60 Hz on the 5K display the
resize bench missed no frames.

### Long runs

A whole scripted day, 08:55 to 18:00, run through the real model with every snapshot
applied to the layer tree and animated (`LongRunTests`): the layer count is unchanged at
the end, and no more than a few hundred animations are ever attached at once, since each
replaces the last under its key.

The app itself, playing the scripted day for ten minutes with its window visible:

| Minute | 0 | 1 | 2 | 4 | 6 | 8 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Footprint | 56 MB | 55 MB | 55 MB | 55 MB | 55 MB | 55 MB | 55 MB |

No growth, and 5.7 s of CPU in 600 s (0.95% of a core). The timings the benches collect
are kept only under `SKALA_BENCH`; before that fix they grew by one entry per snapshot.
