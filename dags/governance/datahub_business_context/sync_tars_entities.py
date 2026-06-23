#!/usr/bin/env python3
"""Sync published TARS entity Context Documents from DataHub into Data Products.

Discovery:
    Search DataHub for Context Documents tagged ``tars-entity``, parse markdown
    content + structured properties, generate ``*.datahub.yaml`` + companion ``.md``.

Delivery modes:
    direct (default, Option B):
        Call ``load_collections_context.py`` directly and backlink the Data Product
        to the source Context Document.

    gitops (Option A):
        Open a GitHub PR with generated MD for engineering review.
        Woodpecker CI pushes to DataHub after merge.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<editor-token>

    # Default — direct push + backlink:
    python dags/governance/datahub_business_context/sync_tars_entities.py

    # GitOps PR (also requires GITHUB_TOKEN with repo write access):
    python dags/governance/datahub_business_context/sync_tars_entities.py --mode gitops

    # Dry-run (parse + generate locally, no delivery):
    python dags/governance/datahub_business_context/sync_tars_entities.py --dry-run

    # Sync a single document by URN:
    python dags/governance/datahub_business_context/sync_tars_entities.py --urn urn:li:document:...

Exit codes: 0 = all documents processed; 1 = at least one failure.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import tempfile
import unicodedata
import uuid
from pathlib import Path

# Ensure sync package is importable when run from repo root
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from sync.constants import (  # noqa: E402
    DATA_PRODUCT_TYPE_METRIC,
    DELIVERY_MODE_DIRECT,
    DELIVERY_MODE_GITOPS,
    LIFECYCLE_STAGE_DRAFT,
    LIFECYCLE_STAGE_PROD,
    MD_OUTPUT_DIR,
    MD_OUTPUT_DIR_METRICS,
    SYNC_STATE_FILENAME,
)
from sync.datahub_document_client import (  # noqa: E402
    TarsEntityDocument,
    fetch_document,
    search_tars_entity_documents,
    write_golden_query_urn,
)
from sync.direct_delivery import deliver_direct  # noqa: E402
from sync.document_parser import (  # noqa: E402
    parse_entity_markdown,
    validate_parsed_document,
)
from sync.github_delivery import open_sync_pull_request  # noqa: E402
from sync.sync_state import SyncStateStore  # noqa: E402
from sync.yaml_generator import (  # noqa: E402
    build_datahub_yaml,
    build_markdown_file,
    render_yaml,
)


def _content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _title_to_slug(title: str) -> str:
    """Convert a document title to a kebab-case data_product_id slug."""
    normalized = unicodedata.normalize("NFD", title)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    lower = ascii_only.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", lower).strip("-")
    return slug


def _is_safe_data_product_id(value: str) -> bool:
    if not value or value != value.strip():
        return False
    if ".." in value or "/" in value or "\\" in value:
        return False
    return all(ch.isalnum() or ch in "-_" for ch in value)


def _validate_document(doc: TarsEntityDocument) -> list[str]:
    """Only hard-gate on things the system cannot derive automatically."""
    errors: list[str] = []
    if not doc.content.strip():
        errors.append("Document has no content")
    if not doc.domain_urn:
        errors.append(
            "Document has no Domain assigned — set a Domain in the DataHub UI"
        )
    if not doc.title.strip():
        errors.append("Document has no title")
    if doc.data_product_id and not _is_safe_data_product_id(doc.data_product_id):
        errors.append(
            "Invalid data_product_id: must be alphanumeric (hyphens/underscores allowed)"
        )
    return errors


def _fill_derived_fields(
    doc: TarsEntityDocument, *, dry_run: bool
) -> TarsEntityDocument:
    """Derive any missing technical fields so the user only needs to write content."""
    # data_product_id: derive from title slug if not set via structured property
    if not doc.data_product_id:
        doc = TarsEntityDocument(
            **{**doc.__dict__, "data_product_id": _title_to_slug(doc.title)}
        )
        print(f"  → data_product_id derived from title: {doc.data_product_id}")
    else:
        print(f"  → data_product_id is: {doc.data_product_id}")

    # golden_query_stable_urn: auto-generate and write back so future syncs reuse it
    if not doc.golden_query_stable_urn:
        stable_urn = f"urn:li:query:{uuid.uuid4()}"
        doc = TarsEntityDocument(
            **{**doc.__dict__, "golden_query_stable_urn": stable_urn}
        )
        print(f"  → golden_query_stable_urn generated: {stable_urn}")
        if not dry_run:
            ok = write_golden_query_urn(doc.urn, stable_urn)
            if ok:
                print(
                    "  → stable URN written back to document (will reuse on future syncs)"
                )
            else:
                print(
                    "  ⚠ could not write stable URN back to document", file=sys.stderr
                )

    return doc


def _md_output_dir(data_product_type: str) -> str:
    return (
        MD_OUTPUT_DIR_METRICS
        if data_product_type == DATA_PRODUCT_TYPE_METRIC
        else MD_OUTPUT_DIR
    )


_OUTCOME_OK = "ok"
_OUTCOME_SKIPPED = "skipped"
_OUTCOME_FAILED = "failed"


def _process_document(
    doc: TarsEntityDocument,
    *,
    mode: str,
    dry_run: bool,
    force: bool,
    state: SyncStateStore,
    output_dir: Path,
    seen_slugs: set[str],
) -> str:
    label = doc.title or doc.urn

    meta_errors = _validate_document(doc)
    if meta_errors:
        print(f"\n✗  {label}  ({doc.urn})", file=sys.stderr)
        for err in meta_errors:
            print(f"  ✗ {err}", file=sys.stderr)
        return _OUTCOME_FAILED

    if not doc.is_published:
        print(
            f"\n⏭  {label}  ({doc.urn}) — status is Draft, publish in DataHub to sync"
        )
        return _OUTCOME_SKIPPED

    content_hash = _content_hash(doc.content)
    if not force and state.is_unchanged(doc.urn, content_hash):
        print(f"\n⏭  {label}  ({doc.urn}) — unchanged since last sync")
        return _OUTCOME_OK

    parsed = parse_entity_markdown(doc.content, fallback_title=doc.title)
    parse_errors = validate_parsed_document(parsed)
    if parse_errors:
        print(f"\n⏭  {label}  ({doc.urn})")
        print("  → document is still being authored — skipping until complete:")
        for err in parse_errors:
            print(f"    • {err}")
        print("  → Fix the sections above in DataHub, then re-run to sync.")
        return _OUTCOME_SKIPPED

    # All pre-checks passed — this doc will produce output
    print(f"\n▶  {label}  ({doc.urn})")
    print(f"  → data_product_type: {doc.data_product_type}")

    doc = _fill_derived_fields(doc, dry_run=dry_run)

    if not doc.data_product_id:
        print(
            f"  ✗ data_product_id cannot be derived: title {doc.title!r} contains no "
            "ASCII letters or digits — set data_product_id via structured property in DataHub",
            file=sys.stderr,
        )
        return _OUTCOME_FAILED
    if not _is_safe_data_product_id(doc.data_product_id):
        print(f"  ✗ invalid data_product_id: {doc.data_product_id!r}", file=sys.stderr)
        return _OUTCOME_FAILED

    product_id = doc.data_product_id.strip().lower().replace("_", "-")

    if product_id in seen_slugs:
        print(
            f"  ✗ slug collision: data_product_id {product_id!r} is already claimed by "
            "another document in this run — set a unique data_product_id via structured "
            "property in DataHub to resolve the conflict",
            file=sys.stderr,
        )
        return _OUTCOME_FAILED
    seen_slugs.add(product_id)
    dp_urn = f"urn:li:dataProduct:{product_id}"
    md_text = build_markdown_file(parsed, data_product_urn=dp_urn)

    entity_slug = doc.data_product_id.replace("-", "_")
    md_path = output_dir / f"{entity_slug}.md"

    if dry_run:
        md_path.write_text(md_text, encoding="utf-8")
        print(f"  ✓ dry-run wrote {md_path}")
        return _OUTCOME_OK

    if mode == DELIVERY_MODE_GITOPS:
        if not os.environ.get("GITHUB_TOKEN", "").strip():
            print("  ✗ GITHUB_TOKEN required for gitops mode", file=sys.stderr)
            return _OUTCOME_FAILED
        pr = open_sync_pull_request(
            data_product_id=doc.data_product_id,
            md_content=md_text,
            document_title=doc.title,
            document_urn=doc.urn,
            md_output_dir=_md_output_dir(doc.data_product_type),
        )
        print(f"  ✓ opened PR #{pr.pr_number}: {pr.pr_url}")
        state.mark_synced(
            doc.urn,
            content_hash,
            data_product_id=doc.data_product_id,
            delivery_mode=DELIVERY_MODE_GITOPS,
            pr_url=pr.pr_url,
        )
        return _OUTCOME_OK

    if mode == DELIVERY_MODE_DIRECT:
        lifecycle = LIFECYCLE_STAGE_PROD if doc.is_published else LIFECYCLE_STAGE_DRAFT
        spec = build_datahub_yaml(
            parsed,
            data_product_id=doc.data_product_id,
            domain_urn=doc.domain_urn,
            lifecycle_stage=lifecycle,
            golden_query_stable_urn=doc.golden_query_stable_urn,
            glossary_parent_node_urn=doc.glossary_parent_node_urn or None,
            primary_datasets=doc.primary_datasets or None,
            source_document_urn=doc.urn,
            data_product_type=doc.data_product_type,
        )
        yaml_text = render_yaml(spec)
        with tempfile.TemporaryDirectory(prefix="tars-sync-") as tmp:
            tmp_yaml = Path(tmp) / f"{doc.data_product_id}.datahub.yaml"
            tmp_yaml.write_text(yaml_text, encoding="utf-8")
            result = deliver_direct(
                tmp_yaml,
                document_urn=doc.urn,
                data_product_id=product_id,
            )
        if result.loader_exit_code != 0:
            print(
                f"  ✗ loader failed (exit {result.loader_exit_code})",
                file=sys.stderr,
            )
            return _OUTCOME_FAILED
        if result.backlink_ok:
            print(f"  ✓ pushed {result.data_product_urn} and backlinked document")
            state.mark_synced(
                doc.urn,
                content_hash,
                data_product_id=product_id,
                delivery_mode=DELIVERY_MODE_DIRECT,
            )
            return _OUTCOME_OK
        print(
            f"  ⚠ pushed {result.data_product_urn} but backlink failed",
            file=sys.stderr,
        )
        return _OUTCOME_FAILED

    print(f"  ✗ unknown mode: {mode}", file=sys.stderr)
    return _OUTCOME_FAILED


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync TARS entity Context Documents from DataHub to Data Products.",
    )
    parser.add_argument(
        "--mode",
        choices=[DELIVERY_MODE_GITOPS, DELIVERY_MODE_DIRECT],
        default=os.environ.get("TARS_SYNC_MODE", DELIVERY_MODE_DIRECT),
        help="Delivery mode: gitops (PR) or direct (GraphQL push + backlink).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and write files locally without delivery.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-sync even if document content hash is unchanged.",
    )
    parser.add_argument(
        "--urn",
        help="Sync a single document by URN instead of searching all tars-entity docs.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=_SCRIPT_DIR / "sync_output",
        help="Output directory for --dry-run (default: sync_output/).",
    )
    ns = parser.parse_args()

    if not os.environ.get("DATAHUB_GRAPHQL_URL", "").strip():
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1

    _state_path_env = os.environ.get("TARS_SYNC_STATE_PATH", "").strip()
    if _state_path_env:
        state_path = Path(_state_path_env)
    elif "DATABRICKS_RUNTIME_VERSION" in os.environ:
        state_path = Path("/dbfs/tmp/governance") / SYNC_STATE_FILENAME
    else:
        state_path = _SCRIPT_DIR / SYNC_STATE_FILENAME
    state = SyncStateStore(state_path)

    if ns.urn:
        doc = fetch_document(ns.urn)
        documents = [doc] if doc else []
    else:
        documents = search_tars_entity_documents()

    if not documents:
        print("No tars-entity documents found.")
        return 0

    print(f"Mode: {ns.mode} | Documents: {len(documents)} | dry_run={ns.dry_run}")

    passed = 0
    skipped = 0
    failed = 0
    seen_slugs: set[str] = set()
    for doc in documents:
        outcome = _process_document(
            doc,
            mode=ns.mode,
            dry_run=ns.dry_run,
            force=ns.force,
            state=state,
            output_dir=ns.output_dir,
            seen_slugs=seen_slugs,
        )
        if outcome == _OUTCOME_OK:
            passed += 1
        elif outcome == _OUTCOME_SKIPPED:
            skipped += 1
        else:
            failed += 1

    total = len(documents)
    print(
        f"\nResults: {passed} ok / {skipped} skipped / {failed} failed / {total} total"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
