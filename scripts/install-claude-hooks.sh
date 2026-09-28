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
# Settings ▸ Claude Code hooks in the app does the same. Every hook pipes its JSON to the app's Unix
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
import json, os, shutil, sys, tempfile

snippet_path, settings_path, mode = sys.argv[1:4]
with open(snippet_path) as handle:
    ours = json.load(handle)["hooks"]

# A settings file kept with your dotfiles and linked from ~/.claude is read and written
# where it lives, so the link stays a link.
real_path = os.path.realpath(settings_path)
settings = {}
if os.path.exists(real_path):
    with open(real_path) as handle:
        text = handle.read()
    try:
        settings = json.loads(text) if text.strip() else {}
    except json.JSONDecodeError as error:
        sys.exit(f"{settings_path} is not valid JSON ({error}); nothing was changed.")
    if not isinstance(settings, dict):
        sys.exit(f"{settings_path} does not hold a JSON object; nothing was changed.")
existing = settings.get("hooks", {})
marker = "SKALA-2000/hooks.sock"

def without_ours(group):
    """The group with our hook taken out, or None if nothing else was in it."""
    hooks = group.get("hooks", [])
    rest = [hook for hook in hooks if marker not in hook.get("command", "")]
    if len(rest) == len(hooks):
        return group
    return dict(group, hooks=rest) if rest else None

merged, changes = {}, []
for event in sorted(set(existing) | set(ours)):
    groups = existing.get(event, [])
    kept = [rest for rest in map(without_ours, groups) if rest is not None]
    had = kept != groups
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
folder = os.path.dirname(real_path)
os.makedirs(folder, exist_ok=True)
if os.path.exists(real_path):
    shutil.copy2(real_path, settings_path + ".skala-backup")
# Written whole beside the file, then moved over it: an interrupted write leaves the old
# one. The file keeps its permissions; a new one is readable by you alone.
fd, temp = tempfile.mkstemp(dir=folder, prefix=".settings-", suffix=".json")
with os.fdopen(fd, "w") as handle:
    json.dump(settings, handle, indent=2, sort_keys=True)
    handle.write("\n")
if os.path.exists(real_path):
    shutil.copymode(real_path, temp)
os.replace(temp, real_path)
print(("Installed" if mode == "--install" else "Removed") + f" SKALA-2000 hooks in {settings_path}")
print("Restart any running Claude Code session to pick the change up.")
PY
