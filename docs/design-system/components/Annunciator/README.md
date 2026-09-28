The alarm board of panel A: one column per session (1 to 4), one row per condition, with the buzzer and the SILENCE, ACKNOWLEDGE and LAMP TEST buttons. It is the only part of the console meant to be read without touching anything.

**Rows, top to bottom:** RUNNING (white), BUSY (green), WAITING FOR OPERATOR (red, alarm), TURN DONE (green), AGENT DONE (white), BACKGROUND JOB (white), BLOCKED (red, alarm), COMPACTING (amber), LOW CONTEXT (red, under 5% of the context left). BATTERY LOW and DATA STALE elsewhere on the console join the same alarm logic.

**Alarm state machine, per window.**

| Event | Window | Sound |
| --- | --- | --- |
| Condition becomes true (alarm row) | `flash` 2 Hz | its signal, once: WAIT two quick buzzes, BLOCK one long |
| ACKNOWLEDGE | every flashing window → `on` | none |
| Condition clears | `off`, whether acknowledged or not | none |
| Condition becomes true (non-alarm row) | `on` | DONE one buzz, COMPACTING three quick, LOW CONTEXT a beep; the rest none |
| SILENCE | unchanged | a mode: no signal until pressed again, and SILENCED burns |
| LAMP TEST held | every window and lens on the console `test` | none |

A relay `clunk` accompanies every window change. TURN DONE and AGENT DONE are events, not states: they light when the hook fires and clear when the operator next submits a prompt to that session (or after the signal's TTL). A session with no record has its whole column dark.

Every source has a TTL: if a session stops reporting, its windows go dark and DATA STALE (red, panel B warnings) lights for that session when selected.

**Consumer provides:** the row definitions, the number of sessions, and per (row, session) a boolean.

**Native.** Keep the state machine in one observable model separate from the views; the views only render `off | on | flash | test`. Buzzer: a 420 Hz square wave at low gain through `AVAudioEngine`, in the patterns of `10-interaction.md`; respect the system mute and offer a BUZZER MUTED preference, but never mute the flash.
