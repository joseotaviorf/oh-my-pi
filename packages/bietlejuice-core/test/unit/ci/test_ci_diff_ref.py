import pytest

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref


@pytest.mark.parametrize(
    ("branch_name", "pipeline_event", "expected"),
    [
        ("master", "pull_request", "origin/master"),
        ("master", "push", "HEAD~1"),
        ("forno", "push", "HEAD~1"),
        ("hotfix/foo", "push", "HEAD~1"),
        ("feature/foo", "pull_request", "origin/master"),
        ("feature/foo", "push", "origin/master"),
        ("master", "", "HEAD~1"),
    ],
)
def test_resolve_diff_from_ref(
    branch_name: str,
    pipeline_event: str,
    expected: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CI_PIPELINE_EVENT", pipeline_event)
    assert resolve_diff_from_ref(branch_name) == expected
