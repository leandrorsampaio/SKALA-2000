The alarm board of panel A: one column per session (1 to 4), one row per condition, with the buzzer and the SILENCE, ACKNOWLEDGE and LAMP TEST buttons. It is the only part of the console meant to be read without touching anything.

**Rows, top to bottom:** RUNNING (white), BUSY (green), WAITING FOR OPERATOR (red, alarm), TURN DONE (green), AGENT DONE (white), BACKGROUND JOB (white), BLOCKED (red, alarm), COMPACTING (amber). BATTERY LOW and DATA STALE elsewhere on the console join the same alarm logic.

**Alarm state machine, per window.**

| Event | Window | Buzzer |
| --- | --- | --- |
| Condition becomes true (alarm row) | `flash` 2 Hz | sounds |
| SILENCE | unchanged | stops until the next new alarm |
| ACKNOWLEDGE | every flashing window → `on` | stops |
| Condition clears | `off`, whether acknowledged or not | stops if none left unacknowledged |
| Condition becomes true (non-alarm row) | `on` | none |
| LAMP TEST held | every window and lens on the console `test` | none |

A relay `clunk` accompanies every window change. TURN DONE and AGENT DONE are events, not states: they light when the hook fires and clear when the operator next submits a prompt to that session (or after the signal's TTL). A session with no record has its whole column dark.

Every source has a TTL: if a session stops reporting, its windows go dark and DATA STALE (red, panel B warnings) lights for that session when selected.

**Consumer provides:** the row definitions, the number of sessions, and per (row, session) a boolean.

**Native.** Keep the state machine in one observable model separate from the views; the views only render `off | on | flash | test`. Buzzer: a looped 420 Hz square wave at low gain through `AVAudioEngine`; respect the system mute and offer a BUZZER MUTED preference, but never mute the flash.
