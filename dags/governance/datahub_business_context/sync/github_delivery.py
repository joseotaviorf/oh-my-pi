"""GitOps delivery: open a GitHub PR with the generated MD file (Option A)."""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional

from sync.constants import (
    GITHUB_DEFAULT_BRANCH,
    GITHUB_REPO,
    MD_OUTPUT_DIR,
)


@dataclass
class PullRequestResult:
    pr_url: str
    branch: str
    pr_number: int
    updated: bool = True


def _github_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise RuntimeError(
            "GITHUB_TOKEN is not set (required for gitops delivery mode)"
        )
    return token


def _api_request(
    method: str,
    path: str,
    body: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    token = _github_token()
    url = f"https://api.github.com/repos/{GITHUB_REPO}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"GitHub API {method} {path} failed ({exc.code}): {detail}"
        ) from exc


def _get_ref_sha(branch: str = GITHUB_DEFAULT_BRANCH) -> str:
    ref = _api_request("GET", f"/git/ref/heads/{branch}")
    return str(ref["object"]["sha"])


def is_ip_allowlist_error(exc: Exception) -> bool:
    return "IP allow list" in str(exc) or (
        "403" in str(exc) and "ip" in str(exc).lower()
    )


def _get_file_sha(path: str, branch: str = GITHUB_DEFAULT_BRANCH) -> Optional[str]:
    try:
        blob = _api_request("GET", f"/contents/{path}?ref={branch}")
        return str(blob.get("sha"))
    except RuntimeError as exc:
        if "404" in str(exc):
            return None
        raise


def _get_file_content(path: str, branch: str) -> Optional[str]:
    """Return the decoded text content of ``path`` on ``branch``, or None if absent."""
    try:
        blob = _api_request("GET", f"/contents/{path}?ref={branch}")
        encoded = blob.get("content", "")
        if not encoded:
            return None
        return base64.b64decode(encoded).decode("utf-8")
    except RuntimeError as exc:
        if "404" in str(exc):
            return None
        raise


def file_exists_on_master(path: str) -> bool:
    """Return True if ``path`` already exists on the default branch (master)."""
    return _get_file_sha(path, GITHUB_DEFAULT_BRANCH) is not None


def _find_open_pr(branch: str) -> Optional[dict[str, Any]]:
    """Return the first open PR whose head is `branch`, or None."""
    owner = GITHUB_REPO.split("/")[0]
    prs = _api_request("GET", f"/pulls?head={owner}:{branch}&state=open")
    if isinstance(prs, list) and prs:
        return prs[0]
    return None


def _create_branch(branch: str, base_sha: str) -> None:
    _api_request(
        "POST",
        "/git/refs",
        {"ref": f"refs/heads/{branch}", "sha": base_sha},
    )


def _put_file(
    path: str,
    content: str,
    message: str,
    branch: str,
    file_sha: Optional[str] = None,
) -> None:
    body: dict[str, Any] = {
        "message": message,
        "content": base64.b64encode(content.encode("utf-8")).decode("ascii"),
        "branch": branch,
    }
    if file_sha:
        body["sha"] = file_sha
    _api_request("PUT", f"/contents/{path}", body)


def _sync_scope(md_output_dir: str) -> str:
    """Return the conventional-commit scope for gitops PR titles."""
    _dir_suffix = md_output_dir.rsplit("/", 1)[-1]
    return "tars-metrics-sync" if "metric" in _dir_suffix else "tars-entity-sync"


def build_sync_pr_title(
    *,
    data_product_id: str,
    is_edit: bool,
    md_output_dir: str = MD_OUTPUT_DIR,
) -> str:
    """Build a Commitlint-safe PR title for TARS entity gitops sync.

    Uses only the kebab-case ``data_product_id`` in the subject so titles stay
    valid even when the DataHub document title contains colons or other punctuation
    (e.g. ``Metric Entity: Property Integrity``).
    """
    action = "update" if is_edit else "add"
    scope = _sync_scope(md_output_dir)
    slug = data_product_id.strip().lower().replace("_", "-")
    return f"docs({scope}): {action} {slug}"


def _update_pr_title(pr_number: int, title: str) -> None:
    _api_request("PATCH", f"/pulls/{pr_number}", {"title": title})


def open_sync_pull_request(
    *,
    data_product_id: str,
    md_content: str,
    document_title: str,
    document_urn: str,
    is_edit: bool = False,
    md_output_dir: str = MD_OUTPUT_DIR,
) -> PullRequestResult:
    """Create branch, commit MD file, and open (or update) a PR for engineering review.

    Only the Markdown file is committed. On merge Woodpecker's ``sync-tars-entities``
    step runs ``sync_tars_entities.py --mode direct``, which reads fresh state from
    DataHub, generates YAML in memory, and pushes the Data Product — no YAML in the
    repo is required.

    ``is_edit=True`` means a file already exists on master; the PR title uses
    ``update`` instead of ``add`` so reviewers know they're looking at a diff.

    ``md_output_dir`` controls both the committed file path and the branch name prefix;
    use ``MD_OUTPUT_DIR_METRICS`` for metric data products.

    Idempotent: if an open PR already exists on the sync branch, the MD file is updated
    in-place on that branch and the existing PR is returned.
    """
    entity_slug = data_product_id.replace("-", "_")
    md_path = f"{md_output_dir}/{entity_slug}.md"
    # Derive branch prefix from the last path component (business_entities → tars-entity-sync,
    # metric_entities → tars-metrics-sync) so branches stay namespaced by kind.
    _dir_suffix = md_output_dir.rsplit("/", 1)[-1]  # e.g. "business_entities"
    _branch_prefix = (
        "tars-metrics-sync" if "metric" in _dir_suffix else "tars-entity-sync"
    )
    branch = f"{_branch_prefix}/{data_product_id}"
    pr_title = build_sync_pr_title(
        data_product_id=data_product_id,
        is_edit=is_edit,
        md_output_dir=md_output_dir,
    )

    commit_msg = (
        f"feat(datahub): sync TARS entity '{document_title}' from Context Document"
    )
    update_msg = f"chore(datahub): update TARS entity '{document_title}' (re-sync)"

    # ── Check for an existing open PR on this branch first ────────────────────
    existing_pr = _find_open_pr(branch)

    if existing_pr:
        # PR is already open — update the MD file on the branch in-place only when
        # the content has actually changed. GitHub creates a real commit even for
        # identical content, so we guard with an explicit content comparison.
        current_content = _get_file_content(md_path, branch)
        if current_content == md_content:
            print(
                f"  ↩ open PR #{existing_pr['number']} already has identical content — skipping commit"
            )
            return PullRequestResult(
                pr_url=str(existing_pr["html_url"]),
                branch=branch,
                pr_number=int(existing_pr["number"]),
                updated=False,
            )
        # Must read SHA from the PR branch (not master) to avoid sha-mismatch errors.
        md_sha = _get_file_sha(md_path, branch)
        _put_file(md_path, md_content, update_msg, branch, md_sha)
        if existing_pr.get("title") != pr_title:
            _update_pr_title(int(existing_pr["number"]), pr_title)
        return PullRequestResult(
            pr_url=str(existing_pr["html_url"]),
            branch=branch,
            pr_number=int(existing_pr["number"]),
        )

    # ── No open PR — create branch, commit MD, and open a new PR ──────────────
    base_sha = _get_ref_sha()
    branch_already_existed = False
    try:
        _create_branch(branch, base_sha)
    except RuntimeError as exc:
        if "Reference already exists" not in str(exc) and "422" not in str(exc):
            raise
        branch_already_existed = True

    # When the branch was freshly cut from master both refs have the same file SHA.
    # When the branch already existed (e.g. a previously-merged/closed PR), the file
    # on the branch may have been updated after the last merge, so its SHA differs from
    # master — we must read it from the branch or GitHub returns 409 sha-mismatch.
    sha_ref = branch if branch_already_existed else GITHUB_DEFAULT_BRANCH
    md_sha = _get_file_sha(md_path, sha_ref)
    _put_file(md_path, md_content, commit_msg, branch, md_sha)

    pr_body = (
        f"## TARS entity self-service sync\n\n"
        f"Auto-generated from DataHub Context Document:\n\n"
        f"- **Document:** `{document_urn}`\n"
        f"- **Title:** {document_title}\n"
        f"- **Data Product ID:** `{data_product_id}`\n\n"
        f"### File\n\n"
        f"- `{md_path}`\n\n"
        f"### On merge\n\n"
        f"Woodpecker `sync-tars-entities` runs automatically and pushes the Data "
        f"Product to DataHub in memory (no YAML file needed in the repo).\n\n"
        f"### Review checklist\n\n"
        f"- [ ] Golden query SQL is valid Trino\n"
        f"- [ ] All `schema.table` pairs exist in DataHub\n"
        f"- [ ] Woodpecker `sync-tars-entities` passes after merge\n"
    )
    pr = _api_request(
        "POST",
        "/pulls",
        {
            "title": pr_title,
            "head": branch,
            "base": GITHUB_DEFAULT_BRANCH,
            "body": pr_body,
        },
    )
    return PullRequestResult(
        pr_url=str(pr.get("html_url", "")),
        branch=branch,
        pr_number=int(pr.get("number", 0)),
    )
