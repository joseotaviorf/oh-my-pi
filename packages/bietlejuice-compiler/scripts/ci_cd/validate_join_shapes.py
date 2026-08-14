#!/usr/bin/env python3
"""Block join shapes that Spark can only plan as a BroadcastNestedLoopJoin.

A join whose ON condition has no top-level equi-predicate across two different table
aliases gives the Spark planner no hash key. On EMR (no RANGE_JOIN bin strategy, no
Databricks-only SKEW handling) the only physical plan left is a BroadcastNestedLoopJoin —
O(N x M), and its parallelism is bounded by the streaming side's partition count. Two
concrete incidents this shape caused in production:

  * enrich_cyber/queue_timeline.sql — a pure inequality (BETWEEN) join with no equi-key.
    Built a 186 MiB broadcast and ran the whole join on a single task.
  * enrich_transactional_entities/entities.sql — `ON u.id = hl.id_related OR u.uuid_person
    = hl.id_related`. A top-level OR gives no extractable key at all. Built a 634 MiB
    broadcast; the DAG never completed a run on EMR (see PRs #27637, #27641, #27643).

This scans every SQL file that appears in the current git diff (new or modified) and fails
if any join in it cannot be hash-joined. Existing, unmodified files are never inspected in
branch mode — see .cursor/skills/databricks-emr-sql-lint/RECIPES.md §8-9 for verified
rewrites (equi-join + window for range joins, UNION of equi-joins for disjunctive joins).

Usage (CI — branch resolved via CI_COMMIT_BRANCH):
    python validate_join_shapes.py -b "$CI_COMMIT_BRANCH"

Usage (local — check the DAG folder you're working on):
    python validate_join_shapes.py --paths dags/growth/enrich_transactional_entities

Usage (local — check a whole domain):
    python validate_join_shapes.py --domain growth

Usage (local — check one file):
    python validate_join_shapes.py --paths dags/growth/.../entities.sql

Usage (scan every .sql file under dags/):
    python validate_join_shapes.py -a
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional

import sqlglot
from sqlglot import exp

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref

# Two import contexts need to work: (1) direct script execution, e.g.
# `python .../scripts/ci_cd/validate_join_shapes.py` (how the Makefile/CI run this), where
# only this file's own directory is on sys.path — `scripts` is not importable as a package
# unless PYTHONPATH is set; and (2) pytest, which imports this module as
# `scripts.ci_cd.validate_join_shapes` — under `--import-mode=importlib`, a bare
# `sys.path.append(parent.parent); import ci_cd.domain_cli` inside an already-namespaced
# `scripts.ci_cd.*` module can fail to resolve. Try the package-qualified form first, since
# that's what a `scripts`-aware environment (pytest, or CI if PYTHONPATH is set) expects;
# fall back to appending this file's own `scripts/` directory otherwise.
try:
    from scripts.ci_cd.domain_cli import domain_arg_type, repo_relative_file_arg_type
    from scripts.services.git_service import GitService
except ImportError:
    sys.path.append(str(Path(__file__).parent.parent))
    from ci_cd.domain_cli import (  # noqa: E402
        domain_arg_type,
        repo_relative_file_arg_type,
    )
    from services.git_service import GitService  # noqa: E402

# ---------------------------------------------------------------------------
# Normalization
#
# Deliberately NOT sql_table_extractor.normalize_sql_for_table_extraction(): that helper
# substitutes 'DUMMY' *including quotes* into an already-quoted placeholder --
# DATE('{load_start_date}') becomes DATE(''DUMMY''), a broken string literal that fails to
# parse. That bug currently makes ~28% of this repo's SQL files unparseable by sqlglot.
# Fixing the shared helper is out of scope here (it would change source-layer-validation
# behaviour); this module keeps its own normalizer so this change cannot affect it.
# ---------------------------------------------------------------------------
_BLOCK_COMMENT_RE = re.compile(r"/\*(?!\+).*?\*/", re.DOTALL)  # not /*+ hint */
_LINE_COMMENT_RE = re.compile(
    r"--[^\n]*"
)  # does not consume \n: line count is preserved
_QUOTED_PARAM_RE = re.compile(
    r"'\{[A-Za-z_]\w*\}'"
)  # '{param}' -> 'DUMMY'  (order matters)
_BARE_PARAM_RE = re.compile(r"\{[A-Za-z_]\w*\}")  # {param}   -> 'DUMMY'


def _blank_preserving_newlines(match: "re.Match[str]") -> str:
    """Replace a matched span with a single space, keeping every newline it contained.

    Used for block comments, which can span multiple lines. Losing those newlines would
    shift every line number reported for code after the comment.
    """
    return " " + "\n" * match.group(0).count("\n")


def normalize_sql_for_join_lint(sql: str) -> str:
    """Strip comments and replace templating so sqlglot can parse pipeline SQL.

    Per databricks_conventions.mdc "Literal Braces": this pipeline runs `str.format` on
    every SQL file, so `{param}` is a template placeholder and a literal `{`/`}` (regex
    quantifiers, JSON) must be written as `{{`/`}}`. Each doubled brace is an INDEPENDENT
    escape for one literal character -- `{{2,3}}` unescapes to `{2,3}`, not "a Jinja-style
    `{{ ... }}` block whose contents get replaced". Treating a `{{...}}` span as a single
    unit (an earlier version of this function did) corrupts every file using this documented
    escape: `REGEXP_LIKE(x, '^[0-9]{{6}}$')` has its `{{6}}` swallowed whole and replaced
    with `'DUMMY'`, splitting the string literal and making otherwise-valid SQL
    UNPARSEABLE -- which is a blocking finding in -b/CI mode. So `{{`/`}}` are unescaped
    to single braces FIRST; only a genuine single-brace `{identifier}` left after that
    (a real template param) is replaced with `'DUMMY'`.

    Line numbers are load-bearing here (see _locate_joins_by_line), so every substitution
    preserves the newline count of what it replaces (none of the brace substitutions can
    introduce or remove a newline, since `{{`/`}}`/`{param}` never contain one in practice).
    """
    sql = _BLOCK_COMMENT_RE.sub(_blank_preserving_newlines, sql)
    sql = _LINE_COMMENT_RE.sub("", sql)
    sql = sql.replace("{{", "{").replace("}}", "}")
    sql = _QUOTED_PARAM_RE.sub("'DUMMY'", sql)  # must run before the bare-param pass
    sql = _BARE_PARAM_RE.sub("'DUMMY'", sql)
    return sql


class Violation(NamedTuple):
    filepath: str
    line_no: int
    kind: str  # OR_JOIN | NO_EQUI_KEY | UNPARSEABLE
    text: str


def _unwrap(node: exp.Expression) -> exp.Expression:
    while isinstance(node, exp.Paren):
        node = node.this
    return node


def _has_equi_key(condition: exp.Expression) -> bool:
    """Mirror Spark's ExtractEquiJoinKeys: split on top-level AND, look for an equality
    between two column-referencing expressions that isn't provably a same-table comparison.

    Real Spark equi-join resolution uses the catalog to bind each side's columns to a
    relation, including unqualified ones. A syntactic lint has no catalog, so it cannot
    replicate that exactly -- but it also must not require BOTH sides to carry a table
    alias, or it flags ordinary equi-joins as having no key: `ON id_user_contract_final =
    u.id` (one side unqualified) and `ON offer_id = sk_offer` (both unqualified) are both
    genuine hash-joinable equi-keys in this repo's SQL, and requiring disjoint qualified
    aliases on both sides reported them as NO_EQUI_KEY.

    So the rule is inverted to only REJECT what can be positively shown to be an
    intra-relation comparison -- both sides qualified with the *same single* alias (e.g.
    `a.status = a.status_backup`), which links no second relation and so provides no join
    key. Everything else with a column on each side (qualified-different, qualified-vs-
    unqualified, unqualified-vs-unqualified) is accepted as a candidate key. This trades a
    handful of undetectable same-table-via-different-unqualified-names false negatives for
    eliminating false positives on real joins -- the right tradeoff for a merge-blocking
    check, where a false positive erodes trust in the whole gate.
    """
    condition = _unwrap(condition)
    conjuncts = (
        list(condition.flatten()) if isinstance(condition, exp.And) else [condition]
    )
    for conjunct in conjuncts:
        conjunct = _unwrap(conjunct)
        if not isinstance(conjunct, exp.EQ):
            continue
        left, right = _unwrap(conjunct.this), _unwrap(conjunct.expression)
        left_cols = list(left.find_all(exp.Column))
        right_cols = list(right.find_all(exp.Column))
        if not left_cols or not right_cols:
            continue  # one side is a literal/constant -- a filter, not a join key
        left_tables = {c.table.lower() for c in left_cols if c.table}
        right_tables = {c.table.lower() for c in right_cols if c.table}
        if (
            left_tables
            and right_tables
            and left_tables == right_tables
            and len(left_tables) == 1
        ):
            continue  # both sides qualified with the same single alias: not cross-relation
        return True
    return False


_JOIN_KEYWORD_RE = re.compile(r"\bJOIN\b", re.IGNORECASE)


def _join_clause_spans(normalized_sql: str) -> List[tuple]:
    """(start, end) character offsets for each `JOIN ... <next JOIN or EOF>` region."""
    starts = [m.start() for m in _JOIN_KEYWORD_RE.finditer(normalized_sql)]
    return [(s, e) for s, e in zip(starts, starts[1:] + [len(normalized_sql)])]


def _locate_line_for_condition(
    normalized_sql: str,
    condition: exp.Expression,
    join_spans: List[tuple],
    used_spans: List[int],
) -> int:
    """Best-effort source line for a flagged ON condition.

    sqlglot does not attach source positions to parsed nodes, and `find_all(exp.Join)`'s
    traversal order does not reliably track source order once CTEs nest (a CTE's own
    `WITH` block, or a UNION branch, can visit before or after sibling joins that appear
    earlier or later in the text) — verified empirically: for a file with 18 joins across
    nested CTEs, zipping AST order against a plain keyword scan misattributed a real
    violation to an unrelated join 79 lines away.

    Locating by content (searching the whole file for the condition's columns near an ON
    keyword) has its own failure mode: when joins sit close together, a lazy `.*?` window
    can jump straight past a join boundary and match columns that actually belong to the
    *next* join's ON clause.

    So: content search is bounded to a single join's own span — from its `JOIN` keyword to
    the next one (or EOF) — which cannot cross into a neighbouring join no matter how
    close together they are. `used_spans` (indices into `join_spans`) stops two distinct
    violations whose conditions reference the same columns (e.g. a pattern duplicated
    across near-identical CTEs) from both being attributed to the same span.
    """
    columns = list(condition.find_all(exp.Column))[:2]
    if not columns:
        return 1

    parts = []
    for col in columns:
        name = re.escape(col.name)
        parts.append(rf"{re.escape(col.table)}\s*\.\s*{name}" if col.table else name)
    pattern = re.compile(
        r"\bON\b[\s\S]{0,400}?" + r"[\s\S]{0,150}?".join(parts), re.IGNORECASE
    )

    for idx, (start, end) in enumerate(join_spans):
        if idx in used_spans:
            continue
        match = pattern.search(normalized_sql, start, end)
        if match:
            used_spans.append(idx)
            # match.start() is the ON keyword itself (the pattern begins with \bON\b), not
            # the chunk's start (the JOIN keyword) — they commonly differ, since the
            # table/alias is usually on its own line between JOIN and ON in this repo's SQL.
            return normalized_sql[: match.start()].count("\n") + 1
    return 1


def scan_sql_text(sql_text: str, filepath: str) -> List[Violation]:
    violations: List[Violation] = []
    normalized = normalize_sql_for_join_lint(sql_text)
    try:
        statements = sqlglot.parse(normalized, read="spark")
    except (
        Exception
    ) as exc:  # sqlglot raises ParseError / TokenError, both re-raised here
        return [Violation(filepath, 1, "UNPARSEABLE", str(exc).splitlines()[0][:160])]

    all_joins: List[exp.Join] = []
    for statement in statements:
        if statement is not None:
            all_joins.extend(statement.find_all(exp.Join))
    join_spans = _join_clause_spans(normalized)
    used_spans: List[int] = []

    for join in all_joins:
        condition = join.args.get("on")
        if condition is None:
            continue  # CROSS JOIN / USING — not a hash-key concern for this check
        condition = _unwrap(condition)
        if isinstance(condition, exp.Or):
            line_no = _locate_line_for_condition(
                normalized, condition, join_spans, used_spans
            )
            violations.append(
                Violation(
                    filepath, line_no, "OR_JOIN", condition.sql(dialect="spark")[:120]
                )
            )
        elif not _has_equi_key(condition):
            line_no = _locate_line_for_condition(
                normalized, condition, join_spans, used_spans
            )
            violations.append(
                Violation(
                    filepath,
                    line_no,
                    "NO_EQUI_KEY",
                    condition.sql(dialect="spark")[:120],
                )
            )
    return violations


def scan_file(path: Path) -> List[Violation]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"WARNING: cannot read {path}: {exc}", file=sys.stderr)
        return []
    return scan_sql_text(text, str(path))


def get_changed_sql_files(branch: str) -> List[Path]:
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    diff: Dict[str, str] = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    return [
        Path(filepath)
        for filepath, status in diff.items()
        if filepath.endswith(".sql")
        and status in git_service.UPSERT_STATUS_CODES
        and not filepath.startswith("dags/platform/migration_")
    ]


def get_all_sql_files() -> List[Path]:
    return list(Path("dags").rglob("*.sql"))


def expand_paths(raw_paths: List[str]) -> List[Path]:
    """Resolve a mix of files and directories into a flat list of .sql files.

    A directory is expanded recursively (rglob), so passing a DAG folder checks every
    query under it and passing a domain folder checks every DAG in that domain. A path
    that is neither an existing file nor an existing directory is a hard error rather
    than a silent skip, since a typo'd --paths argument should not report a false "clean".
    """
    files: List[Path] = []
    for raw in raw_paths:
        p = Path(raw)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.sql")))
        elif p.is_file():
            files.append(p)
        else:
            raise SystemExit(f"error: --paths target does not exist: {raw}")
    return files


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fail if a join in changed SQL files has no extractable hash key."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Current branch (CI_COMMIT_BRANCH)")
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="Scan all .sql files under dags/ (audit)",
    )
    group.add_argument(
        "--paths",
        nargs="+",
        type=repo_relative_file_arg_type,
        help="One or more files or directories to check (directories are scanned recursively)",
    )
    group.add_argument(
        "--domain",
        type=domain_arg_type,
        help="Check every .sql file under dags/<domain>/",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit findings as JSON (for tooling, e.g. the Cursor skill)",
    )
    return parser.parse_args()


def resolve_sql_files(args) -> Optional[List[Path]]:
    if args.all_files:
        return get_all_sql_files()
    if args.domain:
        return expand_paths([f"dags/{args.domain}"])
    if args.paths:
        return expand_paths(args.paths)
    return get_changed_sql_files(args.branch)


def main() -> int:
    args = parse_args()
    sql_files = resolve_sql_files(args)

    if not args.all_files and not args.paths and not args.domain and not sql_files:
        if not args.json:
            print("No changed SQL files detected — nothing to validate.")
        return 0

    if not args.json:
        label = "all" if args.all_files else "changed" if args.branch else "selected"
        print(f"Scanning {len(sql_files)} {label} SQL file(s)")

    all_violations: List[Violation] = []
    for path in sql_files:
        if path.exists():
            all_violations.extend(scan_file(path))

    # In branch/CI mode, new SQL that fails to parse is itself a failure. In audit mode
    # (-a) or ad-hoc local checks, an unparseable pre-existing file is a warning, not a
    # blocker — see the module docstring for the ~2% tail sqlglot still can't handle.
    blocking = [
        v
        for v in all_violations
        if v.kind != "UNPARSEABLE" or not (args.all_files or args.paths or args.domain)
    ]
    warnings = [v for v in all_violations if v not in blocking]

    if args.json:
        print(
            json.dumps(
                {
                    "violations": [v._asdict() for v in blocking],
                    "warnings": [v._asdict() for v in warnings],
                }
            )
        )
        return 1 if blocking else 0

    for v in warnings:
        print(
            f"  WARNING {v.filepath}:{v.line_no}: [{v.kind}] {v.text}", file=sys.stderr
        )

    if not blocking:
        print("OK: No nested-loop join risks found.")
        return 0

    print(
        f"\n❌  Found {len(blocking)} join(s) with no extractable hash key "
        "(these plan as BroadcastNestedLoopJoin on EMR — O(N x M), and have hung "
        "production DAGs before):\n",
        file=sys.stderr,
    )
    for v in blocking:
        print(f"  {v.filepath}:{v.line_no}: [{v.kind}] {v.text}", file=sys.stderr)
    print(
        "\nRewrite these joins before merging. See "
        ".cursor/skills/databricks-emr-sql-lint/RECIPES.md §8 (range joins) and §9 "
        "(disjunctive/OR joins) for verified rewrites.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
