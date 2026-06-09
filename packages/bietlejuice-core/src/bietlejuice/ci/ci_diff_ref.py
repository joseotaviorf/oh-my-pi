"""Resolve git diff base refs for Woodpecker CI validation scripts."""

from __future__ import annotations

import os

_WOODPECKER_PULL_REQUEST = "pull_request"
_LONG_LIVED_BRANCHES = frozenset({"master", "forno"})


def is_woodpecker_pull_request() -> bool:
    """True when Woodpecker is running a pull_request pipeline."""
    return os.environ.get("CI_PIPELINE_EVENT", "").strip() == _WOODPECKER_PULL_REQUEST


def resolve_diff_from_ref(branch_name: str) -> str:
    """Return the git ref used as the diff base (``from_ref`` in ``from_ref...HEAD``).

    Woodpecker sets ``CI_COMMIT_BRANCH`` to the PR *target* branch (often ``master``)
    on ``pull_request`` events. Those builds must diff against ``origin/master`` so the
    full PR is validated, not only the last commit (``HEAD~1``).

    Push pipelines on long-lived branches keep ``HEAD~1`` to scope checks to the
    commit being pushed.
    """
    if is_woodpecker_pull_request():
        return "origin/master"
    if branch_name in _LONG_LIVED_BRANCHES or branch_name.startswith("hotfix/"):
        return "HEAD~1"
    return "origin/master"
