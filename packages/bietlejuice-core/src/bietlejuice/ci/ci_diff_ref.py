"""Resolve git diff base refs for Woodpecker CI validation scripts."""

from __future__ import annotations

import os
import subprocess

_WOODPECKER_PULL_REQUEST = "pull_request"
_LONG_LIVED_BRANCHES = frozenset({"master", "forno", "development"})


def is_woodpecker_pull_request() -> bool:
    """True when Woodpecker is running a pull_request pipeline."""
    return os.environ.get("CI_PIPELINE_EVENT", "").strip() == _WOODPECKER_PULL_REQUEST


def resolve_diff_from_ref(branch_name: str) -> str:
    """Return the git ref used as the diff base (``from_ref`` in ``from_ref...HEAD``).

    Woodpecker sets ``CI_COMMIT_BRANCH`` to the PR *target* branch (often ``master``)
    on ``pull_request`` events. Those builds must diff against the target long-lived
    branch so the full PR is validated, not only the last commit (``HEAD~1``).

    Prefer ``CI_COMMIT_TARGET_BRANCH`` when set; fall back to ``branch_name`` (already
    the PR target in Woodpecker) so master/forno/development PRs each diff against
    their own base. Unknown targets keep ``origin/master``.

    Push pipelines on long-lived branches keep ``HEAD~1`` to scope checks to the
    commit being pushed.
    """
    if is_woodpecker_pull_request():
        target = os.environ.get("CI_COMMIT_TARGET_BRANCH", "").strip() or branch_name
        if target in _LONG_LIVED_BRANCHES:
            return f"origin/{target}"
        return "origin/master"
    if branch_name in _LONG_LIVED_BRANCHES or branch_name.startswith("hotfix/"):
        return "HEAD~1"
    return "origin/master"


def fetch_diff_base(from_ref: str) -> None:
    """Make ``from_ref`` resolvable in a CI clone that only has the PR branch.

    Woodpecker clones a single branch, so a PR targeting ``development`` or
    ``forno`` has no ``origin/<target>`` ref locally. Fetching a hardcoded
    branch instead of the one being diffed makes ``git diff <from_ref>...HEAD``
    fail, which every changed-file validator reads as "nothing changed".

    No-op for local refs such as ``HEAD~1``.
    """
    if not from_ref.startswith("origin/"):
        return
    remote_branch = from_ref.removeprefix("origin/")
    subprocess.run(
        [
            "git",
            "fetch",
            "--no-tags",
            "origin",
            f"+refs/heads/{remote_branch}:refs/remotes/origin/{remote_branch}",
        ],
        check=True,
        capture_output=True,
    )
