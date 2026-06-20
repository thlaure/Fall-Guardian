#!/usr/bin/env python3
"""PreToolUse Bash: block direct commits and pushes on protected branches."""

import json
import shlex
import subprocess
import sys

PROTECTED = {"main", "master", "develop"}

event = json.load(sys.stdin)
command = event.get("tool_input", {}).get("command", "")

try:
    parts = shlex.split(command)
except ValueError:
    sys.exit(0)

if parts[:2] == ["rtk", "git"]:
    git_args = parts[2:]
elif parts[:1] == ["git"]:
    git_args = parts[1:]
else:
    sys.exit(0)

if not git_args or git_args[0] not in {"commit", "push"}:
    sys.exit(0)

result = subprocess.run(
    ["git", "branch", "--show-current"],
    capture_output=True,
    text=True,
)
branch = result.stdout.strip()

if branch in PROTECTED:
    action = "push from" if git_args[0] == "push" else "commit directly on"
    print(
        f"ERROR: Cannot {action} protected branch '{branch}'. "
        "Create or switch to a dedicated feature/fix branch first.",
        file=sys.stderr,
    )
    sys.exit(1)
