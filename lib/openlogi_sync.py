#!/usr/bin/env python3
"""Sync OpenLogi config with Omarchy conventions."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11
    tomllib = None  # type: ignore[assignment]

OPENLOGI_CONFIG = Path.home() / ".config" / "openlogi" / "config.toml"
OMARCHY_THEME_COLORS = (
    Path.home() / ".local" / "state" / "omarchy" / "current" / "theme" / "colors.toml"
)
HOOK_NAME = "theme-set-openlogi"


SHARE_DIR = Path.home() / ".local" / "share" / "omarchy-openlogi"
INSTALLED_SYNC = SHARE_DIR / "openlogi_sync.py"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def sync_module_path() -> Path:
    if INSTALLED_SYNC.is_file():
        return INSTALLED_SYNC
    return Path(__file__).resolve()


def hook_source() -> Path:
    return repo_root() / "hooks" / f"{HOOK_NAME}.sh"


def install_share_files() -> str:
    """Copy sync module to a stable path for installed hooks."""
    source = Path(__file__).resolve()
    SHARE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, INSTALLED_SYNC)
    return f"installed sync module to {INSTALLED_SYNC}"


def parse_simple_toml(path: Path) -> dict[str, dict[str, str]]:
    """Minimal TOML reader for flat string/bool values in known sections."""
    sections: dict[str, dict[str, str]] = {}
    current = ""
    if not path.is_file():
        return sections
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        section = re.match(r"^\[([^\]]+)\]$", line)
        if section:
            current = section.group(1)
            sections.setdefault(current, {})
            continue
        keyval = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', line)
        if keyval and current:
            sections.setdefault(current, {})[keyval.group(1)] = keyval.group(2).strip()
    return sections


def parse_bool(value: str) -> bool:
    return value.lower() in {"true", "yes", "1"}


def format_toml_value(value: bool | str) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if re.fullmatch(r"[A-Za-z0-9_]+", value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def set_app_setting(config_path: Path, key: str, value: bool | str) -> None:
    rendered = f"{key} = {format_toml_value(value)}"
    text = config_path.read_text(encoding="utf-8") if config_path.is_file() else "schema_version = 4\n\n"
    section = "app_settings"
    section_re = re.compile(rf"(^\[{re.escape(section)}\]\s*$)", re.MULTILINE)
    key_re = re.compile(rf"^({re.escape(key)}\s*=).*$", re.MULTILINE)

    if section_re.search(text):
        if key_re.search(text):
            text = key_re.sub(rendered, text, count=1)
        else:
            text = section_re.sub(rf"\1\n{rendered}", text, count=1)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += f"\n[{section}]\n{rendered}\n"

    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(text, encoding="utf-8")


def read_omarchy_mode() -> str | None:
    if tomllib is not None and OMARCHY_THEME_COLORS.is_file():
        data = tomllib.loads(OMARCHY_THEME_COLORS.read_text(encoding="utf-8"))
        mode = str(data.get("mode", "")).strip().lower()
        if mode in {"dark", "light"}:
            return mode
        return None

    sections = parse_simple_toml(OMARCHY_THEME_COLORS)
    mode = sections.get("", {}).get("mode") or sections.get("default", {}).get("mode")
    if not mode:
        # colors.toml is flat — mode is top-level without a section
        for line in OMARCHY_THEME_COLORS.read_text(encoding="utf-8").splitlines():
            match = re.match(r'^mode\s*=\s*"?(dark|light)"?\s*$', line.strip(), re.I)
            if match:
                return match.group(1).lower()
    if mode:
        cleaned = mode.strip('"').lower()
        if cleaned in {"dark", "light"}:
            return cleaned
    return None


def sync_config(*, theme_only: bool = False) -> list[str]:
    actions: list[str] = []
    if not theme_only:
        set_app_setting(OPENLOGI_CONFIG, "check_for_updates", False)
        set_app_setting(OPENLOGI_CONFIG, "auto_install_updates", False)
        set_app_setting(OPENLOGI_CONFIG, "update_prompt_seen", True)
        set_app_setting(OPENLOGI_CONFIG, "launch_at_login", True)
        actions.append("disabled in-app updates (use pacman / omarchy update)")
        actions.append("enabled launch_at_login (OpenLogi manages systemd user unit)")

    mode = read_omarchy_mode()
    if mode:
        set_app_setting(OPENLOGI_CONFIG, "appearance", mode)
        actions.append(f"synced appearance to Omarchy mode: {mode}")
    elif theme_only:
        actions.append("no Omarchy theme colors.toml found — appearance unchanged")

    return actions


def config_owned_by_user() -> bool:
    if not OPENLOGI_CONFIG.parent.exists():
        return True
    try:
        stat = OPENLOGI_CONFIG.stat()
    except OSError:
        return True
    return stat.st_uid == os.getuid()


def warn_config_ownership() -> str | None:
    config_dir = OPENLOGI_CONFIG.parent
    if not config_dir.exists():
        return None
    for path in config_dir.iterdir():
        try:
            if path.stat().st_uid != os.getuid():
                return (
                    f"{config_dir} contains root-owned files — run: "
                    f'sudo chown -R "$USER:$USER" {config_dir}'
                )
        except OSError:
            continue
    return None


def install_theme_hook() -> str | None:
    install_share_files()
    source = hook_source()
    if not source.is_file():
        return f"hook source missing: {source}"
    if not shutil.which("omarchy"):
        return "omarchy not in PATH — skip hook install (copy hooks/theme-set-openlogi.sh manually)"
    subprocess.run(
        ["omarchy", "hook", "install", "theme-set", str(source)],
        check=False,
    )
    return "installed theme-set hook"


def restart_agent() -> str | None:
    if not shutil.which("systemctl") or not shutil.which("openlogi-agent"):
        return None
    for args, label in (
        (["systemctl", "--user", "is-active", "openlogi-agent.service"], "active"),
        (["systemctl", "--user", "is-enabled", "openlogi-agent.service"], "enabled"),
    ):
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            subprocess.run(
                ["systemctl", "--user", "enable", "--now", "openlogi-agent.service"],
                check=False,
            )
            return "started openlogi-agent.service"
    subprocess.run(
        ["systemctl", "--user", "restart", "openlogi-agent.service"],
        check=False,
    )
    return "restarted openlogi-agent.service to apply config"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync OpenLogi with Omarchy settings")
    parser.add_argument(
        "--theme-only",
        action="store_true",
        help="Only sync appearance from the active Omarchy theme",
    )
    parser.add_argument(
        "--no-hook",
        action="store_true",
        help="Do not install the theme-set hook",
    )
    parser.add_argument(
        "--no-agent",
        action="store_true",
        help="Do not restart or enable the agent",
    )
    args = parser.parse_args(argv)

    ownership = warn_config_ownership()
    if ownership:
        print(f"warning: {ownership}", file=sys.stderr)

    if not config_owned_by_user() and OPENLOGI_CONFIG.exists():
        print("error: config.toml is not owned by the current user", file=sys.stderr)
        return 1

    for action in sync_config(theme_only=args.theme_only):
        print(action)

    if not args.no_hook and not args.theme_only:
        hook_result = install_theme_hook()
        if hook_result:
            print(hook_result)

    if not args.no_agent and not args.theme_only:
        agent_result = restart_agent()
        if agent_result:
            print(agent_result)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
