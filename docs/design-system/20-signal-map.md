# Signal map

Which Claude Code reading drives which instrument. Sources are the ones in the telemetry inventory (`claude agents --json`, `~/.claude/sessions/*.json`, the transcript, `cost-state`, `~/.claude/jobs/*/state.json`, hooks posting to `/v1/signals/{id}`). Every reading is defensive: a missing field darkens one instrument, never the console. Join keys (`sessionId`, `pid`) and `ide.authToken` are never displayed.

## Panel A · all sessions (one column per session slot 1 to 4)

| Instrument | Component | Signal |
| --- | --- | --- |
| RUNNING | LampWindow white | session record exists |
| BUSY | LampWindow green | `status == "busy"` |
| WAITING FOR OPERATOR | LampWindow red, alarm | hook `Notification` → `claude.waiting`; cleared by `UserPromptSubmit` or TTL |
| TURN DONE | LampWindow green | hook `Stop` → `claude.done`; cleared by `UserPromptSubmit` or TTL |
| AGENT DONE | LampWindow white | hook `SubagentStop` → `claude.agent` |
| BACKGROUND JOB | LampWindow white | a `jobs/*/state.json` belongs to the slot |
| BLOCKED | LampWindow red, alarm | job `tempo == "blocked"` |
| COMPACTING | LampWindow amber | hook `PreCompact` until `compact_boundary` |
| SESSIONS RUNNING / BUSY | NixieReadout, 1 digit each | `sessions.count` |
| Project strip | PencilStrip | operator; may be pre-filled once from basename of `cwd` |

Slot assignment: a new session takes the lowest free slot and keeps it until it ends. A fifth session is not shown.

## Panel B · selected session

| Instrument | Component | Signal |
| --- | --- | --- |
| Selector, SELECTED | RotarySelector, NixieReadout XL | operator |
| CONTEXT REMAINING + 200K / 1M | MovingCoilMeter (red 0 to 20%), two LampWindows | `context.left`; window from the billed model id in `cost-state`, not the assistant record |
| API SHARE, TOOL SHARE OF TIME | MovingCoilMeter | `totalAPIDuration / totalDuration`, `totalToolDuration / totalDuration` |
| CONTEXT USED, INPUT, OUTPUT, THINKING | NixieReadout 8 | `usage`, cumulative figures deduplicated by `requestId` |
| CACHE READ, CACHE WRITTEN | NixieReadout 8, ×1000 | `usage` |
| QUEUE DEPTH (2), TOOL CALLS (4), TURN MESSAGES (3) | NixieReadout | `queue-operation`, derived, `turn_duration` |
| LAST TURN mm:ss, SESSION UPTIME hh:mm | NixieReadout | `turn.durationMs`, `startedAt` |
| COST, LAST CHECKPOINT | NixieReadout 0000.00 | `totalCostUSD` (a checkpoint, not live: the plate says so) |
| PERMISSION MODE | LampWindow group: DEFAULT, ACCEPT EDITS, PLAN, AUTO (amber), BYPASS (red) | `permission-mode` |
| EFFORT | LOW, MEDIUM, HIGH, X-HIGH (amber) | `effort` |
| MODEL | OPUS, SONNET, HAIKU, OTHER (amber) | `model` |
| MODE · KIND | NORMAL, OTHER MODE (amber), INTERACTIVE, DETACHED | `mode`, `kind` / `backend` |
| SERVICE TIER | STANDARD, OTHER TIER (amber) | `serviceTier` |
| WARNINGS | PRICE UNKNOWN (red), DATA STALE (red), SUBAGENT ACTIVE, PRE-COMPACT (amber) | `hasUnknownModelCost`, TTL expiry, `isSidechain`, `PreCompact` |
| TOTAL COST, TOTAL OUTPUT ×1000, LINES ADDED, LINES REMOVED | DrumCounter 6 | console-wide sums, persisted by the app |
| RESERVED · QUOTA 5 H, QUOTA WEEK · RESET | blanking plates | not available on disk today |
| F8, F9, F10 + COMMAND GOES TO SESSION | GuardedButton ×3, NixieReadout | disruptive commands, to be named; last row of panel B, acting on the selected session |
| PRINT TEXT | PushButton, momentary | writes the selected session's strings (name, title, branch, needs, detail) to the app's log view / file |

Unknown enum values light the OTHER window of their group; they never leave a group fully dark.

## Panel C · control, selected session

COMMAND GOES TO SESSION (NixieReadout XL, mirrors the selector), F1 to F7 (PushButton, to be named), two spare positions.

## Panel D · computer controls

SLEEP MODE, TURN OFF MONITOR, FC1, FC2 (RoundPushButton with ON / OFF lenses); BATTERY % (EdgewiseMeter, red under 20%); ON MAINS (green), ON BATTERY (amber), CHARGING (white), BATTERY LOW (red, alarm) from IOKit power sources.

## Panel E · power and service

MAINS (ToggleSwitch) + POWER ON; six fuse holders (decorative, each maps to a subsystem health check: MAINS, LAMPS, NIXIE, LOGIC, BUZZER, SPARE); HOURS IN SERVICE (DrumCounter, app running time, persisted); spare lamps; ground bolt.
