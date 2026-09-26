#!/usr/bin/env bash
#
# Point Claude Code's hooks at SKALA-2000, so the desk hears what happens the moment it
# happens: a session starting and ending, a turn finishing, a subagent starting and
# stopping, a permission prompt, a tool finishing, a compaction. Reading ~/.claude says
# what is true; only hooks say what just happened.
#
#   scripts/install-claude-hooks.sh            # show what would change
#   scripts/install-claude-hooks.sh --install  # write it
#   scripts/install-claude-hooks.sh --remove   # take it back out
#
# Settings ▸ Hooks in the app does the same. Every hook pipes its JSON to the app's Unix
# socket in ~/Library/Application Support/SKALA-2000/: async, so Claude Code never waits,
# and best-effort, so a closed app costs a session nothing. SKALA-2000's hooks are told
# apart by the socket path they name; Mac Command Center's hooks and anything you wrote
# yourself are left exactly where they are, so both apps can listen at once.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNIPPET="$ROOT/scripts/claude-hooks.json"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
MODE="${1:---show}"

case "$MODE" in
--show | --install | --remove) ;;
*)
    echo "Usage: $(basename "$0") [--show | --install | --remove]" >&2
    exit 2
    ;;
esac

python3 - "$SNIPPET" "$SETTINGS" "$MODE" <<'PY'
import json, os, shutil, sys

snippet_path, settings_path, mode = sys.argv[1:4]
ours = json.load(open(snippet_path))["hooks"]
settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
existing = settings.get("hooks", {})
marker = "SKALA-2000/hooks.sock"

def is_ours(group):
    return any(marker in hook.get("command", "") for hook in group.get("hooks", []))

merged, changes = {}, []
for event in sorted(set(existing) | set(ours)):
    groups = existing.get(event, [])
    kept = [group for group in groups if not is_ours(group)]
    had = len(kept) != len(groups)
    if mode != "--remove" and event in ours:
        kept += ours[event]
        changes.append(("replace" if had else "add", event))
    elif had:
        changes.append(("remove", event))
    if kept:
        merged[event] = kept

if mode == "--show":
    print(f"Would change {settings_path}:" if changes else f"Nothing to change in {settings_path}.")
    for verb, event in changes:
        print(f"  {verb:8} {event}")
    sys.exit(0)

if merged:
    settings["hooks"] = merged
else:
    settings.pop("hooks", None)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".skala-backup")
with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(("Installed" if mode == "--install" else "Removed") + f" SKALA-2000 hooks in {settings_path}")
print("Restart any running Claude Code session to pick the change up.")
PY
