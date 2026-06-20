#!/usr/bin/env python3
"""PreToolUse Bash: block commits and pushes on protected branches."""

import json
import subprocess
import sys

PROTECTED = {"main", "master", "develop"}

event = json.load(sys.stdin)
command = event.get("tool_input", {}).get("command", "")

if not (command.startswith("git commit") or command.startswith("git push")):
    sys.exit(0)

result = subprocess.run(
    ["git", "branch", "--show-current"],
    capture_output=True,
    text=True,
)
branch = result.stdout.strip()

if branch in PROTECTED:
    action = "push from" if command.startswith("git push") else "commit directly on"
    print(
        f"ERROR: Cannot {action} protected branch '{branch}'. "
        "Create or switch to a dedicated feature/fix branch first.",
        file=sys.stderr,
    )
    sys.exit(1)
