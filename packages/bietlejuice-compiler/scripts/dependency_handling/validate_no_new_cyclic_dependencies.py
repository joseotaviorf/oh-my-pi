"""
Fails when a change introduces a cyclic dependency between DAGs that does not exist on the base
branch.

Why this exists: when the dependency graph contains a cycle, the generator breaks it by deleting
*every* edge inside it, not only the edge that closed it. On 2026-07-30 a single backwards read added
to `enrich_supply_leads` created a cycle across five supply DAGs, and regenerating `dependencies.yaml`
silently dropped 17 ordering edges -- including
`enrich_supply_acquisition -> enrich_supply_leads:load-enrich-leads-sks`. The next morning
`enrich_supply_acquisition` ran before `enrich_supply_leads` and `dw_growth.obt_supply` lost a full day
of leads and prospects. CI stayed green throughout, because
`validate_dependency_file_correctness.py` only checks that the committed file matches what the
generator produces -- and the generator produced the mangled file.

The generator cannot tell a new cycle from an old one: it has no notion of "before". So this script
builds the graph twice, once for the working tree and once for the point the branch diverged from (the
merge base, checked out into a throwaway git worktree), and compares the cycles found in each. Cycles
that already exist there are left alone; only new ones fail the build.

The baseline is the merge base rather than the tip of the base branch on purpose: a branch that has not
been rebased must be judged on the cycles *it* introduces, not on cycles that someone else has fixed on
the base branch in the meantime.

A cycle is identified by the set of DAGs taking part in it. So an unrelated change to a DAG that
already sits inside a cycle passes, while a change that pulls a new DAG into an existing cycle fails.

Known limitation: the base-branch graph is built from the base branch's `dags/` tree using the working
tree's compiler code, so a cycle caused purely by a change to the dependency-parsing code itself shows
up on both sides and is not reported.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from typing import Dict, FrozenSet, List, Optional

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.dependencies.bietlejuice_cyclic_dependency_finder import (
    BietlejuiceCyclicDependencyFinder,
)
from bietlejuice.base.dependencies.file_dependency_generator import (
    FileDependencyGenerator,
)
from bietlejuice.base.dependencies.ignored_dag_ids import (
    filter_ignored_dag_dependencies,
)
from bietlejuice.ci.ci_diff_ref import fetch_diff_base, resolve_diff_from_ref
from scripts.dependency_handling.automate_dependencies import (
    UNSTANDARD_DAGS_PATH,
    get_unstandard_dags_file_content,
)
from scripts.services.git_service import GitService

DEFAULT_TO_BRANCH = "HEAD"

SEPARATOR = "=" * 70

# A cycle is keyed by the set of DAGs that take part in it, and maps each of those DAGs to the
# dependencies of theirs that stay inside the cycle.
Cycle = Dict[str, List[str]]
CyclesByDags = Dict[FrozenSet[str], Cycle]


def build_dependency_graph() -> dict:
    """
    Builds the dependency graph of the current working tree, stopping right before cycles are broken.

    Mirrors `automate_dependencies.generate_dependencies`, minus the cycle removal and the manual
    modifications: manual modifications are applied after the cycle removal, so they cannot be what
    creates a cycle here.

    :return: A dictionary, in which keys are DAGs and values are lists of tasks
    :rtype: dict
    """
    dependency_generator = FileDependencyGenerator(
        get_unstandard_dags_file_content(UNSTANDARD_DAGS_PATH)
    )
    dependencies = dependency_generator.replace_table_dependencies_with_tasks(
        dependency_generator.table_dependencies_from_all_dags(),
        dependency_generator.map_tables_to_correspondent_tasks(),
    )
    dependencies = dependency_generator.treat_static_dag_exceptions(dependencies)
    return filter_ignored_dag_dependencies(dependencies)


def find_cycles() -> CyclesByDags:
    """
    Finds the cycles in the dependency graph of the current working tree.

    :return: The cycles, keyed by the set of DAGs taking part in each one
    :rtype: CyclesByDags
    """
    return {
        frozenset(cycle): cycle
        for cycle in BietlejuiceCyclicDependencyFinder.find_cyclic_dependencies_by_cycle(
            build_dependency_graph()
        )
    }


def resolve_base_commit(from_branch: str, to_branch: str) -> str:
    """
    Returns the commit the change diverged from, so that cycles someone else has already fixed on the
    base branch are not mistaken for cycles this change introduces.

    :param from_branch: The branch used as the comparison base. e.g. origin/master
    :type from_branch: str
    :param to_branch: The branch being compared. e.g. HEAD
    :type to_branch: str
    :return: The merge base of both branches, or `from_branch` itself when it cannot be determined
    :rtype: str
    """
    try:
        return _run(["git", "merge-base", from_branch, to_branch]).stdout.strip()
    except subprocess.CalledProcessError:
        print(
            f"WARNING: could not find the merge base of {from_branch} and {to_branch}, "
            f"comparing against {from_branch} directly."
        )
        return from_branch


def find_cycles_in_commit(commit: str) -> Optional[CyclesByDags]:
    """
    Finds the cycles in the dependency graph of the given commit, by checking it out into a throwaway
    git worktree and running this same script inside it.

    The worktree only provides the `dags/` tree: the interpreter and the compiler code are the ones of
    the current working tree, so the comparison isolates changes to the DAGs themselves.

    :param commit: The commit to build the graph from
    :type commit: str
    :return: The cycles, keyed by the set of DAGs taking part in each one, or None when the commit
        could not be inspected
    :rtype: Optional[CyclesByDags]
    """
    repository_root = _repository_root()
    with tempfile.TemporaryDirectory(
        prefix="bietlejuice-cycles-"
    ) as temporary_directory:
        worktree_path = os.path.join(temporary_directory, "base-commit")
        cycles_path = os.path.join(temporary_directory, "cycles.json")
        try:
            _run(
                [
                    "git",
                    "worktree",
                    "add",
                    "--detach",
                    "--quiet",
                    worktree_path,
                    commit,
                ],
                cwd=repository_root,
            )
        except subprocess.CalledProcessError as error:
            print(
                f"WARNING: could not check out '{commit}' to look for pre-existing cycles, so this "
                f"validation is being skipped. error={error.stderr}"
            )
            return None

        try:
            _run(
                [
                    sys.executable,
                    os.path.abspath(__file__),
                    "--dump-cycles",
                    cycles_path,
                ],
                cwd=worktree_path,
                # The graph is built from wherever the `dags` package resolves to, and that package is
                # only importable through the path. Same shape as the PYTHONPATH the Makefile exports,
                # but rooted at the worktree -- and deliberately not inheriting the parent's, so a
                # broken worktree fails loudly instead of silently falling back to the working tree.
                env={
                    **os.environ,
                    "PYTHONPATH": os.pathsep.join(
                        [
                            worktree_path,
                            os.path.join(
                                worktree_path, "packages", "bietlejuice-compiler"
                            ),
                        ]
                    ),
                },
            )
            with open(cycles_path) as cycles_file:
                return _deserialize_cycles(json.load(cycles_file))
        except (subprocess.CalledProcessError, OSError, ValueError) as error:
            print(
                f"WARNING: could not build the dependency graph of '{commit}', so this validation is "
                f"being skipped. error={error}"
            )
            return None
        finally:
            _run(
                ["git", "worktree", "remove", "--force", worktree_path],
                cwd=repository_root,
                check=False,
            )


def find_new_cycles(
    cycles: CyclesByDags, base_commit_cycles: CyclesByDags
) -> CyclesByDags:
    """
    Returns the cycles that exist in the working tree but not in the base commit.

    :param cycles: The cycles found in the working tree
    :type cycles: CyclesByDags
    :param base_commit_cycles: The cycles found in the base commit
    :type base_commit_cycles: CyclesByDags
    :return: The cycles introduced by the change
    :rtype: CyclesByDags
    """
    return {
        dags: cycle for dags, cycle in cycles.items() if dags not in base_commit_cycles
    }


def print_report(
    new_cycles: CyclesByDags, changed_files: List[str], base_commit: str
) -> None:
    """
    Prints the report of the cycles introduced by the change.

    :param new_cycles: The cycles introduced by the change
    :type new_cycles: CyclesByDags
    :param changed_files: The files changed by this change that belong to the DAGs in the cycles
    :type changed_files: List[str]
    :param base_commit: The commit the change is being compared against
    :type base_commit: str
    """
    print(SEPARATOR)
    print("NEW CYCLIC DAG DEPENDENCY INTRODUCED BY THIS CHANGE")
    print(SEPARATOR)
    cycle_count = len(new_cycles)
    print(
        f"This change creates {cycle_count} dependency "
        f"{'cycle' if cycle_count == 1 else 'cycles'} that {'does' if cycle_count == 1 else 'do'} "
        f"not exist on {base_commit}.\n"
    )

    for cycle in new_cycles.values():
        edge_count = sum(len(dependencies) for dependencies in cycle.values())
        print(f"Cycle - {len(cycle)} DAGs now depend on each other:")
        for dag in cycle:
            print(f"  {dag}")
        print(
            "\n  The generator breaks a cycle by DELETING EVERY EDGE inside it. These "
            f"{edge_count} ordering edges would be silently dropped from dependencies.yaml:"
        )
        for dag, dependencies in cycle.items():
            print(f"    {dag}")
            for dependency in dependencies:
                print(f"      -> {dependency}")
        print("")

    if changed_files:
        print("Files changed by this change that belong to the DAGs above:")
        for changed_file in changed_files:
            print(f"  {changed_file}")
        print("")

    print(
        "How to fix:\n"
        "  Find the backwards read - a query in one of the DAGs above that reads a table\n"
        "  produced downstream of its own DAG - and read the upstream source instead.\n"
        "\n"
        "  There is no exception list for this. A cycle means the DAGs cannot be ordered,\n"
        "  so the generator throws the ordering away - and it throws away ALL of it, not\n"
        "  just the dependency you added. On 2026-07-30 that cost dw_growth.obt_supply a\n"
        "  full day of leads and prospects."
    )
    print(SEPARATOR)


def find_changed_files_of_dags(
    dags: FrozenSet[str], from_branch: str, to_branch: str
) -> List[str]:
    """
    Lists the files changed between the two branches that belong to any of the given DAGs. Used to
    enrich the report, never to decide whether the validation passes.

    :param dags: The DAG ids to look for. e.g. {"bietlejuice.enrich_supply_leads"}
    :type dags: FrozenSet[str]
    :param from_branch: The branch used as the comparison base. e.g. origin/master
    :type from_branch: str
    :param to_branch: The branch being compared. e.g. HEAD
    :type to_branch: str
    :return: The sorted paths of the new or modified files belonging to the given DAGs
    :rtype: List[str]
    """
    try:
        modified_files = GitService().get_modified_files_from_diff(
            from_branch, to_branch
        )
    except (subprocess.SubprocessError, OSError, ValueError):
        return []

    dag_folders = {f"/{dag.split('.')[-1]}/" for dag in dags}
    return sorted(
        path
        for path, status in modified_files.items()
        if status in GitService.UPSERT_STATUS_CODES
        and path.startswith("dags/")
        and any(dag_folder in f"/{path}" for dag_folder in dag_folders)
    )


def _repository_root() -> str:
    return _run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()


def _run(
    command: List[str],
    cwd: Optional[str] = None,
    env: Optional[dict] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        command, cwd=cwd, env=env, check=check, capture_output=True, text=True
    )


def _serialize_cycles(cycles: CyclesByDags) -> List[Cycle]:
    return list(cycles.values())


def _deserialize_cycles(payload: List[Cycle]) -> CyclesByDags:
    return {frozenset(cycle): cycle for cycle in payload}


def _dump_cycles(cycles_path: str) -> None:
    """
    Writes the cycles of the current working tree to a file, for the parent process to read.

    Only ever called on the base-branch worktree. Reading the wrong `dags/` tree here would compare the
    working tree against itself and report no new cycles, so that is checked rather than assumed.
    """
    from dags import DAG_PACKAGES_ROOT

    expected_dags_root = os.path.realpath(os.path.join(os.getcwd(), "dags"))
    if os.path.realpath(DAG_PACKAGES_ROOT) != expected_dags_root:
        raise RuntimeError(
            f"expected to read the DAGs from {expected_dags_root}, "
            f"but they resolved to {DAG_PACKAGES_ROOT}"
        )

    with open(cycles_path, mode="w") as cycles_file:
        json.dump(_serialize_cycles(find_cycles()), cycles_file)


def _parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fails when a change introduces a cyclic dependency between DAGs."
    )
    parser.add_argument(
        "--from-branch",
        default=resolve_diff_from_ref(os.environ.get("CI_COMMIT_BRANCH", "")),
        help="Branch used as the comparison base (defaults to the CI target)",
    )
    parser.add_argument(
        "--to-branch",
        default=DEFAULT_TO_BRANCH,
        help=f"Branch being compared (default: {DEFAULT_TO_BRANCH})",
    )
    parser.add_argument(
        "--dump-cycles",
        help=argparse.SUPPRESS,  # internal: used on the base-branch worktree
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = _parse_args(argv)

    if args.dump_cycles:
        _dump_cycles(args.dump_cycles)
        return 0
    fetch_diff_base(args.from_branch)

    base_commit = resolve_base_commit(args.from_branch, args.to_branch)

    print("Looking for cycles in the DAG dependency graph...")
    cycles = find_cycles()
    print(f"Looking for cycles already present on {base_commit}...")
    base_commit_cycles = find_cycles_in_commit(base_commit)
    if base_commit_cycles is None:
        return 0

    new_cycles = find_new_cycles(cycles, base_commit_cycles)
    if not new_cycles:
        print(
            "No new cyclic DAG dependencies were introduced by this change "
            f"({len(base_commit_cycles)} pre-existing cycles on {base_commit} left untouched)."
        )
        return 0

    changed_files = find_changed_files_of_dags(
        frozenset().union(*new_cycles.keys()), args.from_branch, args.to_branch
    )
    print_report(new_cycles, changed_files, base_commit)
    return 1


if __name__ == "__main__":
    exit(main())
