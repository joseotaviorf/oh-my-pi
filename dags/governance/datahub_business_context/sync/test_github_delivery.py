"""Unit tests for github_delivery — content-equality guard."""

from __future__ import annotations

import base64
from unittest.mock import MagicMock, patch

import pytest

from sync.github_delivery import (
    _get_file_content,
    open_sync_pull_request,
)

# ── helpers ────────────────────────────────────────────────────────────────────


def _b64(text: str) -> str:
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def _mock_api(responses: dict) -> MagicMock:
    """Return a side-effect function keyed on (method, path_prefix)."""

    def _side_effect(method, path, body=None):
        for (m, prefix), value in responses.items():
            if method == m and path.startswith(prefix):
                if isinstance(value, Exception):
                    raise value
                return value
        raise RuntimeError(f"Unexpected API call: {method} {path}")

    return MagicMock(side_effect=_side_effect)


# ── _get_file_content ──────────────────────────────────────────────────────────


class TestGetFileContent:
    def test_returns_decoded_content(self):
        text = "# Hello\n"
        with patch(
            "sync.github_delivery._api_request",
            return_value={"content": _b64(text)},
        ):
            assert _get_file_content("docs/foo.md", "my-branch") == text

    def test_returns_none_on_404(self):
        with patch(
            "sync.github_delivery._api_request",
            side_effect=RuntimeError("GitHub API GET /contents/foo.md failed (404)"),
        ):
            assert _get_file_content("docs/foo.md", "my-branch") is None

    def test_returns_none_when_content_key_missing(self):
        with patch("sync.github_delivery._api_request", return_value={}):
            assert _get_file_content("docs/foo.md", "my-branch") is None

    def test_raises_on_non_404_error(self):
        with patch(
            "sync.github_delivery._api_request",
            side_effect=RuntimeError("GitHub API GET /contents/foo.md failed (500)"),
        ):
            with pytest.raises(RuntimeError, match="500"):
                _get_file_content("docs/foo.md", "my-branch")


# ── open_sync_pull_request — existing open PR ─────────────────────────────────


class TestOpenSyncPullRequestExistingPR:
    _EXISTING_PR = {
        "html_url": "https://github.com/org/repo/pull/42",
        "number": 42,
    }

    def _run_with_patches(self, md_content: str, branch_content: str | None):
        """Patch module-level helpers and return (result, put_file_mock)."""
        put_file = MagicMock()
        with patch.multiple(
            "sync.github_delivery",
            _find_open_pr=MagicMock(return_value=self._EXISTING_PR),
            _get_file_content=MagicMock(return_value=branch_content),
            _get_file_sha=MagicMock(return_value="abc123"),
            _put_file=put_file,
        ):
            result = open_sync_pull_request(
                data_product_id="my-entity",
                md_content=md_content,
                document_title="My Entity",
                document_urn="urn:li:document:abc",
            )
        return result, put_file

    def test_skips_commit_when_content_unchanged(self):
        md = "# Entity\n\nSame content.\n"
        result, put_file = self._run_with_patches(md_content=md, branch_content=md)
        put_file.assert_not_called()
        assert result.updated is False
        assert result.pr_number == 42

    def test_commits_when_content_changed(self):
        old_md = "# Entity\n\nOld content.\n"
        new_md = "# Entity\n\nNew content.\n"
        result, put_file = self._run_with_patches(
            md_content=new_md, branch_content=old_md
        )
        put_file.assert_called_once()
        assert result.updated is True
        assert result.pr_number == 42

    def test_commits_when_branch_file_absent(self):
        new_md = "# Entity\n\nBrand new.\n"
        result, put_file = self._run_with_patches(
            md_content=new_md, branch_content=None
        )
        put_file.assert_called_once()
        assert result.updated is True


# ── open_sync_pull_request — new PR ───────────────────────────────────────────


class TestOpenSyncPullRequestNewPR:
    def test_creates_branch_and_pr(self):
        create_branch = MagicMock()
        put_file = MagicMock()
        with patch.multiple(
            "sync.github_delivery",
            _find_open_pr=MagicMock(return_value=None),
            _get_ref_sha=MagicMock(return_value="deadbeef"),
            _create_branch=create_branch,
            _get_file_sha=MagicMock(return_value=None),
            _put_file=put_file,
            _api_request=MagicMock(
                return_value={
                    "html_url": "https://github.com/org/repo/pull/1",
                    "number": 1,
                }
            ),
        ):
            result = open_sync_pull_request(
                data_product_id="new-entity",
                md_content="# New\n",
                document_title="New Entity",
                document_urn="urn:li:document:xyz",
            )
        create_branch.assert_called_once_with("tars-entity-sync/new-entity", "deadbeef")
        put_file.assert_called_once()
        assert result.updated is True
        assert result.pr_number == 1
