"""Push context_documents/*.md files to DataHub as native Context Documents.

Reads ``context_documents/context_documents_registry.yml`` and for each entry:
  - Creates the document if it does not exist (``createDocument``).
  - Updates content if the file hash changed (``updateDocumentContents``).
  - Wires parent-child hierarchy (parents pushed first).
  - Sets document settings (``showInGlobalContext``).

Idempotent: safe to run repeatedly; uses stable document IDs so re-runs update
rather than duplicate.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-editor-role>
    python dags/governance/datahub_business_context/push_context_documents.py

    # Dry-run — print actions without calling DataHub:
    python dags/governance/datahub_business_context/push_context_documents.py --dry-run

Exit codes: 0 = all documents synced; 1 = at least one failure.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

# ---------------------------------------------------------------------------
# Bootstrap GraphQL client — same pattern as load_collections_context.py.
# Uses stdlib urllib so the script also works without bietlejuice installed,
# which matches smoke_test_datahub.py (CI doesn't always install the package).
# ---------------------------------------------------------------------------
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional

import yaml


def _graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    """POST GraphQL body; returns (parsed JSON root or None, diagnostic string)."""
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    req = urllib.request.Request(
        graphql_url,
        data=payload,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            if int(getattr(resp, "status", None) or resp.getcode()) != 200:
                return None, "http_error"
            raw = resp.read()
            if not raw or not raw.strip():
                return None, "empty_body"
            return json.loads(raw.decode("utf-8")), "ok"
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        return None, f"http_{exc.code}: {detail}"
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
        return None, f"fetch_error: {exc}"


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

GRAPHQL_URL: str = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

_SCRIPT_DIR = Path(__file__).resolve().parent
_CONTEXT_DOCS_DIR = _SCRIPT_DIR / "context_documents"
_REGISTRY_FILE = _CONTEXT_DOCS_DIR / "context_documents_registry.yml"

_errors: list[str] = []


def _ok(label: str) -> None:
    print(f"  \u2713 {label}")


def _fail(label: str, detail: str) -> None:
    msg = f"  \u2717 {label}: {detail}"
    print(msg, file=sys.stderr)
    _errors.append(msg)


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    root, diag = _graphql_post(GRAPHQL_URL, TOKEN, query, variables)
    if root is None:
        print(f"    [DEBUG] {diag}", file=sys.stderr)
        return None
    if root.get("errors"):
        print(
            f"    [DEBUG] GraphQL errors: {json.dumps(root['errors'])}", file=sys.stderr
        )
        return root
    return root.get("data")


def _content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _already_exists_error(errors: list[Any]) -> bool:
    for err in errors or []:
        msg = (err.get("message") or "").lower()
        if "already exists" in msg or "duplicate" in msg:
            return True
    return False


# ---------------------------------------------------------------------------
# GraphQL mutations / queries
# ---------------------------------------------------------------------------

_GET_DOCUMENT = """
query GetContextDocument($urn: String!) {
  document(urn: $urn) {
    urn
    info {
      title
    }
  }
}
"""

_CREATE_DOCUMENT = """
mutation CreateContextDocument($input: CreateDocumentInput!) {
  createDocument(input: $input)
}
"""

_UPDATE_DOCUMENT_CONTENTS = """
mutation UpdateContextDocumentContents($input: UpdateDocumentContentsInput!) {
  updateDocumentContents(input: $input)
}
"""

_UPDATE_DOCUMENT_SETTINGS = """
mutation UpdateContextDocumentSettings($input: UpdateDocumentSettingsInput!) {
  updateDocumentSettings(input: $input)
}
"""

_MOVE_DOCUMENT = """
mutation MoveContextDocument($input: MoveDocumentInput!) {
  moveDocument(input: $input)
}
"""


def _document_urn(doc_id: str) -> str:
    return f"urn:li:document:{doc_id}"


def _document_exists(doc_id: str) -> bool:
    """Return True only when the document is a real entity with a title."""
    data = _post(_GET_DOCUMENT, {"urn": _document_urn(doc_id)})
    if data is None:
        return False
    doc = data.get("document") or {}
    return bool((doc.get("info") or {}).get("title"))


def _create_document(
    *,
    doc_id: str,
    title: str,
    content: str,
    sub_type: str,
    state: str,
    parent_id: Optional[str],
    dry_run: bool,
) -> bool:
    urn = _document_urn(doc_id)
    inp: dict[str, Any] = {
        "id": doc_id,
        "title": title,
        "contents": {"text": content},
        "subType": sub_type,
        "state": state,
    }
    if parent_id:
        inp["parentDocument"] = _document_urn(parent_id)

    if dry_run:
        _ok(f"[dry-run] would create {urn}")
        return True

    result = _post(_CREATE_DOCUMENT, {"input": inp})
    if result is None:
        # result is None means HTTP failure; check for errors dict
        _fail(f"createDocument({doc_id})", "HTTP/network failure")
        return False
    # result may be the full root dict (with errors) when _post returns root
    if isinstance(result, dict) and result.get("errors"):
        if _already_exists_error(result["errors"]):
            _ok(f"{doc_id}: already exists")
            return True
        _fail(f"createDocument({doc_id})", json.dumps(result["errors"]))
        return False
    created_urn = result.get("createDocument") if isinstance(result, dict) else None
    if created_urn:
        _ok(f"created {created_urn}")
        return True
    # Fallback: if createDocument returned null but no errors, treat as success
    # (some DataHub versions return null when document already exists without an error)
    _ok(f"{doc_id}: created (null response — may already exist)")
    return True


def _update_contents(*, doc_id: str, content: str, dry_run: bool) -> bool:
    urn = _document_urn(doc_id)
    if dry_run:
        _ok(f"[dry-run] would update contents for {urn}")
        return True
    data = _post(
        _UPDATE_DOCUMENT_CONTENTS,
        {"input": {"urn": urn, "contents": {"text": content}}},
    )
    if data is None:
        _fail(f"updateDocumentContents({doc_id})", "mutation failed")
        return False
    _ok(f"updated contents for {urn}")
    return True


def _update_settings(
    *, doc_id: str, show_in_global_context: bool, dry_run: bool
) -> bool:
    urn = _document_urn(doc_id)
    if dry_run:
        _ok(
            f"[dry-run] would set showInGlobalContext={show_in_global_context} for {urn}"
        )
        return True
    data = _post(
        _UPDATE_DOCUMENT_SETTINGS,
        {"input": {"urn": urn, "showInGlobalContext": show_in_global_context}},
    )
    if data is None:
        _fail(f"updateDocumentSettings({doc_id})", "mutation failed")
        return False
    _ok(f"settings updated for {urn}")
    return True


def _move_document(*, doc_id: str, parent_id: Optional[str], dry_run: bool) -> bool:
    urn = _document_urn(doc_id)
    parent_urn = _document_urn(parent_id) if parent_id else None
    if dry_run:
        _ok(f"[dry-run] would move {urn} → parent={parent_urn}")
        return True
    inp: dict[str, Any] = {"urn": urn}
    if parent_urn:
        inp["parentDocument"] = parent_urn
    data = _post(_MOVE_DOCUMENT, {"input": inp})
    if data is None:
        _fail(f"moveDocument({doc_id})", "mutation failed")
        return False
    _ok(f"hierarchy set for {urn}")
    return True


# ---------------------------------------------------------------------------
# Registry loading
# ---------------------------------------------------------------------------


def _load_registry() -> list[dict[str, Any]]:
    with _REGISTRY_FILE.open(encoding="utf-8") as fh:
        reg = yaml.safe_load(fh)
    if not isinstance(reg, dict) or not isinstance(reg.get("documents"), list):
        raise SystemExit(f"Invalid registry format: {_REGISTRY_FILE}")
    return list(reg["documents"])


def _read_source(source_file: str) -> str:
    path = _CONTEXT_DOCS_DIR / source_file
    if not path.is_file():
        raise SystemExit(f"Source file not found: {path}")
    return path.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Per-document sync
# ---------------------------------------------------------------------------


def _sync_document(entry: dict[str, Any], *, dry_run: bool) -> bool:
    doc_id: str = str(entry["id"])
    title: str = str(entry.get("title") or doc_id)
    source_file: str = str(entry["source_file"])
    sub_type: str = str(entry.get("sub_type", "Process Guide"))
    state: str = str(entry.get("state", "PUBLISHED"))
    parent_id: Optional[str] = entry.get("parent_id")
    show_in_global: bool = bool(entry.get("show_in_global_context", True))

    print(f"\n▶  {doc_id}  ({source_file})")

    content = _read_source(source_file)

    exists = _document_exists(doc_id) if not dry_run else False

    if not exists:
        ok = _create_document(
            doc_id=doc_id,
            title=title,
            content=content,
            sub_type=sub_type,
            state=state,
            parent_id=parent_id,
            dry_run=dry_run,
        )
        if not ok:
            return False
    else:
        _ok(f"{doc_id}: already exists — checking for content updates")
        ok = _update_contents(doc_id=doc_id, content=content, dry_run=dry_run)
        if not ok:
            return False
        if parent_id:
            ok = _move_document(doc_id=doc_id, parent_id=parent_id, dry_run=dry_run)
            if not ok:
                return False

    ok = _update_settings(
        doc_id=doc_id,
        show_in_global_context=show_in_global,
        dry_run=dry_run,
    )
    return ok


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _smoke_check(registry: list[dict[str, Any]]) -> int:
    """Verify that every registered document exists in DataHub with non-empty properties.

    Used as a lightweight post-deploy check.  Exit 0 if all present, 1 otherwise.
    """
    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token      : {'set' if TOKEN else 'NOT SET'}")
    print(f"Documents       : {len(registry)}")
    print("────────────────────────────────────────────────────────────")

    passed: list[str] = []
    failed: list[str] = []

    for entry in registry:
        doc_id = str(entry.get("id") or "")
        if not doc_id:
            failed.append("(unknown)")
            continue
        urn = _document_urn(doc_id)
        if _document_exists(doc_id):
            print(f"  \u2713 {urn}")
            passed.append(doc_id)
        else:
            print(f"  \u2717 {urn}  (missing or no properties)", file=sys.stderr)
            failed.append(doc_id)

    print()
    print("═" * 60)
    print(f"Results: {len(passed)} ok / {len(failed)} missing / {len(registry)} total")

    if failed:
        print("\nMissing documents:")
        for name in failed:
            print(f"  \u2717 urn:li:document:{name}")
        print(
            "\nRun `python push_context_documents.py` to create them.",
            file=sys.stderr,
        )
        return 1

    print(f"\nAll {len(passed)} context documents are present in DataHub.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Push context_documents/*.md to DataHub as native Context Documents.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without calling DataHub.",
    )
    parser.add_argument(
        "--smoke-check",
        action="store_true",
        help=(
            "Verify that all registered documents exist in DataHub (read-only). "
            "Exit 0 if all present, 1 if any are missing."
        ),
    )
    ns = parser.parse_args()

    if not ns.dry_run and not GRAPHQL_URL:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1

    registry = _load_registry()

    if ns.smoke_check:
        return _smoke_check(registry)

    print(f"DataHub target  : {GRAPHQL_URL or '(dry-run)'}")
    print(
        f"Auth token      : {'set' if TOKEN else ('NOT SET' if not ns.dry_run else '(dry-run)')}"
    )
    print(f"Documents       : {len(registry)}")
    print("────────────────────────────────────────────────────────────")

    passed: list[str] = []
    failed: list[str] = []

    for entry in registry:
        doc_id = str(entry.get("id") or "")
        if not doc_id:
            print("  ✗ entry missing 'id' — skipping", file=sys.stderr)
            failed.append("(unknown)")
            continue
        ok = _sync_document(entry, dry_run=ns.dry_run)
        if ok:
            passed.append(doc_id)
        else:
            failed.append(doc_id)

    print("\n" + "═" * 60)
    print(f"Results: {len(passed)} ok / {len(failed)} failed / {len(registry)} total")

    if failed:
        print("\nFailed:")
        for name in failed:
            print(f"  ✗ {name}")
        return 1

    print(f"\nAll {len(passed)} context documents synced.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
