# Performance

Every number here was measured on the owner's Mac: an Apple M4 Pro, macOS 26.5, driving a
Samsung 5K display ("looks like" 2560 × 1440, **60 Hz**) with the lid closed. CPU is the
app process as a percentage of one core, averaged over 60 s after 10 s of warm-up, from
`ps -o time=` deltas, the way the reference was measured (`scripts/measure-cpu.sh`,
`scripts/bench.sh`). "With children" adds the processes the app starts and waits for,
which is where the Claude Code feed spends its time (`claude agents --json`).

## Budget (handover §15) and where it stands

| Scenario | Target | SKALA-2000 | Notes |
| --- | --- | --- | --- |
| Visible, idle (MAINS on, no sessions, no alarms) | ≤ 0.3% | **0.02%** | `bench.sh static` |
| Four lamps flashing, buzzer silenced | ≤ 0.5% | **0.00%** | `bench.sh flash`; the render server animates. See WindowServer below |
| Busy telemetry (the scripted day) | ≤ 2% | **0.77%** | `bench.sh demo` |
| Real Claude Code feed, this session busy | — | **0.10%** (0.53% with children) | `bench.sh real` |
| Hidden (minimised), real feed | ≤ 0.3% | **0.10%** (0.54% with children) | the feed's `claude agents` runs are the rest; the reference measured 0.52% in total |
| Hidden, no feed | ≤ 0.3% | **0.02%** | |
| Live resize, 1280 wide to the widest the screen allows | no dropped frames; ≤ 2 ms main thread per frame | **0 of 272 frames missed**; DeskView **0.04 ms** per frame (max 0.12) | the whole `NSWindow.setFrame` step is 2.2 ms, of which an *empty* AppKit window takes 1.44 ms (p95 4.4 ms) |
| Click → cap visibly down | next frame | cap transform set inside `mouseDown`, committed with that turn of the run loop | see "Input" |
| Launch → interactive desk | ≤ 0.5 s warm, ≤ 1.5 s cold | **0.40–0.42 s warm**, **1.17 s** first launch after a build | from `exec` to the art on screen; the art comes from the disk cache in 12 ms |
| Memory, 5K full screen | ≤ 250 MB | **161 MB** | was 346 MB before the art moved into IOSurfaces |

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

### Open items

- Instruments' Animation Hitches shows single-frame hitches during the power-up sequence
  at launch, while every sprite is shown for the first time.
