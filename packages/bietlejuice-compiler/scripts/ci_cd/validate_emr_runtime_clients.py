#!/usr/bin/env python3
"""Block new spark jobs that bypass the bietlejuice dual-runtime clients.

A job only works on both Databricks and EMR when it obtains its Spark session,
its ``dbutils`` handle, and its metastore service from the bietlejuice clients:

* ``SparkClient(app_name=JOB_NAME).conn`` -- the only path that reaches
  ``create_emr_spark_session()`` (Delta extension, ``DeltaCatalog``, s3a ACLs).
* ``BaseDBUtils().get_dbutils()`` -- returns the boto3-backed facade on EMR.
* ``MetastoreServiceFactory.create_loader_metastore_service(spark_client)`` --
  registers tables in both the Databricks catalog and AWS Glue.

Bare ``spark`` / ``dbutils`` globals exist only because Databricks injects them
into the job namespace; on EMR they raise ``NameError``. A direct
``SparkSession.builder`` or ``BaseSparkContext.spark`` builds a session that
skips the EMR factory, and a direct ``SparkMetastoreService`` registers the
table in the runtime-native catalog only -- both fail silently.

Only **added** files are checked (``RELEVANT_STATUSES``), so pre-existing
violations never block a PR. Use ``-a`` to audit the whole tree.

Usage (CI):
    python validate_emr_runtime_clients.py -b "$CI_COMMIT_BRANCH"

Usage (local audit -- list every bypass in dags/, exit 0):
    python validate_emr_runtime_clients.py -a
"""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path
from typing import Dict, Iterable, List, NamedTuple, Optional, Set

sys.path.append(str(Path(__file__).parent.parent))
from services.git_service import GitService

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref

REPO_ROOT = Path(__file__).resolve().parents[4]
# Added files only: a legacy file never enters the diff as "A", so existing
# debt cannot block a PR. Add "M" here to also gate edits to existing jobs.
RELEVANT_STATUSES = frozenset({"A"})
SCANNED_GLOB = "dags/*/*/spark_jobs/*.py"

RULE_BARE_SPARK = "bare-spark"
RULE_SPARK_BUILDER = "spark-builder"
RULE_BASE_SPARK_CONTEXT = "base-spark-context"
RULE_BARE_DBUTILS = "bare-dbutils"
RULE_DIRECT_METASTORE = "direct-metastore-service"

MESSAGES = {
    RULE_BARE_SPARK: (
        "bare 'spark' global (Databricks-injected; NameError on EMR); "
        "use spark_client = SparkClient(app_name=JOB_NAME) / spark = spark_client.conn"
    ),
    RULE_SPARK_BUILDER: (
        "SparkSession.builder bypasses create_emr_spark_session (no Delta "
        "extension, DeltaCatalog or s3a ACLs); use SparkClient.conn"
    ),
    RULE_BASE_SPARK_CONTEXT: (
        "BaseSparkContext builds its session at import time and is not "
        "Glue-backed on EMR; use SparkClient.conn"
    ),
    RULE_BARE_DBUTILS: (
        "bare 'dbutils' global (Databricks-injected; NameError on EMR); "
        "use dbutils = BaseDBUtils().get_dbutils()"
    ),
    RULE_DIRECT_METASTORE: (
        "SparkMetastoreService registers in the runtime-native catalog only, "
        "bypassing the Glue/UC sync; use "
        "MetastoreServiceFactory.create_loader_metastore_service(spark_client)"
    ),
}

# Bare globals that Databricks injects and EMR does not.
INJECTED_GLOBALS = {"spark": RULE_BARE_SPARK, "dbutils": RULE_BARE_DBUTILS}
# Calls that legitimately wrap a SparkMetastoreService into the composite.
METASTORE_FACTORIES = {"MetastoreServiceFactory", "MetastoreLoaderFactory"}


class Violation(NamedTuple):
    path: str
    line: int
    rule: str

    def render(self) -> str:
        return f"  {self.path}:{self.line}: {self.rule}: {MESSAGES[self.rule]}"


def _attribute_root(node: ast.AST) -> Optional[str]:
    """Return the right-most name of a dotted expression, if it is a plain path.

    ``SparkSession`` -> ``"SparkSession"``;
    ``pyspark.sql.SparkSession`` -> ``"SparkSession"``; a subscript / call -> None.
    """
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


class _ScopeCollector(ast.NodeVisitor):
    """Collect every name bound directly in one scope, without descending into
    nested function/class scopes (those get their own collector)."""

    def __init__(self) -> None:
        self.bound: Set[str] = set()
        self.declared_global: Set[str] = set()

    # -- bindings ---------------------------------------------------------
    def visit_Name(self, node: ast.Name) -> None:
        if isinstance(node.ctx, (ast.Store, ast.Del)):
            self.bound.add(node.id)

    def visit_arg(self, node: ast.arg) -> None:
        self.bound.add(node.arg)

    def visit_alias(self, node: ast.alias) -> None:
        name = node.asname or node.name.split(".")[0]
        self.bound.add(name)

    def visit_Global(self, node: ast.Global) -> None:
        self.declared_global.update(node.names)
        self.bound.update(node.names)

    def visit_Nonlocal(self, node: ast.Nonlocal) -> None:
        self.bound.update(node.names)

    # -- nested scopes: record the name, do not descend --------------------
    def _visit_scope_def(self, node: ast.AST) -> None:
        self.bound.add(node.name)  # type: ignore[attr-defined]

    visit_FunctionDef = _visit_scope_def
    visit_AsyncFunctionDef = _visit_scope_def
    visit_ClassDef = _visit_scope_def

    def visit_Lambda(self, node: ast.Lambda) -> None:
        return


def _collect_scope(node: ast.AST) -> _ScopeCollector:
    collector = _ScopeCollector()
    for child in ast.iter_child_nodes(node):
        # Decorators and default values evaluate in the *enclosing* scope, but
        # treating them as local only ever adds bindings, never removes them,
        # so it cannot create a false positive.
        collector.visit(child)
    return collector


def _scope_bodies(node: ast.AST) -> Iterable[ast.AST]:
    """Child scopes of a module/function/class node."""
    for child in ast.walk(node):
        if child is node:
            continue
        if isinstance(
            child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)
        ):
            yield child


class RuntimeClientChecker(ast.NodeVisitor):
    """Report bypasses of the bietlejuice dual-runtime clients in one module."""

    def __init__(
        self, path: str, tree: ast.Module, exempt_calls: Optional[Set[int]] = None
    ) -> None:
        self.path = path
        self.violations: List[Violation] = []
        self._exempt_metastore_calls = exempt_calls or set()
        self._bound_stack: List[Set[str]] = [self._module_bindings(tree)]

    @staticmethod
    def _module_bindings(tree: ast.Module) -> Set[str]:
        """Module-scope bindings, plus anything a function declares ``global``
        and then assigns (which binds at module scope)."""
        bindings = _collect_scope(tree).bound
        for scope in _scope_bodies(tree):
            if isinstance(scope, ast.Lambda):
                continue
            collector = _collect_scope(scope)
            bindings |= collector.declared_global
        return bindings

    # -- scope handling ---------------------------------------------------
    def _enter_scope(self, node: ast.AST) -> None:
        self._bound_stack.append(_collect_scope(node).bound)

    def _visit_scope(self, node: ast.AST) -> None:
        self._enter_scope(node)
        try:
            self.generic_visit(node)
        finally:
            self._bound_stack.pop()

    visit_FunctionDef = _visit_scope
    visit_AsyncFunctionDef = _visit_scope
    visit_ClassDef = _visit_scope
    visit_Lambda = _visit_scope

    def _is_bound(self, name: str) -> bool:
        return any(name in scope for scope in self._bound_stack)

    def _report(self, node: ast.AST, rule: str) -> None:
        self.violations.append(
            Violation(path=self.path, line=getattr(node, "lineno", 0), rule=rule)
        )

    # -- rules ------------------------------------------------------------
    def visit_Name(self, node: ast.Name) -> None:
        rule = INJECTED_GLOBALS.get(node.id)
        if rule and isinstance(node.ctx, ast.Load) and not self._is_bound(node.id):
            self._report(node, rule)
        self.generic_visit(node)

    def visit_Attribute(self, node: ast.Attribute) -> None:
        root = _attribute_root(node.value)
        if node.attr == "builder" and root == "SparkSession":
            self._report(node, RULE_SPARK_BUILDER)
        elif node.attr in ("spark", "sc") and root == "BaseSparkContext":
            self._report(node, RULE_BASE_SPARK_CONTEXT)
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        if (
            _attribute_root(node.func) == "SparkMetastoreService"
            and id(node) not in self._exempt_metastore_calls
        ):
            self._report(node, RULE_DIRECT_METASTORE)
        self.generic_visit(node)


def _sanctioned_metastore_calls(tree: ast.Module) -> Set[int]:
    """``MetastoreServiceFactory.create(SparkMetastoreService(client))`` is the
    sanctioned composite wiring, not a bypass. Collected up front so the result
    does not depend on visit order."""
    exempt: Set[int] = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if _attribute_root(node.func.value) not in METASTORE_FACTORIES:
            continue
        for arg in node.args:
            if isinstance(arg, ast.Call):
                exempt.add(id(arg))
    return exempt


def check_source(path: str, source: str) -> List[Violation]:
    """Return violations for one module. A syntax error is reported and skipped."""
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        print(f"  {path}:{exc.lineno}: syntax error: {exc.msg}", file=sys.stderr)
        return []
    checker = RuntimeClientChecker(path, tree, _sanctioned_metastore_calls(tree))
    checker.visit(tree)
    return sorted(checker.violations, key=lambda v: (v.line, v.rule))


def is_scanned_path(repo_relative: str) -> bool:
    path = Path(repo_relative)
    parts = path.parts
    return (
        len(parts) == 5
        and parts[0] == "dags"
        and parts[3] == "spark_jobs"
        and path.suffix == ".py"
        and path.name != "__init__.py"
    )


def added_spark_jobs(changed_files: Dict[str, str]) -> List[str]:
    return sorted(
        path
        for path, status in changed_files.items()
        if status in RELEVANT_STATUSES and is_scanned_path(path)
    )


def collect_violations(branch: str) -> List[Violation]:
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    changed = git_service.get_modified_files_from_diff(from_ref, "HEAD")

    violations: List[Violation] = []
    for repo_relative in added_spark_jobs(changed):
        absolute = REPO_ROOT / repo_relative
        if not absolute.is_file():
            continue
        violations.extend(
            check_source(repo_relative, absolute.read_text(encoding="utf-8"))
        )
    return violations


def audit_all() -> List[Violation]:
    violations: List[Violation] = []
    for absolute in sorted(REPO_ROOT.glob(SCANNED_GLOB)):
        repo_relative = str(absolute.relative_to(REPO_ROOT))
        if not is_scanned_path(repo_relative):
            continue
        violations.extend(
            check_source(repo_relative, absolute.read_text(encoding="utf-8"))
        )
    return violations


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Fail if a newly added spark job bypasses SparkClient, BaseDBUtils "
            "or the dual-catalog metastore factory."
        )
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", help="Current branch (CI_COMMIT_BRANCH)")
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="List every bypass in dags/ (local audit, exit 0)",
    )
    return parser.parse_args()


def _print_by_rule(violations: List[Violation], stream) -> None:
    by_rule: Dict[str, List[Violation]] = {}
    for violation in violations:
        by_rule.setdefault(violation.rule, []).append(violation)
    for rule in (
        RULE_BARE_SPARK,
        RULE_BARE_DBUTILS,
        RULE_SPARK_BUILDER,
        RULE_BASE_SPARK_CONTEXT,
        RULE_DIRECT_METASTORE,
    ):
        found = by_rule.get(rule)
        if not found:
            continue
        files = sorted({v.path for v in found})
        print(
            f"\n{rule}: {len(found)} occurrence(s) in {len(files)} file(s)",
            file=stream,
        )
        for violation in found:
            print(violation.render(), file=stream)


def main() -> int:
    args = parse_args()

    if args.all_files:
        violations = audit_all()
        files = sorted({v.path for v in violations})
        print(
            f"Found {len(violations)} bypass(es) in {len(files)} spark job file(s) "
            "(audit mode, always exit 0):"
        )
        _print_by_rule(violations, sys.stdout)
        return 0

    violations = collect_violations(args.branch)
    if not violations:
        print("OK: No new spark job bypasses the dual-runtime clients.")
        return 0

    files = sorted({v.path for v in violations})
    print(
        f"\nFound {len(violations)} dual-runtime client bypass(es) in "
        f"{len(files)} newly added spark job file(s):",
        file=sys.stderr,
    )
    _print_by_rule(violations, sys.stderr)
    print(
        "\nNew spark jobs must obtain their session, dbutils handle and "
        "metastore service from bietlejuice:\n"
        "    spark_client = SparkClient(app_name=JOB_NAME)\n"
        "    spark = spark_client.conn\n"
        "    dbutils = BaseDBUtils().get_dbutils()\n"
        "    metastore_service = "
        "MetastoreServiceFactory.create_loader_metastore_service(spark_client)\n"
        "See .cursor/rules/python_conventions.mdc for the full rule.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
