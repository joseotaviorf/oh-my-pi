"""Post the CI validation result back to the PR as a single, upserted comment.

The Luigi self-service submitter is non-technical and doesn't watch Woodpecker — so
when ``validate_datahub_context_entities`` fails on their PR, we surface the reason
*on the PR* as a comment. Zordon's review poller then reads that comment (matched by
``MARKER``) and relays it into the user's Google Chat thread, translated.

Idempotent: one comment per PR, PATCHed in place on each new push (never a new comment
per failure), so the thread stays clean and the poller relays on content change only.

Best-effort: any failure here is logged and swallowed — posting a comment must never
change the validator's exit code or block CI.
"""

from __future__ import annotations

import logging

from sync.github_delivery import _api_request

logger = logging.getLogger(__name__)

# Hidden HTML marker the poller (zordon) greps for to recognize this as the CI
# validation comment. Keep it in lockstep with zordon's poller._CI_COMMENT_MARKER.
MARKER = "<!-- luigi-ci-validation -->"


def _find_marker_comment(pr_number: int) -> dict | None:
    """This PR's existing CI-validation comment (the full dict), or None."""
    comments = _api_request("GET", f"/issues/{pr_number}/comments")
    if not isinstance(comments, list):
        return None
    for comment in comments:
        if MARKER in (comment.get("body") or ""):
            return comment
    return None


def _upsert(pr: int, full_body: str) -> bool:
    """Create-or-update the single marker comment, but skip the write when the body is
    already identical — so the comment's ``updated_at`` doesn't move and the poller
    doesn't re-relay unchanged content on every CI run."""
    existing = _find_marker_comment(pr)
    if existing is not None:
        if (existing.get("body") or "").strip() == full_body.strip():
            return True  # unchanged — leave updated_at (and the relay) untouched
        _api_request("PATCH", f"/issues/comments/{existing['id']}", {"body": full_body})
    else:
        _api_request("POST", f"/issues/{pr}/comments", {"body": full_body})
    return True


def post_validation_failure(pr_number: str | int, body: str) -> bool:
    """Upsert the CI-validation comment with the failure ``body`` (marker prepended).
    Best-effort: False on a bad PR number or any API error, never raises."""
    if not str(pr_number).strip().isdigit():
        return False
    try:
        return _upsert(int(pr_number), f"{MARKER}\n{body}")
    except Exception:
        logger.exception(
            "Luigi CI: failed to post failure comment on PR #%s", pr_number
        )
        return False


_SUCCESS_BODY = (
    "✅ **Automated review passed** — your Data Product documentation is valid. "
    "It's now waiting for a **manual review by the responsible Data Engineer** before "
    "it's published. I'll let you know when that's done."
)


def post_validation_success(pr_number: str | int) -> bool:
    """Upsert the CI-validation comment to the success message — posted on **every** pass
    (including a clean first open), so the submitter always knows the automated review is
    green and only the manual review remains. Idempotent (see ``_upsert``); best-effort."""
    if not str(pr_number).strip().isdigit():
        return False
    try:
        return _upsert(int(pr_number), f"{MARKER}\n{_SUCCESS_BODY}")
    except Exception:
        logger.exception(
            "Luigi CI: failed to post success comment on PR #%s", pr_number
        )
        return False
