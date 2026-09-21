"""
Runs a make validation target for every domain that has changes in the current branch,
executing all domain validations in parallel.

Domain detection logic:
  - If ALL changed files are under dags/{known_domain}/  → validate only affected domains.
  - If ANY changed file is outside a known domain folder  → validate ALL domains (framework
    or shared-file change that may affect every domain).

Usage (via Makefile — preferred):
    make run-domain-validation MAKE_TARGET=validate-lineage-consistency
    make run-domain-validation MAKE_TARGET=validate-dag-declaration-files MAKE_EXTRA_ARGS="level=debug"
    make run-domain-validation MAKE_TARGET=validate-dags-dependencies

Direct invocation (rare; the Makefile target wraps this):
    uv run --project packages/bietlejuice-compiler python \\
        packages/bietlejuice-compiler/scripts/ci_cd/run_validation_by_domain.py \\
        --make-target validate-lineage-consistency \\
        --all-domains   # skip change detection, run every domain
"""

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from scripts.services.git_service import GitService

# Folders under dags/ that are not validation domains and must not be sharded.
# (get_dag_domain_names already skips "_"-prefixed entries such as __pycache__.)
_NON_DOMAIN_FOLDERS = frozenset({"dependency_exceptions"})

# Derived from the filesystem so new dags/<domain>/ folders are picked up
# automatically — no hardcoded list to drift out of sync (previously missed
# house_and_listing, journey_optimizer and publisher_xp).
ALL_DOMAINS: List[str] = sorted(
    d
    for d in DAGPackagesPathService.get_dag_domain_names()
    if d not in _NON_DOMAIN_FOLDERS
)

_DOMAIN_PREFIXES = {d: f"dags/{d}/" for d in ALL_DOMAINS}


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------


def _current_branch() -> str:
    branch = os.environ.get("CI_COMMIT_BRANCH", "").strip()
    if not branch:
        branch = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
    return branch


def _changed_files(branch: str) -> Optional[List[str]]:
    """Returns paths of files changed in *branch* vs its diff base, or None on error.

    Woodpecker pull_request pipelines diff the PR target branch (full PR diff).
    Push pipelines on long-lived branches (master, forno, hotfix/*) use HEAD~1..HEAD.
    Feature branches compare origin/master..HEAD.
    """
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)

    try:
        diff = git_service.get_modified_files_from_diff(from_ref, "HEAD")
        return list(diff.keys())
    except Exception as exc:
        print(f"[warn] Could not determine changed files ({exc}).", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# Domain detection
# ---------------------------------------------------------------------------


def domains_to_validate(branch: str) -> List[str]:
    """Returns the sorted list of domains that should be validated."""
    changed = _changed_files(branch)

    if changed is None:
        print("Could not determine changed files — validating all domains.", flush=True)
        return list(ALL_DOMAINS)

    affected: set = set()
    for path in changed:
        matched = next(
            (d for d, prefix in _DOMAIN_PREFIXES.items() if path.startswith(prefix)),
            None,
        )
        if matched:
            affected.add(matched)
        else:
            # File outside any known domain folder → framework/shared change
            print(
                f"Non-domain file changed ({path!r}) — validating all {len(ALL_DOMAINS)} domains.",
                flush=True,
            )
            return list(ALL_DOMAINS)

    return sorted(affected)


# ---------------------------------------------------------------------------
# Subprocess runner
# ---------------------------------------------------------------------------


def _run_domain(
    make_target: str, domain: str, extra_args: List[str]
) -> Tuple[str, int, str]:
    cmd = ["make", make_target, f"domain={domain}"] + extra_args
    result = subprocess.run(cmd, capture_output=True, text=True)
    return domain, result.returncode, result.stdout + result.stderr


def _separator(domain: str, ok: bool) -> str:
    icon = "✓" if ok else "✗"
    bar = "━" * max(0, 58 - len(domain))
    return f"━━━ {domain} {icon} {bar}"


def _failure_section(output: str) -> str:
    """Reprint the failure block already emitted by the domain validation."""
    marker = "Files that failed the validation:"
    if marker not in output:
        return ""

    section = output.split(marker, 1)[1]
    lines = [marker]
    for line in section.splitlines():
        stripped = line.strip()
        if stripped.startswith("make[") or stripped.startswith("Leaving directory"):
            break
        if stripped.startswith("From https://github.com"):
            break
        lines.append(line.rstrip())

    return "\n".join(lines).strip()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run a make validation target per changed domain in parallel."
    )
    parser.add_argument(
        "--make-target",
        required=True,
        help="Make target to invoke (e.g. validate-lineage-consistency)",
    )
    parser.add_argument(
        "--make-extra-args",
        default="",
        help="Extra space-separated make arguments (e.g. 'level=debug')",
    )
    parser.add_argument(
        "--all-domains",
        action="store_true",
        help="Skip change detection and run every domain",
    )
    args = parser.parse_args()

    extra_args = args.make_extra_args.split() if args.make_extra_args else []

    branch = _current_branch()

    if args.all_domains:
        domains = list(ALL_DOMAINS)
        print(f"--all-domains: validating all {len(domains)} domains.", flush=True)
    else:
        domains = domains_to_validate(branch)

    if not domains:
        print(
            f"No domain changes detected for [{args.make_target}] — skipping.",
            flush=True,
        )
        sys.exit(0)

    print(
        f"\nRunning [{args.make_target}] for {len(domains)} domain(s): "
        f"{', '.join(domains)}\n",
        flush=True,
    )

    ordered_results: List[Optional[Tuple[str, int, str]]] = [None] * len(domains)

    with ThreadPoolExecutor(max_workers=len(domains)) as executor:
        future_map = {
            executor.submit(_run_domain, args.make_target, d, extra_args): i
            for i, d in enumerate(domains)
        }
        for future in as_completed(future_map):
            ordered_results[future_map[future]] = future.result()

    failed: List[str] = []
    failed_details: List[Tuple[str, str]] = []
    for domain, rc, output in ordered_results:  # type: ignore[misc]
        ok = rc == 0
        print(_separator(domain, ok), flush=True)
        if output.strip():
            print(output, flush=True)
        if not ok:
            failed.append(domain)
            section = _failure_section(output)
            if section:
                failed_details.append((domain, section))

    print("=" * 62, flush=True)
    if failed:
        print(f"FAILED ({len(failed)}): {', '.join(failed)}", flush=True)
        if failed_details:
            print(flush=True)
            for domain, section in failed_details:
                print(f"[{domain}]", flush=True)
                print(section, flush=True)
        sys.exit(1)
    else:
        print(f"All {len(domains)} domain(s) passed ✓", flush=True)
        sys.exit(0)


if __name__ == "__main__":
    main()
