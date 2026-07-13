"""Regenerate the ``domain: regex(...)`` line in the Yamale metadata schemas from
the single source of truth (:mod:`bietlejuice.governance.domain_registry`).

Yamale schemas are static YAML — they cannot read the loader at validation time —
so the allowlist regex is the one artifact we materialize. The runtime F2-01 check
and every other consumer read the loader directly; only these 5 schema files are
generated.

Usage (via Makefile — preferred):
    make sync-domain-allowlist            # rewrite the 5 schemas in place
    make validate-domain-allowlist-sync   # --check: exit 1 if any schema is stale

Direct invocation:
    uv run --project packages/bietlejuice-compiler python \\
        packages/bietlejuice-compiler/scripts/governance_metadata_validation/sync_domain_allowlist.py [--check]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# compiler package root, so `bietlejuice.*` resolves (same pattern as sibling scripts)
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bietlejuice.governance.domain_registry import domain_allowlist_pattern

_COMPILER_ROOT = Path(__file__).resolve().parents[2]
_SCHEMA_DIR = _COMPILER_ROOT / "scripts" / "services" / "metadata_file_schemas"
# Only these layers carry a `domain:` field. privacy_schema.yml does not.
_SCHEMA_LAYERS = ("raw", "clean", "core", "enrich_dw", "metric")

# Captures the literal `domain: regex('<alternation>')` line, preserving prefix
# and any trailing content so only the alternation between quotes is rewritten.
_LINE_RE = re.compile(r"^(domain:\s*regex\(')[^']*('\).*)$", re.MULTILINE)


def _render(text: str, pattern: str, schema: Path) -> str:
    """Return ``text`` with the domain alternation replaced by ``pattern``."""
    # Function replacement avoids backslash/group-ref interpretation of `pattern`.
    new_text, count = _LINE_RE.subn(
        lambda m: f"{m.group(1)}{pattern}{m.group(2)}", text
    )
    if count != 1:
        raise SystemExit(
            f"{schema}: expected exactly one `domain: regex(...)` line, found {count}"
        )
    return new_text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write; exit 1 if any schema differs from the generated form.",
    )
    args = parser.parse_args()

    pattern = domain_allowlist_pattern()
    stale: list[Path] = []

    for layer in _SCHEMA_LAYERS:
        schema = _SCHEMA_DIR / f"{layer}_schema.yml"
        text = schema.read_text(encoding="utf-8")
        new_text = _render(text, pattern, schema)
        if new_text != text:
            stale.append(schema)
            if not args.check:
                schema.write_text(new_text, encoding="utf-8")

    if args.check:
        if stale:
            print("Domain allowlist drift detected in:")
            for path in stale:
                print(f"  - {path.relative_to(_COMPILER_ROOT.parents[1])}")
            print(
                "\nThe Yamale schemas are out of sync with "
                "bietlejuice/governance/domains.yml.\n"
                "Run `make sync-domain-allowlist` and commit the regenerated schemas."
            )
            return 1
        print("Domain allowlist in sync across all schemas.")
        return 0

    if stale:
        print(f"Synced domain allowlist into {len(stale)} schema(s).")
    else:
        print("Domain allowlist already in sync; nothing to write.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
