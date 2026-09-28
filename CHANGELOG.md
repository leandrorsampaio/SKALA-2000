# Changelog

## 0.5.0

- **Panel F, the Mac itself**, in a fourth column: the desk is 3352 units wide now. Four
  moving-coil meters, CPU load, GPU load, the watts the whole Mac draws and memory used;
  tubes for the hottest point of the processor die, the SSD and the battery, both fans,
  memory used, wired, compressed and swap, room on the startup disk, disk and network
  traffic; and each seated session's own CPU and memory, everything it started included,
  in panel A's four columns. All read on the Mac, every two seconds, without privileges;
  the temperatures every ten. A session's processes still running never keep it from
  going stale. The scripted day has figures of its own for it.
- **THERMAL STATE and MEMORY PRESSURE** at the foot of panel D, under the power source: a
  lamp for each of macOS's levels, red ones flashing while they hold.
- **Panel F is hidden until COMPUTER STATUS shows it**, and the window grows to the right to
  take it, or back; the desk remembers which. While it is hidden, only the thermal state
  and memory pressure are read, and the desk costs what it did before panel F.
- **A second row of round buttons in panel D**: WINDOW ON TOP, off at every launch; MAC
  SPEAKERS, which sends the sound to the Mac's own speakers and, pressed again, back to the
  device it came from, remembered across a relaunch; COMPUTER STATUS; and MINIMIZE WINDOW,
  which lets go of ON TOP first. Each lens shows what the window or the sound reports, the
  sound whoever changed it.
- **No title bar.** The desk reaches the window's edges, and dragging bare steel moves it.
- **F1 moves to panel B**, beside PRINT TO LOG. Panel C keeps F2 to F7, and COMMAND GOES TO
  SESSION is gone: SELECTED already says it. Panel C is shorter and panel D taller.
- **REMOTE CONTROL**, a tenth annunciator row: white, burning while a session's Remote
  Control is on, so it can be carried on from claude.ai or the phone, and dark again when
  it is turned off. Claude Code tells no status line or hook this; the session's
  transcript records it, and only whether it is on is read, never the link or its id. It
  makes no sound. The scripted day turns it on for one session.
- **F10 and F11 are gone.** They had no job; F12, behind its guard and key, stands alone
  under DISRUPTIVE COMMANDS. Compacting a session or turning its Remote Control on from the
  desk was looked at and left out: Claude Code takes both only as commands typed at the
  session's own prompt.
- **SILENCED stands beside the buzzer**, level with the grille's middle, to give panel A
  the room for the new row.
- **Panel B, rearranged.** F12 moves up into the first row, at its right end, beside the
  session selector, SELECTED and PRT; the selector's plate goes under the knob to make the
  room. The row, the three meters and the two columns of tubes each span the panel from
  edge to edge, so the meters line up with the tubes under them. Every lamp group has a
  line of its own, KIND and WARNINGS too, their plates one below the other. The height F12
  gave up goes between the sections.
- **PRINT TO LOG**, where the button said PRINT TEXT: it writes the selected session's
  text to the text log and opens it.
- **Both plan windows count down in days, hours and minutes**, on three readouts each.
  Claude Code gives the moment a window resets; the time left is counted on the Mac's
  clock. NEAR LIMIT and AT LIMIT stand one above the other.

## 0.4.2

Panel E, when it has nothing to show.

- **The desk remembers the plan's usage** across a relaunch, until each window resets, so
  it no longer waits dark for Claude Code to speak again.
- **The status line runs every 30 seconds** while a Claude Code session is open, as well
  as after each answer, so the desk hears even from an idle session.
- **Settings says when the status line was last heard**, and whether it carried the
  plan's usage: the way to tell a status line that is not running from one without the
  figures.

## 0.4.1

- **Panel B's lamps**: each group on one line, its plate on the left, as panel A's rows
  are; MODE and KIND share a line, and SERVICE TIER and WARNINGS.
- **Panel A's foot**: the buzzer and SILENCED, then the alarm buttons, SILENCE and
  ACKNOWLEDGE, and the tests, LAMP TEST and BUZZER TEST, each under a plate of its own.
  The instruction plate is as wide as its words need, and the two session counters
  stand closer in.
- **Panel D**: the MAINS switch is gone; MAINS is in the Console menu, ⇧⌘M, with a check
  while the desk has power. The battery and the power source lamps stand further apart.
- **A click you can hear.** Every button clicked on down and up, but 18 ms at 2.6 kHz was
  too short and too high to be heard over the relays; it is now 30 ms at 1.8 kHz, louder.
  A VoiceOver press clicks too.

## 0.4.0

A narrower panel B, and room for A and E.

- **Panel B** starts with a row: the session selector, SELECTED and PRINT TEXT, where they
  had a column to themselves. The two reserved plates are gone, the four totals drums
  stand centred, and the panel is 1004 units wide instead of 1190.
- **Panels A and E** take the width, 836 instead of 650. The annunciator's four columns
  stand further apart, and each plan window in panel E is one row: meter, countdown,
  NEAR LIMIT and AT LIMIT.
- **Red windows flash for as long as their cause holds**: WAIT, BLOCK and LOW CTX, and AT
  LIMIT. ACKNOWLEDGE still steadies DATA STALE and BATT LOW. Panel A's plate says so.

## 0.3.2

Panels B, D and E, tidied.

- **Panel E**: each plan window is one row, its meter beside how long until it resets,
  the label on the readout's left, and its two lamps under the readout. The rows stand
  apart, and HOURS IN SERVICE sits apart beneath them, its label on the left too.
- **Panel B**: COMMAND GOES TO SESSION and the instruction under it are gone; the
  disruptive commands stand alone, centred. The selected slot is still on SELECTED, and
  on panel C.
- **Panel D**: the instruction plate is gone, and the battery group stands further from
  the buttons above it.

## 0.3.1

Panel E, easier to read.

- **The two plan windows stand side by side**, well apart, each a column: its meter, how
  long until it resets, and its NEAR LIMIT and AT LIMIT lamps side by side beneath.
- **The week's reset reads in days and hours**, on two readouts, `03 d 03 h`, rounded up
  as a countdown reads; the session's stays in hours and minutes.
- **POWER ON and the ground bolt are gone.** MAINS and the tubes striking already say the
  desk has power. HOURS IN SERVICE sits beneath, without a unit the plate already gives.

## 0.3.0

Your plan's usage on the desk.

- **Panel E shows the plan's two usage windows**, the five hours and the week, each on a
  horizontal edgewise meter, the battery's scale turned on its side and red from 80%.
  Beside each, the hours and minutes to its reset on nixies, an amber NEAR LIMIT lamp
  from 80% and a red AT LIMIT from 95%, each beeping once as it comes on. A window that
  resets goes dark until it is heard of again.
- **A status line brings them.** Only Claude Code's status line is told these figures, so
  Settings ▸ Claude Code status line installs one: it posts its JSON to the app's socket
  and prints the line the app answers, the model, the context used and both windows. One
  someone else configured is never replaced. Claude Code does not tell a status line the
  per-model weekly limits, credits or spend limits; those stay on claude.ai.
- **MAINS moves to panel D**, beside the power source it switches. POWER ON and HOURS IN
  SERVICE take panel E's bottom row, and the fuses, which did nothing, are gone. Panel B's
  two plates reserved for the quotas now just say RESERVED.
- The scripted day reports a plan's usage too, so the demo shows panel E at work.

## 0.2.0

The desk as its owner asked for it after the first day at it.

- **Signals instead of a buzzer left sounding.** Each state speaks once as it begins:
  DONE one buzz, WAIT two quick, CMPCT three quick, BLOCK and the desk's own alarms one
  long, one after another and never over each other. Windows still flash until
  ACKNOWLEDGE.
- **LOW CONTEXT**, a ninth annunciator row: red under 5% of a session's context left,
  with a beep of its own, a 1.6 kHz sine, higher and rounder than the buzzer.
- **SILENCE is a mode**, on and off: while on, no signal sounds and its cap burns. A
  SILENCED lamp under the buzzer burns while it is on, or while the buzzer is muted in
  Settings.
- **The model says Opus 200K or Opus 1M**, by the session's context window; the two
  window lamps under the context meter are gone, and panel B's gaps take up their room.
- **F8 and F9** replace the spare plates in panel C, with no job yet; the guarded keys
  are now F10, F11 and F12, and F12, behind its key, ends a session.
- **The needles drift.** About a fifth of the time each moving-coil needle wanders one to
  three points off its reading and settles back, each on its own; never one resting on
  its stop, or where a fresh session starts it, nor with Reduce Motion.
- **A lit lamp's spill is light.** It was painted in the glass's own colour, darker than
  the paint, and read as a dark halo; it is now the hot colour halfway to white, so the
  paint under it only gets lighter.
- SLEEP MODE's plate breaks over two lines like its neighbours'. The annunciator's rows
  sit a little closer, to make room.

## 0.1.2

The rest of the first outside review.

- **The buzzer** starts again when the Mac's sound output changes under a sounding alarm,
  headphones in or out; it used to go silent for good.
- **VoiceOver** can fire F8 to F10: its press holds a guarded button for its two seconds.
- **Keyboard focus** leaves a button when its guard falls, for the flap.
- **Sessions keep their slots across a relaunch**, each under its own pencil strip.
- **Settings** save the paint and the buzzer mute at once, even with MAINS off.
- **Hooks.** A body over 1 MiB no longer waits a second for the go-ahead curl asks for.
  Removing takes out only SKALA-2000's hook, even from a group holding one of yours. At
  most 16 hook connections are served at once.
- **Robustness.** A session id that is not a plain one never becomes a path or a shell
  word, and a pid too large for the system is no process rather than a crash. Shutting
  F10's guard or turning its key back mid-hold drops the relay. A guard falling after NO
  ANSWER is logged as it falls. A clock set back no longer holds the desk's readings
  back. Art the Mac cannot spare the memory for is skipped, and the art on screen stays.
  Every demo day has its own sessions, so its drums count from the start. Another build's
  cached art is kept for a week. A replaced console is let go, and switching the demo no
  longer adds a snapshot observer each time.
- **Tools.** The bench will not run beside another SKALA-2000 and quits its own copy
  whatever fails. CI has a time limit, a build cache and one release build.
- **Tests.** 227. Lenses in the golden comparisons allow 24 levels, for their glow.

## 0.1.1

Fixes from two outside reviews.

- **F10 is stricter.** A password typed after the desk has shown NO ANSWER ends nothing,
  and the prompt closes itself at that point. The process must be the one that wrote the
  session's file (Claude Code records its start time there), so a pid reused after a crash
  is never signalled. The prompt names the session by its folder or name, never its id.
- **Numbers too large for the tubes no longer stop the app.** A damaged figure in a
  transcript is not counted, and one already in the desk's memory rolls the drum over
  instead of stopping every launch. One mistyped total no longer zeroes the others.
- **Reduce Motion**, turned on or off while lamps flash, reaches them at once.
- **A resize dragged back** while art was drawing no longer leaves art of the wrong size.
- **Hooks.** A `settings.json` linked from a dotfiles folder stays a link, and its backup is
  a copy of the file. The script accepts an empty settings file, refuses one that is not
  JSON, and writes atomically. The receiver clears a dangling link at its socket's path,
  never deletes a file that is not a socket, and Settings says why it could not start. It
  no longer narrows the process-wide umask while it binds, which left any folder another
  thread made at that moment unusable.
- **Robustness.** A transcript line written while it was being read is no longer read
  twice. A `claude` run that ignores SIGTERM at its timeout is killed. A damaged art cache
  file is refused and deleted instead of read out of bounds. The Mac's power source can no
  longer call into a freed object. Two views asking for the same art at once draw it once.
- **Tests** no longer read, write or prune the app's art cache, and the whole-day replays
  give the main thread back as they go, so the real-time tests no longer wait 25 s behind
  them: 217 tests in about 27 s, the power-up test no longer flaky.
- `ClaudeSummary`, the old menu bar panel's summary, is gone: nothing used it.

## 0.1.0

The first version: the PK-4 console from Mac Command Center, rebuilt as a standalone app
that draws its art once and only moves it afterwards.

- **The desk.** All five panels and the header, every instrument of the reference, in both
  themes and all three paints, held by golden tests to within antialiasing of the reference
  SwiftUI desk (a mean of about 3.4 levels in 255). The plates say SKALA-2000, type DD-72.
- **Behaviour.** The reference's rules and readers unchanged, with their 152 tests: four
  session slots, the alarm board, LAMP TEST and BUZZER TEST, the routine and guarded keys
  (F10 ends a session after the key, a 2 s hold and your password), Keep Awake, sleep and
  monitor off, MAINS and the power-up sequence, PRINT TEXT, the safety log, the desk's
  memory and the scripted day.
- **Speed.** 0.02% of a core idle, 0.77% playing the scripted day, 0.04 ms of main thread
  per resize frame with no frames missed, 0.41 s from launch to desk, 161 MB at 5K full
  screen. See PERFORMANCE.md.
- **Hooks** on a Unix socket of the app's own, beside Mac Command Center's, installed from
  Settings or a script.
- **Input.** An explicit hit table (no two controls overlap, tested), press on mouse-down
  and release on mouse-up anywhere, keyboard focus for the keyboard only, VoiceOver for
  every instrument.
- **Fixed from the reference:** panel B overflowed the desk by 40 units and its lower edge
  was cut off; it now ends at 1778 like D and E. The four POWER SOURCE lamps had no
  instrument ids in the layout and would never have lit.
