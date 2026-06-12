"""Shared dataclasses for EMR migration validation."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


SchemaEntry = Tuple[str, str]


@dataclass
class ColumnProfile:
    null_count: int
    checksum: Optional[str] = None
    checksum_sum: Optional[str] = None


@dataclass
class TableProfile:
    version: int = 1
    columns: Dict[str, ColumnProfile] = field(default_factory=dict)
    skipped_columns: List[str] = field(default_factory=list)
    truncated_columns: List[str] = field(default_factory=list)
    checksum_skipped_columns: List[str] = field(default_factory=list)


@dataclass
class ParsedResult:
    """Normalized output from a Databricks Commands API result."""

    columns: List[str]
    rows: List[List[Any]]
    row_dicts: List[Dict[str, Any]]


@dataclass
class TableBaseline:
    """Result of Phase 2 baseline capture."""

    dag: str
    table: str
    layer: str
    load_start_date: str
    schema: List[SchemaEntry]
    count: int
    sample_rows: int
    sample: List[Dict[str, Any]]
    order_by_cols: List[str]
    time_pinned_functions: List[str]
    non_comparable_cols: List[str]
    load_end_date: str = ""
    sql_hash: str = ""
    pinned_sql: str = ""
    profile: Optional[TableProfile] = None
    error: Optional[str] = None


@dataclass
class EmrTableResult:
    """Result from EMR validation job."""

    schema: List[SchemaEntry]
    count: int
    sample: List[Dict[str, Any]]
    profile: Optional[TableProfile] = None
    error: Optional[str] = None


@dataclass
class ValidationResult:
    """Phase 4 comparison result for one table."""

    table: str
    baseline_count: int
    emr_count: int
    count_delta_pct: float
    schema_match: bool
    schema_issues: List[str] = field(default_factory=list)
    sample_match: bool = True
    sample_warn: bool = False
    sample_diff_rows: List[Dict[str, Any]] = field(default_factory=list)
    profile_match: bool = True
    profile_issues: List[str] = field(default_factory=list)
    profile_warn: bool = False
    baseline_profile: Optional[TableProfile] = None
    emr_profile: Optional[TableProfile] = None
    status: str = "PASS"
    message: str = "OK"
