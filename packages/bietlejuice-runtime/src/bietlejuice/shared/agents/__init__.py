"""Reusable Spark I/O helpers for agent-domain jobs.

Keep metric-module orchestration in the DAG. This package is prune reads,
enrich Delta writes, and positional Spark CLI parsing.
"""

from bietlejuice.shared.agents.cli import parse_args
from bietlejuice.shared.agents.sources import (
    SourceCatalog,
    SourceSpec,
    overlapping_calendar_month_bounds,
)
from bietlejuice.shared.agents.writer import (
    resolve_write_target,
    write_delta_or_dev_view,
)

__all__ = [
    "SourceCatalog",
    "SourceSpec",
    "overlapping_calendar_month_bounds",
    "parse_args",
    "resolve_write_target",
    "write_delta_or_dev_view",
]
