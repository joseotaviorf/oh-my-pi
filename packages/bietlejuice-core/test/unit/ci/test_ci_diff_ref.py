from unittest import mock

import pytest

from bietlejuice.ci.ci_diff_ref import fetch_diff_base, resolve_diff_from_ref


@pytest.fixture(autouse=True)
def _isolate_woodpecker_target(monkeypatch: pytest.MonkeyPatch) -> None:
    # Woodpecker sets CI_COMMIT_TARGET_BRANCH to this PR's target. Tests that
    # simulate development/forno PRs must not inherit the host pipeline's value.
    monkeypatch.delenv("CI_COMMIT_TARGET_BRANCH", raising=False)


@pytest.mark.parametrize(
    ("branch_name", "pipeline_event", "target_branch", "expected"),
    [
        ("master", "pull_request", None, "origin/master"),
        ("development", "pull_request", None, "origin/development"),
        ("forno", "pull_request", None, "origin/forno"),
        ("feature/foo", "pull_request", "development", "origin/development"),
        ("master", "push", None, "HEAD~1"),
        ("forno", "push", None, "HEAD~1"),
        ("hotfix/foo", "push", None, "HEAD~1"),
        ("feature/foo", "pull_request", None, "origin/master"),
        ("feature/foo", "push", None, "origin/master"),
        ("master", "", None, "HEAD~1"),
    ],
)
def test_resolve_diff_from_ref(
    branch_name: str,
    pipeline_event: str,
    target_branch: str | None,
    expected: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CI_PIPELINE_EVENT", pipeline_event)
    if target_branch is not None:
        monkeypatch.setenv("CI_COMMIT_TARGET_BRANCH", target_branch)
    assert resolve_diff_from_ref(branch_name) == expected


@mock.patch("bietlejuice.ci.ci_diff_ref.subprocess.run")
def test_fetch_diff_base_fetches_the_ref_being_diffed(
    mock_run: mock.MagicMock,
) -> None:
    # Act
    fetch_diff_base("origin/development")
    # Assert — Woodpecker clones one branch, so the diff base must be fetched by
    # name or git diff fails and callers read the empty output as "no changes".
    mock_run.assert_called_once_with(
        [
            "git",
            "fetch",
            "--no-tags",
            "origin",
            "+refs/heads/development:refs/remotes/origin/development",
        ],
        check=True,
        capture_output=True,
    )


@mock.patch("bietlejuice.ci.ci_diff_ref.subprocess.run")
def test_fetch_diff_base_skips_local_refs(mock_run: mock.MagicMock) -> None:
    # Act — push pipelines diff HEAD~1, which needs no fetch
    fetch_diff_base("HEAD~1")
    # Assert
    mock_run.assert_not_called()
