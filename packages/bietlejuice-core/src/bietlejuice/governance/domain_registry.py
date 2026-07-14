"""Single source of truth for the metadata ``domain:`` allowlist.

Reads :mod:`bietlejuice.governance.domains` (``domains.yml``, shipped inside the
wheel next to this module) and exposes a stable interface. All consumers — the
FAIR F2-01 runtime check, the Yamale schema regex, CI sharding, metadata
generation — depend on this loader, never on the YAML format directly. That
indirection is what lets the underlying source be swapped later (e.g. to the
data-contracts domain files) without touching any consumer.
"""

from __future__ import annotations

import re
from functools import lru_cache
from pathlib import Path
from typing import Optional

import yaml

_DOMAINS_FILE = Path(__file__).parent / "domains.yml"


@lru_cache(maxsize=1)
def _load() -> dict:
    """Parse ``domains.yml`` once per process."""
    with _DOMAINS_FILE.open(encoding="utf-8") as fp:
        return yaml.safe_load(fp)


@lru_cache(maxsize=1)
def active_domains() -> tuple[str, ...]:
    """Allowlisted ``domain:`` values, in declaration order.

    Order is significant: it is preserved into the Yamale regex alternation and
    must stay byte-identical to the historical pattern.
    """
    return tuple(_load()["metadata_domains"])


@lru_cache(maxsize=1)
def domain_allowlist_pattern() -> str:
    """The regex alternation used to validate ``domain:``.

    Plain ``|`` join with no escaping — matches the historical hand-written
    pattern exactly. None of the values contain regex metacharacters (guarded by
    a unit test); ``&`` and spaces are not special in :mod:`re`.
    """
    return "|".join(active_domains())


@lru_cache(maxsize=1)
def domain_allowlist_regex() -> re.Pattern[str]:
    """Compiled allowlist regex (used with ``fullmatch`` by FAIR F2-01)."""
    return re.compile(domain_allowlist_pattern())


def folder_to_domain(folder: str) -> Optional[str]:
    """Resolve a ``dags/`` repo folder to its metadata ``domain:`` value.

    Returns the mapped allowlist value for folders with a reliable 1:1 domain, or
    ``None`` for folders that are mixed / per-DAG (or unknown) — callers should then
    leave ``domain:`` for a human to fill rather than guess.
    """
    return _load().get("repo_folder_mappings", {}).get(folder)
