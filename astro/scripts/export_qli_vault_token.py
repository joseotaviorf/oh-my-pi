#!/usr/bin/env python3
"""Print shell exports for the developer's short-lived Vault token from qli.

qli login / qli kv cache tokens in ~/.qli/configv2 (base64-encoded YAML).
Used by local Astro only — never baked into the Airflow image.

Usage:
  eval "$(astro/scripts/export_qli_vault_token.py)"
  # → exports VAULT_ADDR + VAULT_TOKEN for vault-sandbox (forno parity)

Override URL with VAULT_ADDR. Refresh with: qli login -r -s vault
"""

from __future__ import annotations

import base64
import os
import re
import sys
import time
from pathlib import Path

DEFAULT_VAULT_ADDR = "https://vault-sandbox.sre.quintoandar.com.br"
DEFAULT_QLI_CONFIGV2 = Path.home() / ".qli" / "configv2"


def _sh_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def _parse_vault_environments(decoded: str) -> dict[str, dict[str, str]]:
    envs: dict[str, dict[str, str]] = {}
    current: str | None = None
    for line in decoded.splitlines():
        match = re.match(r"^    (https://[^:]+):\s*$", line)
        if match:
            current = match.group(1).rstrip("/")
            envs[current] = {}
            continue
        if current and line.startswith("      ") and ":" in line:
            key, _, val = line.strip().partition(":")
            envs[current][key.strip()] = val.strip()
        elif current and line and not line.startswith(" "):
            current = None
        elif current and re.match(r"^  \S", line):
            current = None
    return envs


def main() -> int:
    config_path = Path(os.environ.get("QLI_CONFIGV2", DEFAULT_QLI_CONFIGV2))
    vault_addr = os.environ.get("VAULT_ADDR", DEFAULT_VAULT_ADDR).rstrip("/")

    if not config_path.is_file():
        print(f"ERROR: {config_path} not found. Run: qli login", file=sys.stderr)
        return 1

    decoded = base64.b64decode(config_path.read_text().strip()).decode()
    envs = _parse_vault_environments(decoded)
    meta = envs.get(vault_addr) or {}
    token = meta.get("token")
    expires_raw = meta.get("expires_at")

    if not token:
        print(
            f"ERROR: no Vault token for {vault_addr} in {config_path}. "
            "Run: qli login -r -s vault",
            file=sys.stderr,
        )
        return 1

    if expires_raw is not None:
        try:
            if float(expires_raw) < time.time():
                print(
                    f"ERROR: Vault token for {vault_addr} expired. "
                    "Run: qli login -r -s vault",
                    file=sys.stderr,
                )
                return 1
        except ValueError:
            pass

    print(f"export VAULT_ADDR={_sh_quote(vault_addr)}")
    print(f"export VAULT_TOKEN={_sh_quote(token)}")
    print(
        f"Vault token loaded for {vault_addr} (len={len(token)})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
