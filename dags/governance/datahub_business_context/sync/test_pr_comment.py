"""Tests for pr_comment — upserting the CI-validation comment on a PR."""

from __future__ import annotations

from unittest.mock import patch

from sync import pr_comment


def test_posts_a_new_comment_when_none_exists():
    with patch.object(pr_comment, "_api_request") as api:
        api.side_effect = [[], {}]  # GET comments (none), then POST
        ok = pr_comment.post_validation_failure("42", "boom")

    assert ok is True
    methods = [call.args[0] for call in api.call_args_list]
    assert methods == ["GET", "POST"]
    post_path, post_body = api.call_args_list[1].args[1], api.call_args_list[1].args[2]
    assert post_path == "/issues/42/comments"
    assert pr_comment.MARKER in post_body["body"]
    assert "boom" in post_body["body"]


def test_patches_the_existing_marker_comment():
    existing = [
        {"id": 7, "body": "unrelated human comment"},
        {"id": 9, "body": f"{pr_comment.MARKER}\nold errors"},
    ]
    with patch.object(pr_comment, "_api_request") as api:
        api.side_effect = [existing, {}]  # GET, then PATCH
        ok = pr_comment.post_validation_failure(42, "new errors")

    assert ok is True
    assert api.call_args_list[1].args[:2] == ("PATCH", "/issues/comments/9")
    assert "new errors" in api.call_args_list[1].args[2]["body"]


def test_non_numeric_pr_is_a_noop():
    with patch.object(pr_comment, "_api_request") as api:
        assert pr_comment.post_validation_failure("", "x") is False
        api.assert_not_called()


def test_api_error_is_swallowed_and_returns_false():
    with patch.object(pr_comment, "_api_request", side_effect=RuntimeError("403")):
        assert pr_comment.post_validation_failure("42", "x") is False


def test_success_patches_an_existing_failure_comment():
    existing = [{"id": 9, "body": f"{pr_comment.MARKER}\n❌ old errors"}]
    with patch.object(pr_comment, "_api_request") as api:
        api.side_effect = [existing, {}]  # GET, then PATCH
        ok = pr_comment.post_validation_success(42)

    assert ok is True
    assert api.call_args_list[1].args[:2] == ("PATCH", "/issues/comments/9")
    assert "passed" in api.call_args_list[1].args[2]["body"]


def test_success_creates_a_comment_on_a_clean_first_pass():
    # Posted on EVERY pass, including a clean open where no failure comment exists.
    with patch.object(pr_comment, "_api_request") as api:
        api.side_effect = [[], {}]  # GET (none), then POST
        ok = pr_comment.post_validation_success(42)

    assert ok is True
    assert api.call_args_list[1].args[:2] == ("POST", "/issues/42/comments")


def test_upsert_is_idempotent_when_body_unchanged():
    # An already-success comment must NOT be re-written (would bump updated_at and make
    # the poller re-relay the same message every CI run).
    same = [{"id": 9, "body": f"{pr_comment.MARKER}\n{pr_comment._SUCCESS_BODY}"}]
    with patch.object(pr_comment, "_api_request") as api:
        api.side_effect = [same]  # only GET — no PATCH/POST
        ok = pr_comment.post_validation_success(42)

    assert ok is True
    assert [c.args[0] for c in api.call_args_list] == ["GET"]
