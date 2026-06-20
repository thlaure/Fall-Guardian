#!/usr/bin/env python3
"""PreToolUse Write|Edit: block writes outside the repository root."""

import json
import os
import subprocess
import sys

event = json.load(sys.stdin)
tool_input = event.get("tool_input", {})
file_path = tool_input.get("file_path") or tool_input.get("path") or ""

if not file_path:
    sys.exit(0)

result = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"],
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    sys.exit(0)

project_root = os.path.realpath(result.stdout.strip())
abs_file = os.path.realpath(os.path.abspath(file_path))

if not abs_file.startswith(project_root + os.sep) and abs_file != project_root:
    print("ERROR: Writing outside the project directory is blocked.", file=sys.stderr)
    print(f"Attempted path: {file_path}", file=sys.stderr)
    sys.exit(1)
