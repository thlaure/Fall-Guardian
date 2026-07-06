#!/usr/bin/env python3
"""PreToolUse Write|Edit: block obvious credentials before they hit disk."""

import json
import re
import sys

SENSITIVE_FILENAMES = {
    "google-services.json",
    "GoogleService-Info.plist",
}

SECRET_PATTERNS = [
    re.compile(r"AIza[0-9A-Za-z_-]{20,}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----"),
    re.compile(r"(?i)(?:password|secret|api[_-]?key|private[_-]?key|token|credential)\s*[:=]\s*['\"][^'\"]{8,}['\"]"),
    re.compile(r"(?i)FCM_SERVICE_ACCOUNT_JSON\s*="),
]

event = json.load(sys.stdin)
tool_input = event.get("tool_input", {})
file_path = tool_input.get("file_path", "")
content = tool_input.get("content") or tool_input.get("new_string") or ""

if any(file_path.endswith(name) for name in SENSITIVE_FILENAMES):
    print(f"ERROR: Refusing to write generated Firebase config: {file_path}", file=sys.stderr)
    print("Use runtime secrets or --dart-define values instead.", file=sys.stderr)
    sys.exit(1)

matches: list[str] = []
for pattern in SECRET_PATTERNS:
    matches.extend(pattern.findall(content))

if matches:
    print(f"ERROR: Possible hardcoded credential in {file_path}.", file=sys.stderr)
    for match in matches[:3]:
        print(f"  {match}", file=sys.stderr)
    print("Fix: use environment variables, CI secrets, or local ignored config.", file=sys.stderr)
    sys.exit(1)
