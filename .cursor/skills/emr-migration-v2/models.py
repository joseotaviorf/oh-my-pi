"""Shared dataclasses for the EMR migration skill."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional


@dataclass
class MigrationScope:
    """A single DAG to migrate, identified by domain/dag_name."""

    domain: str
    dag_name: str

    @property
    def scope_id(self) -> str:
        return f"{self.domain}__{self.dag_name}"

    @classmethod
    def parse(cls, spec: str) -> "MigrationScope":
        parts = spec.strip().split("/")
        if len(parts) != 2:
            raise ValueError(
                f"Invalid scope format '{spec}', expected 'domain/dag_name'"
            )
        return cls(domain=parts[0], dag_name=parts[1])

    @classmethod
    def parse_list(cls, specs: str) -> List["MigrationScope"]:
        return [cls.parse(s) for s in specs.split(",") if s.strip()]


@dataclass
class TableTranspileResult:
    table_name: str
    layer: str
    original_path: str
    needs_transpile: bool = False
    transpiled: Optional[str] = None
    syntax_valid: bool = False
    error: Optional[str] = None
    findings: List[str] = field(default_factory=list)

    @property
    def status(self) -> str:
        if not self.needs_transpile:
            return "SKIP"
        if self.error:
            return "FAIL"
        if self.syntax_valid:
            return "PASS"
        return "FAIL"


@dataclass
class DagTranspileReport:
    scope: MigrationScope
    run_id: str
    tables: List[TableTranspileResult] = field(default_factory=list)

    @property
    def passed(self) -> int:
        return sum(1 for t in self.tables if t.status == "PASS")

    @property
    def skipped(self) -> int:
        return sum(1 for t in self.tables if t.status == "SKIP")

    @property
    def failed(self) -> int:
        return sum(1 for t in self.tables if t.status == "FAIL")

    @property
    def tables_to_validate(self) -> List[TableTranspileResult]:
        return [t for t in self.tables if t.status in ("PASS", "SKIP")]
