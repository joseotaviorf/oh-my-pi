"""Offline FAIR metadata checks on governance YAML files.

Woodpecker ``validate-fair-metadata`` runs substantive description checks on
clean+ layers: **F2-01** (table ``description``) and **F2-02** (column
``description``). Schema checks (owner, domain, min description length, YAML
shape) belong to ``validate-metadata-files-content`` (Yamale).
**Does not** honor ``skip_list.yml`` ``metadata_files_out_of_pattern`` — FAIR
applies to every changed clean+ metadata file in the PR diff.

Owner ACTIVE (F2-01) is **online only** — Trino MCP or ``trino/SKILL.md`` + ``check_owner_active.sql``
or production ``enrich_fairness_assessment`` (org_chart). No offline snapshot.

Column name alignment between metadata and SQL is validated at PR time by
``make validate-lineage-consistency`` (sqlglot). Production I1-01 runs after
deploy via ``enrich_fairness_assessment``.

Scope-wide audits (domain, owner, DAG, FQN) use ``--audit`` with scope flags.
PR diffs use ``-b`` / ``-f`` (Woodpecker ``validate-fair-metadata``).

Uses ``print()`` for CI/Woodpecker logs (same pattern as
``validate_metadata_files_content`` and ``validate_lineage_consistency``).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, DefaultDict, Dict, List, Optional, Sequence, Set, Tuple

import yaml

from bietlejuice.ci.ci_diff_ref import fetch_diff_base, resolve_diff_from_ref
from bietlejuice.governance.fairness_assessment.constants import (
    CDC_PLUMBING_COLUMN_NAMES_LOWERCASE,
    PARTITION_COLUMN_NAMES_LOWERCASE,
)
from bietlejuice.governance.fairness_assessment.description_quality import (
    assess_column_description_quality,
    assess_table_description_quality,
)

PARTITION_COLUMNS = PARTITION_COLUMN_NAMES_LOWERCASE
CDC_PLUMBING_COLUMNS = CDC_PLUMBING_COLUMN_NAMES_LOWERCASE
PLACEHOLDER_COLUMNS = frozenset({"_placeholder"})
UPSERT_STATUS = frozenset({"M", "A"})
METADATA_PATH_RE = re.compile(r"dags/.+/metadata/[^/]+/[^/]+\.yml$")
_VALID_SCOPE_SEGMENT_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_\-]*$")
RAW_LAYER_SEGMENT = "/metadata/raw/"
CLEAN_PLUS_LAYERS = (
    "/metadata/clean/",
    "/metadata/core/",
    "/metadata/enrich/",
    "/metadata/dw/",
    "/metadata/metric/",
)


def _load_metadata(path: Path) -> Dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: root must be a mapping")
    return data


def _try_load_metadata(path: Path) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Load metadata YAML; return (data, error_message). Used for resilient repo scans."""
    try:
        return _load_metadata(path), None
    except (OSError, yaml.YAMLError, ValueError) as exc:
        return None, str(exc)


def _is_raw_metadata(path: Path) -> bool:
    return RAW_LAYER_SEGMENT in path.as_posix()


def _is_clean_plus_metadata(path: Path) -> bool:
    posix = path.as_posix()
    return any(layer in posix for layer in CLEAN_PLUS_LAYERS)


def _validate_domain_name(domain: str) -> str:
    """``dags/<domain>/`` folder name — matches compiler ``domain_arg_type``."""
    if not _VALID_SCOPE_SEGMENT_RE.match(domain):
        raise ValueError(
            f"Invalid domain name {domain!r}: only alphanumeric characters, "
            "underscores, and hyphens are allowed."
        )
    return domain


def _validate_dag_scope_path(dag: str) -> str:
    """Repo-relative path under ``dags/`` (e.g. ``governance/metabase``)."""
    clean = dag.replace("\\", "/").strip("/")
    if clean.startswith("dags/"):
        clean = clean[len("dags/") :]
    parts = [part for part in clean.split("/") if part]
    if not parts:
        raise ValueError(f"Invalid --dag {dag!r}: path must not be empty.")
    for part in parts:
        if part in (".", "..") or not _VALID_SCOPE_SEGMENT_RE.match(part):
            raise ValueError(
                f"Invalid --dag {dag!r}: each segment must be alphanumeric "
                "(underscores/hyphens allowed); '..' is not permitted."
            )
    return "/".join(parts)


def _assert_resolves_under_dags_root(dags_root: Path, target: Path) -> None:
    """Defence in depth after joining scope flags under ``dags/``."""
    try:
        target.resolve().relative_to(dags_root.resolve())
    except (ValueError, OSError) as exc:
        raise ValueError(f"Scope path {target} must resolve under {dags_root}") from exc


def _domain_arg_type(value: str) -> str:
    try:
        return _validate_domain_name(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def _dag_arg_type(value: str) -> str:
    try:
        return _validate_dag_scope_path(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def _paths_in_domain(dags_root: Path, domain: str) -> Set[Path]:
    _validate_domain_name(domain)
    domain_base = dags_root / domain
    _assert_resolves_under_dags_root(dags_root, domain_base)
    if not domain_base.is_dir():
        raise FileNotFoundError(f"Domain folder not found: {domain_base}")
    return set(domain_base.rglob("metadata/*/*.yml"))


def _paths_in_dag(dags_root: Path, dag: str) -> Set[Path]:
    dag_rel = _validate_dag_scope_path(dag)
    dag_base = dags_root / dag_rel
    _assert_resolves_under_dags_root(dags_root, dag_base)
    if not dag_base.is_dir():
        raise FileNotFoundError(f"DAG folder not found: {dag_base}")
    return set(dag_base.rglob("metadata/*/*.yml"))


def _normalize_owner_filter(owner: str) -> str:
    owner_norm = owner.strip().lower()
    if not owner_norm:
        raise ValueError("--owner must be a non-empty email address")
    return owner_norm


def _paths_for_owner(dags_root: Path, owner: str) -> Set[Path]:
    owner_norm = _normalize_owner_filter(owner)
    paths: Set[Path] = set()
    for meta_path in dags_root.rglob("metadata/*/*.yml"):
        data, err = _try_load_metadata(meta_path)
        if err or data is None:
            continue
        file_owner = str(data.get("owner") or "").strip().lower()
        if file_owner == owner_norm:
            paths.add(meta_path)
    return paths


def _paths_for_fqn(dags_root: Path, fqn: str) -> Set[Path]:
    if "." not in fqn:
        raise ValueError(
            f"Invalid --fqn {fqn!r}; expected format database_name.table_name"
        )
    database_name, table_name = fqn.split(".", 1)
    paths: Set[Path] = set()
    for meta_path in dags_root.rglob("metadata/*/*.yml"):
        data, err = _try_load_metadata(meta_path)
        if err or data is None:
            continue
        if (
            data.get("database_name") == database_name
            and data.get("table_name") == table_name
        ):
            paths.add(meta_path)
    return paths


def resolve_scope_paths(
    repo_root: Path,
    *,
    domain: Optional[str] = None,
    owner: Optional[str] = None,
    dag: Optional[str] = None,
    fqn: Optional[str] = None,
    extra_files: Optional[Sequence[Path]] = None,
) -> List[Path]:
    """Resolve metadata inventory for the user-requested scope.

    Multiple scope flags are combined by **intersection** (e.g. domain + owner).
    """
    dags_root = repo_root / "dags"
    filters: List[Set[Path]] = []

    if extra_files:
        filters.append(set(extra_files))
    if domain:
        filters.append(_paths_in_domain(dags_root, domain))
    if dag:
        filters.append(_paths_in_dag(dags_root, dag))
    if owner:
        filters.append(_paths_for_owner(dags_root, owner))
    if fqn:
        filters.append(_paths_for_fqn(dags_root, fqn))

    if not filters:
        return []

    paths = set.intersection(*filters)
    return sorted(paths)


def collect_distinct_owners(
    paths: Sequence[Path],
) -> Tuple[List[Tuple[str, int, str]], List[str]]:
    """Return ((owner_email, file_count, status), ...) and YAML load warnings.

    Offline audit lists MISSING vs UNVERIFIED only. ACTIVE/INACTIVE requires
    online verification (Trino MCP / ``trino/SKILL.md`` / org_chart). Unreadable YAML is skipped with
    a warning (scope scans remain resilient).
    """
    by_owner: DefaultDict[str, List[Path]] = defaultdict(list)
    yaml_load_errors: List[str] = []
    for path in paths:
        if not path.is_file():
            continue
        data, err = _try_load_metadata(path)
        if err or data is None:
            yaml_load_errors.append(f"{path}: {err}")
            continue
        owner = str(data.get("owner") or "").strip().lower() or "(missing)"
        by_owner[owner].append(path)

    rows: List[Tuple[str, int, str]] = []
    for owner, owner_paths in sorted(by_owner.items()):
        status = "MISSING" if owner == "(missing)" else "UNVERIFIED"
        rows.append((owner, len(owner_paths), status))
    return rows, yaml_load_errors


def validate_metadata_file(path: Path) -> Tuple[bool, List[str]]:
    """Return (passed, blocking_issues).

    CI and scope audit use this for **F2-01 table + F2-02 column** substantive
    descriptions on clean+ layers. Yamale (``validate-metadata-files-content``)
    already validates owner, domain, table/column description length, and
    ``columns`` map shape.
    """
    blocking: List[str] = []
    data, load_err = _try_load_metadata(path)
    if load_err or data is None:
        blocking.append(load_err or f"{path}: failed to load metadata YAML")
        return (False, blocking)

    database_name = data.get("database_name")
    table_name = data.get("table_name")
    description = data.get("description")
    columns = data.get("columns") or {}

    if _is_raw_metadata(path) or not _is_clean_plus_metadata(path):
        return (True, blocking)

    desc = str(description).strip() if description is not None else ""
    if not desc:
        blocking.append("F2-01 table_description_missing")
    else:
        table_tdq = assess_table_description_quality(
            database_name, table_name, description
        )
        if not table_tdq.is_substantive:
            reason = table_tdq.reason_code or "not_substantive"
            blocking.append(f"F2-01 table_description_not_substantive: {reason}")

    if not isinstance(columns, dict):
        blocking.append(
            f"{path}: columns must be a mapping (dict); invalid YAML shape for metadata columns"
        )
        return (False, blocking)

    insufficient: List[str] = []
    for col_name, col_meta in columns.items():
        if (
            col_name.lower() in PARTITION_COLUMNS
            or col_name.lower() in CDC_PLUMBING_COLUMNS
            or col_name in PLACEHOLDER_COLUMNS
        ):
            continue
        if not isinstance(col_meta, dict):
            blocking.append(f"{path}: column {col_name!r} must be a mapping (dict)")
            continue
        col_desc = col_meta.get("description")
        result = assess_column_description_quality(
            database_name, table_name, col_name, col_desc
        )
        if not result.is_substantive:
            insufficient.append(f"{col_name} ({result.reason_code})")

    if insufficient:
        suffix = " ..." if len(insufficient) > 20 else ""
        blocking.append(
            "F2-02 column_description_not_substantive: "
            + ", ".join(insufficient[:20])
            + suffix
        )

    return (len(blocking) == 0, blocking)


@dataclass
class ScopeAuditResult:
    paths: List[Path] = field(default_factory=list)
    missing_paths: List[Path] = field(default_factory=list)
    owner_rows: List[Tuple[str, int, str]] = field(default_factory=list)
    f2_failures: List[Tuple[Path, List[str]]] = field(default_factory=list)
    raw_file_count: int = 0
    raw_with_columns_count: int = 0
    yaml_load_errors: List[str] = field(default_factory=list)

    @property
    def existing_file_count(self) -> int:
        return sum(1 for path in self.paths if path.is_file())

    @property
    def parsed_file_count(self) -> int:
        return sum(count for _owner, count, _status in self.owner_rows)

    @property
    def gate_a_passed(self) -> bool:
        if self.missing_paths:
            return False
        if self.existing_file_count > 0 and self.parsed_file_count == 0:
            return False
        return not any(owner == "(missing)" for owner, _n, _s in self.owner_rows)

    @property
    def gate_b_passed(self) -> bool:
        return not self.f2_failures


def audit_scope_paths(paths: Sequence[Path]) -> ScopeAuditResult:
    result = ScopeAuditResult(paths=list(paths))
    existing_paths = [path for path in paths if path.is_file()]
    result.missing_paths = [path for path in paths if not path.is_file()]
    result.owner_rows, result.yaml_load_errors = collect_distinct_owners(existing_paths)

    for path in existing_paths:
        if _is_raw_metadata(path):
            result.raw_file_count += 1
            _data, err = _try_load_metadata(path)
            if err:
                continue
            columns = _data.get("columns") if _data else None
            if isinstance(columns, dict) and columns:
                result.raw_with_columns_count += 1
            continue
        if not _is_clean_plus_metadata(path):
            continue
        ok, blocking = validate_metadata_file(path)
        if not ok and blocking:
            result.f2_failures.append((path, blocking))

    return result


def print_scope_audit_report(
    result: ScopeAuditResult,
    *,
    scope_label: str,
) -> None:
    print(f"\n=== FAIR metadata scope audit — {scope_label} ===")
    print(f"Inventory: {len(result.paths)} metadata file(s)\n")

    print("=== Gate A — Owners (distinct owner emails in scope) ===")
    if result.existing_file_count > 0 and result.parsed_file_count == 0:
        print(
            f"  FAIL: {result.existing_file_count} file(s) on disk but none parsed "
            "(unreadable YAML — fix before EXECUTE)"
        )
    elif not result.owner_rows:
        print("  (no metadata files in scope)")
    else:
        for owner, count, status in result.owner_rows:
            print(f"  {owner:45} {count:4} file(s)  [{status}]")
    print(
        "\n  NOTE: Owner ACTIVE is not verified offline. Use Trino MCP or "
        "`trino/SKILL.md` with sql/check_owner_active.sql before EXECUTE."
    )
    missing = [o for o, _n, s in result.owner_rows if s == "MISSING"]
    if missing:
        print(f"\n  FAIL: {len(missing)} owner(s) missing: {', '.join(missing)}")

    print(
        "\n=== Gate B — substantive descriptions: table F2-01 + columns F2-02 "
        "(clean / core / enrich / dw / metric) ==="
    )
    print(
        "  NOTE: owner, domain, and min description length are validated by "
        "validate-metadata-files-content (Yamale)."
    )
    if not result.f2_failures:
        print("  PASS: no F2-01/F2-02 blocking issues in clean+ layers")
    else:
        print(f"  FAIL: {len(result.f2_failures)} file(s)")
        for path, issues in result.f2_failures:
            print(f"  - {path}")
            for issue in issues:
                print(f"      {issue}")

    if result.missing_paths:
        print(f"\n  FAIL: {len(result.missing_paths)} inventory path(s) not on disk:")
        for path in result.missing_paths:
            print(f"  - {path}")

    if result.raw_file_count:
        print("\n=== Raw layer (optional — not a blocking gate) ===")
        print(
            f"  {result.raw_file_count} raw file(s) in scope; "
            f"{result.raw_with_columns_count} document column(s)."
        )
        print(
            "  Raw column documentation is encouraged but not required; "
            "F2-01/F2-02 apply on clean+ only."
        )

    if result.yaml_load_errors:
        print(
            f"\n  WARN: {len(result.yaml_load_errors)} metadata file(s) "
            "skipped (unreadable YAML — fix or run validate-metadata-files-content):"
        )
        for msg in result.yaml_load_errors[:15]:
            print(f"  - {msg}")
        if len(result.yaml_load_errors) > 15:
            print(f"  ... and {len(result.yaml_load_errors) - 15} more")


def _git_branch_files(branch: str) -> List[Path]:
    from_ref = resolve_diff_from_ref(branch)
    fetch_diff_base(from_ref)
    out = subprocess.check_output(
        [
            "git",
            "diff",
            "--no-commit-id",
            "--name-status",
            "--no-renames",
            "-r",
            f"{from_ref}...HEAD",
        ],
        text=True,
    )
    paths: List[Path] = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status, file_path = parts[0], parts[-1]
        code = status[0] if status else ""
        if code not in UPSERT_STATUS:
            continue
        if METADATA_PATH_RE.search(file_path):
            paths.append(Path(file_path))
    return paths


def _scope_label(
    args: argparse.Namespace,
    *,
    explicit_file_count: Optional[int] = None,
) -> str:
    if explicit_file_count is not None:
        noun = "file" if explicit_file_count == 1 else "files"
        return f"explicit file list ({explicit_file_count} {noun})"
    parts: List[str] = []
    if args.domain:
        parts.append(f"domain={args.domain}")
    if args.owner:
        parts.append(f"owner={args.owner}")
    if args.dag:
        parts.append(f"dag={args.dag}")
    if args.fqn:
        parts.append(f"fqn={args.fqn}")
    return ", ".join(parts) if parts else "custom file list"


def _scope_flags_set(args: argparse.Namespace) -> bool:
    return any([args.domain, args.owner, args.dag, args.fqn])


def _scope_flags_ignored_with_files(args: argparse.Namespace) -> bool:
    return bool(args.files and _scope_flags_set(args))


def _branch_ignored_with_scope_flags(args: argparse.Namespace) -> bool:
    return bool(args.branch and _scope_flags_set(args))


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate metadata YAML for FAIR F2-01 (table description) and F2-02 "
            "(column descriptions). Schema checks (owner, domain, min length) run in "
            "validate-metadata-files-content. Owner ACTIVE is online-only. "
            "Use scope flags + --audit for Gate A/B scope inventory; "
            "use -b for PR diff (Woodpecker). "
            "For metadata vs SQL column names use validate-lineage-consistency."
        ),
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "-f",
        "--file",
        action="append",
        dest="files",
        help="Metadata YAML path (repeatable)",
    )
    mode.add_argument(
        "-b",
        "--branch",
        help="Git branch name; validate metadata files changed vs the PR target branch",
    )

    scope = parser.add_argument_group(
        "scope",
        "Resolve the full inventory the user requested (not PR diff). "
        "Combine --domain with --owner to intersect.",
    )
    scope.add_argument(
        "--domain",
        type=_domain_arg_type,
        help="Domain folder under dags/ (e.g. governance, for_rent)",
    )
    scope.add_argument(
        "--owner",
        help="Owner email — all metadata YAML with this owner in scope",
    )
    scope.add_argument(
        "--dag",
        type=_dag_arg_type,
        help="DAG path under dags/ (e.g. governance/metabase)",
    )
    scope.add_argument(
        "--fqn",
        help="Single table as database_name.table_name (all layers in repo)",
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help=(
            "Print Gate A/B scope audit report. Requires scope flags or -f. "
            "Exits non-zero when any gate fails."
        ),
    )
    return parser.parse_args(argv)


def _resolve_paths(args: argparse.Namespace, repo_root: Path) -> Tuple[List[Path], str]:
    if args.files:
        paths = [Path(f) for f in args.files]
        if _scope_flags_ignored_with_files(args):
            print(
                "WARN: --domain/--owner/--dag/--fqn ignored when -f/--file is set; "
                "audit runs on explicit files only.",
                file=sys.stderr,
            )
        return paths, _scope_label(args, explicit_file_count=len(paths))

    scope_used = _scope_flags_set(args)
    if scope_used:
        if _branch_ignored_with_scope_flags(args):
            print(
                "WARN: -b/--branch ignored when --domain/--owner/--dag/--fqn is set; "
                "audit runs on full scope inventory, not branch diff.",
                file=sys.stderr,
            )
        paths = resolve_scope_paths(
            repo_root,
            domain=args.domain,
            owner=args.owner,
            dag=args.dag,
            fqn=args.fqn,
        )
        return paths, _scope_label(args)

    if args.branch:
        return _git_branch_files(args.branch), f"branch={args.branch}"

    branch = subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        text=True,
    ).strip()
    return _git_branch_files(branch), f"branch={branch}"


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    repo_root = Path.cwd()

    if args.owner is not None and not args.owner.strip():
        print("Error: --owner must be a non-empty email address", file=sys.stderr)
        return 1

    if args.audit and not args.files and not _scope_flags_set(args):
        print(
            "Error: --audit requires scope flags (--domain/--owner/--dag/--fqn) "
            "or -f/--file; refusing to audit only the current branch diff.",
            file=sys.stderr,
        )
        return 1

    try:
        paths, label = _resolve_paths(args, repo_root)
    except (ValueError, FileNotFoundError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if not paths:
        print("No metadata files in scope.")
        return 0 if not args.audit else 1

    if args.audit:
        audit = audit_scope_paths(paths)
        print_scope_audit_report(audit, scope_label=label)
        if audit.gate_a_passed and audit.gate_b_passed:
            print("\nResult: All gates passed for scope.")
            return 0
        print("\nResult: Scope audit failed — remediate before EXECUTE.")
        return 1

    print(
        "F2-01 table + F2-02 column descriptions on clean+ — owner/domain/min length: "
        "validate-metadata-files-content (Yamale). Owner ACTIVE: online only "
        "(Trino MCP / trino/SKILL.md / org_chart)."
    )

    failed = 0
    missing = 0
    validated = 0
    skipped = 0
    for path in paths:
        if not path.is_file():
            missing += 1
            print(f"SKIP (missing): {path}")
            continue
        if _is_raw_metadata(path) or not _is_clean_plus_metadata(path):
            skipped += 1
            print(f"SKIP (not clean+): {path}")
            continue
        validated += 1
        ok, blocking = validate_metadata_file(path)
        if ok:
            print(f"PASS: {path}")
        else:
            failed += 1
            print(f"FAIL: {path}")
            for issue in blocking:
                print(f"  - {issue}")

    if validated == 0 and paths:
        if skipped and not missing:
            print(f"\nResult: No clean+ metadata files in scope ({skipped} skipped).")
            return 0
        print(f"\nResult: No metadata files found on disk ({missing} missing path(s)).")
        return 1
    if failed:
        print(f"\nResult: {failed} file(s) failed FAIR metadata validation.")
        return 1
    if missing:
        print(f"\nResult: {missing} metadata path(s) from scope missing on disk.")
        return 1
    print("\nResult: All files passed FAIR metadata validation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
