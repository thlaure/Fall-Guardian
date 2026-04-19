#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROTECTED_BRANCHES = {"main", "master", "develop"}
INSTRUCTION_FILES = {"AGENTS.md", "CLAUDE.md"}
INSTRUCTION_PREFIX = ".claude/"

BACKEND_PREFIXES = ("backend/src/", "backend/config/", "backend/tests/")
FLUTTER_PREFIXES = ("flutter_app/lib/", "flutter_app/test/", "caregiver_app/lib/", "caregiver_app/test/")
NATIVE_ANDROID_PREFIXES = ("flutter_app/android/", "wear_os_app/")
NATIVE_IOS_PREFIXES = ("flutter_app/ios/", "watchos_app/")

SENSITIVE_SURFACE_PREFIXES = (
    "backend/src/Domain/Auth/",
    "backend/src/Infrastructure/Auth/",
    "backend/config/packages/security",
    "backend/config/routes",
)

BRIDGE_PREFIXES = (
    "flutter_app/lib/services/",
    "flutter_app/android/app/src/main/java/",
    "flutter_app/ios/Runner/",
    "wear_os_app/app/src/main/java/",
    "watchos_app/",
)

ENV_FILE_PATTERN = re.compile(r"(^|/)\.env(\..+)?$")


def load_tool_input() -> dict:
    raw = os.environ.get("CLAUDE_TOOL_INPUT", "{}")
    try:
        return json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return {}


def repo_path(path: str) -> str:
    try:
        resolved = Path(path).resolve()
        return resolved.relative_to(REPO_ROOT).as_posix()
    except Exception:
        return path.replace("\\", "/")


def collect_paths(value: object) -> list[str]:
    paths: list[str] = []

    if isinstance(value, str):
        normalized = value.replace("\\", "/")
        if "/" in normalized or normalized.startswith("."):
            paths.append(repo_path(normalized))
        return paths

    if isinstance(value, list):
        for item in value:
            paths.extend(collect_paths(item))
        return paths

    if isinstance(value, dict):
        for key, item in value.items():
            if key in {"path", "file_path", "target_file", "paths", "files"}:
                paths.extend(collect_paths(item))
        return paths

    return paths


def current_branch() -> str | None:
    try:
        return (
            subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=REPO_ROOT,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            .strip()
        )
    except Exception:
        return None


def git_changed_files(*args: str) -> list[str]:
    try:
        output = subprocess.check_output(
            ["git", *args],
            cwd=REPO_ROOT,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return [line.strip() for line in output.splitlines() if line.strip()]
    except Exception:
        return []


def all_changed_files() -> list[str]:
    files = set(git_changed_files("diff", "--name-only"))
    files.update(git_changed_files("diff", "--cached", "--name-only"))
    return sorted(files)


def is_instruction_file(path: str) -> bool:
    return path in INSTRUCTION_FILES or path.startswith(INSTRUCTION_PREFIX)


def is_env_file(path: str) -> bool:
    return bool(ENV_FILE_PATTERN.search(path))


def touches_backend(path: str) -> bool:
    return path.startswith(BACKEND_PREFIXES)


def touches_flutter(path: str) -> bool:
    return path.startswith(FLUTTER_PREFIXES)


def touches_native(path: str) -> bool:
    return path.startswith(NATIVE_ANDROID_PREFIXES) or path.startswith(NATIVE_IOS_PREFIXES)


def touches_bridge(path: str) -> bool:
    return path.startswith(BRIDGE_PREFIXES)


def touches_sensitive_surface(path: str) -> bool:
    return path.startswith(SENSITIVE_SURFACE_PREFIXES)


def emit_unique(warnings: list[str]) -> int:
    seen: set[str] = set()
    for warning in warnings:
        if warning in seen:
            continue
        seen.add(warning)
        print(f"[fall-guardian guardrail] {warning}", file=sys.stderr)
    return 0


def _staged_file_warnings(staged_files: list[str]) -> list[str]:
    warnings: list[str] = []

    if any(is_instruction_file(path) for path in staged_files):
        warnings.append(
            "Instruction files are staged. Changes to `AGENTS.md`, `CLAUDE.md`, or `.claude/*` require explicit confirmation; keep `CLAUDE.md` as a thin pointer."
        )

    if "backend/phpstan.neon" in staged_files:
        warnings.append(
            "`phpstan.neon` is staged. Prefer fixing code, types, or PHPDoc first. Justify any config relaxation before commit preparation."
        )

    if any(is_env_file(path) for path in staged_files):
        warnings.append(
            "Sensitive env files are staged. Do not commit `.env*` files unless there is a justified need."
        )

    active_layers = [
        k
        for k, fn in [
            ("backend", touches_backend),
            ("flutter", touches_flutter),
            ("native", touches_native),
        ]
        if any(fn(p) for p in staged_files)
    ]
    if len(active_layers) > 1:
        warnings.append(
            f"Changes span {' + '.join(active_layers)} layers. Verify all affected stacks before preparing a commit: `make check`, backend PHPStan/PHPUnit, and native build if applicable."
        )

    if any(touches_bridge(path) for path in staged_files):
        warnings.append(
            "Native bridge or service files are staged. Cross-platform contracts (MethodChannel, Wearable Data Layer, FCM payload keys) must stay aligned across Flutter, Android, iOS, Wear OS, watchOS, and backend."
        )

    if any(touches_sensitive_surface(path) for path in staged_files):
        warnings.append(
            "Auth or route configuration files are staged. Run a security review and ensure negative-path coverage before commit preparation."
        )

    return warnings


def handle_bash(data: dict) -> int:
    command = str(data.get("command", "")).strip()
    warnings: list[str] = []

    if re.search(r"\bgit\s+(commit|push)\b", command):
        branch = current_branch()
        if branch in PROTECTED_BRANCHES:
            warnings.append(
                f"Current branch is `{branch}`. Shared branches are protected; prefer a dedicated feature, fix, or hotfix branch before commit/push."
            )

    if re.search(r"\bgit\s+add\b", command):
        staged_files = git_changed_files("diff", "--cached", "--name-only")
        warnings.extend(_staged_file_warnings(staged_files))

    return emit_unique(warnings)


def handle_file_tool(data: dict, mode: str) -> int:
    warnings: list[str] = []
    paths = collect_paths(data)
    changed_files = all_changed_files()

    if any(is_instruction_file(path) for path in paths):
        warnings.append(
            "Instruction files are being changed. Explicit confirmation is required; keep `CLAUDE.md` as a thin pointer."
        )

    if any(path == "backend/phpstan.neon" for path in paths):
        warnings.append(
            "`phpstan.neon` is being changed. Prefer fixing PHPStan issues in code, types, or PHPDoc first."
        )

    if any(is_env_file(path) for path in paths):
        warnings.append(
            "Sensitive `.env*` files are in scope. Do not expose them in prompts, logs, comments, or commits."
        )

    if any(touches_bridge(path) for path in paths):
        warnings.append(
            "This change touches a native bridge or service layer. Keep cross-platform contracts aligned across Flutter, Android, iOS, Wear OS, watchOS, and backend."
        )

    if any(touches_sensitive_surface(path) for path in paths):
        warnings.append(
            "This change touches auth or route configuration. Security review and negative-path testing are expected."
        )

    if mode in {"edit", "write"}:
        active_layers = {
            "backend": any(touches_backend(p) for p in changed_files),
            "flutter": any(touches_flutter(p) for p in changed_files),
            "native": any(touches_native(p) for p in changed_files),
        }
        layers = [k for k, v in active_layers.items() if v]
        if len(layers) > 1:
            warnings.append(
                f"Worktree spans {' + '.join(layers)} layers. Remember to verify all affected stacks before preparing a commit."
            )

    return emit_unique(warnings)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    data = load_tool_input()

    if mode == "bash":
        return handle_bash(data)
    if mode in {"edit", "write", "read"}:
        return handle_file_tool(data, mode)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
