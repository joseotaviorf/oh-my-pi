"""
airflow parsing enforcement

Note: this line above forces Airflow to parse this file for implemented DAGs
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import pendulum
from airflow import DAG
from airflow.models import Variable
from airflow.models.param import Param
from airflow.operators.python import PythonOperator

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

# sync_tars_entities.py lives two levels up in governance/datahub_business_context/
_SYNC_SCRIPT = (
    Path(__file__).resolve().parents[1]  # → dags/governance/
    / "datahub_business_context"
    / "sync_tars_entities.py"
)

# sync/ package — needed for write_sync_status in open_pr task
_SYNC_PKG_DIR = _SYNC_SCRIPT.parent


# ── stdout / stderr formatting helpers ────────────────────────────────────────

def _print_output(stdout: str, stderr: str) -> None:
    """Print script output with the same structured blocks used previously."""
    if stdout:
        stdout_lines = stdout.splitlines()
        audit_lines = [l for l in stdout_lines if l.startswith("AUDIT:")]
        other_lines = [l for l in stdout_lines if not l.startswith("AUDIT:")]

        if other_lines:
            print("\n" + "─" * 60)
            print("SCRIPT OUTPUT")
            print("─" * 60)
            for line in other_lines:
                print(line)

        if audit_lines:
            print("\n" + "─" * 60)
            print("AUDIT RESULTS")
            print("─" * 60)
            _AUDIT_RE = re.compile(
                r"AUDIT:"
                r"document_urn=(?P<document_urn>\S+)\s+"
                r"data_product_id=(?P<data_product_id>\S*)\s+"
                r"data_product_urn=(?P<data_product_urn>\S*)\s+"
                r"sync_status=(?P<sync_status>\S+)\s+"
                r"payload_hash=(?P<payload_hash>\S*)"
                r"(?:\s+error=(?P<error>.+))?"
            )
            for raw in audit_lines:
                m = _AUDIT_RE.match(raw)
                if m:
                    p = m.groupdict()
                    status = p["sync_status"]
                    icon = "✅" if status == "PASS" else ("⏭" if status == "SKIPPED" else "❌")
                    print(f"  {icon}  [{status}]  {p['data_product_id']}")
                    print(f"       document    : {p['document_urn']}")
                    print(f"       data product: {p['data_product_urn']}")
                    error = (p.get("error") or "").strip()
                    if error:
                        print(f"       ⚠ error    : {error}")
                else:
                    print(f"  ⚠  (unparseable) {raw}")
            print("─" * 60)

    if stderr:
        stderr_lines = stderr.splitlines()
        validation_errors = [
            l for l in stderr_lines
            if any(kw in l for kw in ("✗", "validation", "ERROR", "Error", "Traceback"))
        ]
        other_stderr = [
            l for l in stderr_lines
            if l not in validation_errors and l.strip()
        ]
        if validation_errors:
            print("\n" + "═" * 60)
            print("VALIDATION / ERRORS  (from stderr)")
            print("═" * 60)
            for line in validation_errors:
                print(f"  {line}")
            print("═" * 60)
        if other_stderr:
            print("\n[stderr – other]")
            for line in other_stderr:
                print(f"  {line}")


# ── Task 1 — audit_document ───────────────────────────────────────────────────

def audit_document(**context) -> dict[str, Any]:
    """Dry-run validation: validate all published tars-entity documents and write
    generated files to sync_output/. Returns an XCom payload consumed by open_pr.

    Raises RuntimeError if any document fails validation — open_pr is skipped.
    """
    graphql_url = Variable.get("DATAHUB_GRAPHQL_URL")
    token = Variable.get("DATAHUB_TOKEN")
    params = context.get("params", {})

    env = {
        **os.environ,
        "DATAHUB_GRAPHQL_URL": graphql_url,
        "DATAHUB_TOKEN": token,
    }

    cmd = [sys.executable, str(_SYNC_SCRIPT), "--mode", "gitops", "--dry-run"]

    doc_urn = str(params.get("document_urn", "") or "").strip()
    if doc_urn:
        cmd += ["--urn", doc_urn]

    if params.get("force"):
        cmd.append("--force")

    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, env=env, check=False, text=True, capture_output=True)
    _print_output(result.stdout, result.stderr)

    if result.returncode != 0:
        raise RuntimeError(
            f"audit_document failed (exit {result.returncode}) — open_pr will not run"
        )

    # ── Parse stdout to build XCom payload ────────────────────────────────────
    # We need: document_urn, document_title, data_product_id, md_content
    # Example stdout lines:
    #   ▶  Collections TEST  (urn:li:document:d1fd0bc2-...)
    #   → data_product_id derived from title: collections-test
    #   ✓ dry-run wrote /path/to/sync_output/collections_test.md

    _doc_header_re = re.compile(r"^▶\s+(.+?)\s+\((urn:li:document:[^)]+)\)")
    _dp_id_re = re.compile(r"→ data_product_id (?:derived from title|is): (\S+)")
    _dp_type_re = re.compile(r"→ data_product_type: (\S+)")
    _md_re = re.compile(r"✓ dry-run wrote (.+\.md)$")

    docs: list[dict[str, str]] = []
    current: dict[str, str] = {}

    for line in result.stdout.splitlines():
        m = _doc_header_re.match(line.strip())
        if m:
            if current.get("document_urn"):
                docs.append(current)
            current = {"document_title": m.group(1).strip(), "document_urn": m.group(2)}
            continue

        m = _dp_id_re.search(line)
        if m:
            current["data_product_id"] = m.group(1).strip()
            continue

        m = _dp_type_re.search(line)
        if m:
            current["data_product_type"] = m.group(1).strip()
            continue

        m = _md_re.search(line)
        if m:
            current["_md_path"] = m.group(1).strip()

    if current.get("document_urn"):
        docs.append(current)

    # Default missing types to "domain" for backward compatibility.
    for d in docs:
        d.setdefault("data_product_type", "domain")

    # Read MD content into XCom so downstream tasks don't depend on the local filesystem
    # (tasks may run on different workers that don't share /tmp or sync_output/).
    missing = []
    for d in docs:
        md_path = d.pop("_md_path", None)
        if not md_path or not d.get("data_product_id"):
            missing.append(d.get("document_urn", "?"))
            continue
        p = Path(md_path)
        if not p.exists():
            missing.append(f"{d.get('document_urn', '?')} (md not found: {md_path})")
            continue
        d["md_content"] = p.read_text(encoding="utf-8")

    if missing:
        raise RuntimeError(
            "Could not read generated MD for: " + ", ".join(missing)
        )

    if not docs:
        print("No documents processed — nothing to PR.")
        return {"docs": []}

    print(f"\nXCom payload: {len(docs)} document(s) ready for PR")
    for d in docs:
        print(f"  {d['data_product_id']}: {len(d.get('md_content', ''))} chars")

    return {"docs": docs}


# ── Task 2 — classify_entity ──────────────────────────────────────────────────

def classify_entity(**context) -> dict[str, Any]:
    """Check GitHub and DataHub to classify each document as NEW or EDIT.

    GitHub check: does ``docs/llm_context/business_entities/{slug}.md`` already
    exist on master? If yes → EDIT (PR will show a diff). If no → NEW.

    DataHub check: does ``urn:li:dataProduct:{slug}`` exist? If yes, and the
    document's ``data_product_id`` structured property is not yet set, write it
    back to the document sidebar so ops users can see the linkage.

    Enriches the XCom payload from ``audit_document`` with ``is_edit`` (bool)
    and ``existing_dp_urn`` (str | None) per document, then passes it to
    ``open_pr``.
    """
    github_token = Variable.get("GITHUB_TOKEN")
    graphql_url = Variable.get("DATAHUB_GRAPHQL_URL")
    token = Variable.get("DATAHUB_TOKEN")

    os.environ["GITHUB_TOKEN"] = github_token
    os.environ["DATAHUB_GRAPHQL_URL"] = graphql_url
    os.environ["DATAHUB_TOKEN"] = token

    pkg_dir = str(_SYNC_PKG_DIR)
    if pkg_dir not in sys.path:
        sys.path.insert(0, pkg_dir)

    from sync.constants import MD_OUTPUT_DIR, MD_OUTPUT_DIR_METRICS  # noqa: PLC0415
    from sync.datahub_document_client import (  # noqa: PLC0415
        fetch_data_product,
        write_data_product_id,
    )
    from sync.github_delivery import (  # noqa: PLC0415
        file_exists_on_master,
        is_ip_allowlist_error,
    )

    audit: dict[str, Any] = context["ti"].xcom_pull(task_ids="audit_document") or {}
    docs: list[dict[str, Any]] = audit.get("docs", [])

    if not docs:
        print("No documents in XCom payload — nothing to classify.")
        return {"docs": []}

    for doc in docs:
        dp_id = doc["data_product_id"]
        product_id = dp_id.strip().lower().replace("_", "-")
        entity_slug = product_id.replace("-", "_")
        dp_type = doc.get("data_product_type", "domain")
        md_dir = MD_OUTPUT_DIR_METRICS if dp_type == "metric" else MD_OUTPUT_DIR
        md_path = f"{md_dir}/{entity_slug}.md"
        dp_urn = f"urn:li:dataProduct:{product_id}"

        try:
            is_edit = file_exists_on_master(md_path)
        except RuntimeError as exc:
            if is_ip_allowlist_error(exc):
                print(
                    f"  ⚠ [{dp_id}] GitHub API blocked by org IP allowlist — "
                    "cannot check if file exists on master, defaulting to NEW. "
                    "Add the Airflow worker IP to the GitHub org IP allowlist to fix this."
                )
                is_edit = False
            else:
                raise

        existing_dp = fetch_data_product(dp_urn)

        doc["is_edit"] = is_edit
        doc["existing_dp_urn"] = dp_urn if existing_dp else None

        # If a live Data Product exists but the document doesn't know its id yet,
        # write it back so the ops author can see the linkage in DataHub.
        if existing_dp and not doc.get("data_product_id_was_set"):
            ok = write_data_product_id(doc["document_urn"], product_id)
            if ok:
                print(f"  → wrote data_product_id={product_id!r} back to DataHub document")
            else:
                print(f"  ⚠ could not write data_product_id back for {product_id}")

        label = "EDIT" if is_edit else "NEW"
        dp_status = f"dp_exists=yes ({dp_urn})" if existing_dp else "dp_exists=no"
        print(f"  [{label}]  {dp_id}  {dp_status}")

    return {"docs": docs}


# ── Task 3 — open_pr ──────────────────────────────────────────────────────────

def open_pr(**context) -> None:
    """Open a GitHub PR with the generated MD file for each document that passed audit.

    Requires the GITHUB_TOKEN Airflow Variable. On merge, Woodpecker sync-tars-entities
    pushes the Data Product to DataHub in memory (no YAML committed to the repo).
    """
    github_token = Variable.get("GITHUB_TOKEN")
    graphql_url = Variable.get("DATAHUB_GRAPHQL_URL")
    token = Variable.get("DATAHUB_TOKEN")

    enriched: dict[str, Any] = context["ti"].xcom_pull(task_ids="classify_entity") or {}
    docs: list[dict[str, Any]] = enriched.get("docs", [])

    if not docs:
        print("No documents in XCom payload — nothing to PR.")
        return

    # Set env for github_delivery and datahub_client
    os.environ["GITHUB_TOKEN"] = github_token
    os.environ["DATAHUB_GRAPHQL_URL"] = graphql_url
    os.environ["DATAHUB_TOKEN"] = token

    # Ensure sync/ package is importable inside the Airflow worker
    pkg_dir = str(_SYNC_PKG_DIR)
    if pkg_dir not in sys.path:
        sys.path.insert(0, pkg_dir)

    from sync.constants import MD_OUTPUT_DIR, MD_OUTPUT_DIR_METRICS  # noqa: PLC0415
    from sync.datahub_document_client import write_sync_status  # noqa: PLC0415
    from sync.github_delivery import (  # noqa: PLC0415
        is_ip_allowlist_error,
        open_sync_pull_request,
    )

    failed: list[str] = []

    for doc in docs:
        dp_id = doc["data_product_id"]
        doc_urn = doc["document_urn"]
        title = doc.get("document_title", dp_id)
        md_content = doc.get("md_content", "")

        if not md_content:
            print(f"  ❌  No MD content in XCom payload for {dp_id}")
            failed.append(doc_urn)
            continue

        is_edit = doc.get("is_edit", False)
        dp_type = doc.get("data_product_type", "domain")
        md_output_dir = MD_OUTPUT_DIR_METRICS if dp_type == "metric" else MD_OUTPUT_DIR
        pr_label = "EDIT" if is_edit else "NEW"
        print(f"\n[{pr_label}] Opening PR for '{title}' ({dp_id}) [type={dp_type}] ...")
        try:
            pr = open_sync_pull_request(
                data_product_id=dp_id,
                md_content=md_content,
                document_title=title,
                document_urn=doc_urn,
                is_edit=is_edit,
                md_output_dir=md_output_dir,
            )
            print(f"  ✅  PR #{pr.pr_number}: {pr.pr_url}")
            print(f"       branch : {pr.branch}")
            print(f"       type   : {pr_label}")

            write_sync_status(
                doc_urn,
                status="PASS",
                data_product_urn=f"urn:li:dataProduct:{dp_id}",
            )

        except Exception as exc:
            if is_ip_allowlist_error(exc):
                msg = (
                    f"GitHub API blocked by org IP allowlist for {dp_id}. "
                    "Add the Airflow worker IP to the GitHub org IP allowlist "
                    "in Settings → Security → IP allow list."
                )
            else:
                msg = str(exc)
            print(f"  ❌  Failed to open PR for {dp_id}: {msg}")
            write_sync_status(doc_urn, status="FAIL", error=f"pr_error: {msg}")
            failed.append(doc_urn)

    if failed:
        raise RuntimeError(f"open_pr failed for: {', '.join(failed)}")


# ── DAG definition ─────────────────────────────────────────────────────────────

with DAG(
    dag_id="governance.sync_tars_entities",
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "retries": 0,
    },
    description=(
        "Validate, classify (NEW/EDIT), and open a GitHub PR for published DataHub "
        "Context Documents tagged tars-entity (domain data products) or tars-metrics "
        "(metric data products). Merging the PR triggers Woodpecker, which publishes "
        "the Data Product to DataHub."
    ),
    start_date=pendulum.datetime(2026, 6, 10, tz="America/Sao_Paulo"),
    schedule="*/5 * * * *",
    catchup=False,
    tags=["governance", "datahub", "tars"],
    doc_md="""
## sync_tars_entities

Three-task pipeline for ops-authored DataHub Context Documents.

```
audit_document  →  classify_entity  →  open_pr  →  [human review]  →  merge  →  Woodpecker  →  DataHub
```

### Supported document kinds

| DataHub tag | Data Product type | MD output directory |
|---|---|---|
| `tars-entity` | `domain` | `docs/llm_context/business_entities/` |
| `tars-metrics` | `metric` | `docs/llm_context/metric_entities/` |

Both tags are audited in a single run. Each document's type is detected automatically
from which tag is present.

### Task 1 — audit_document

Runs `sync_tars_entities.py --dry-run --mode gitops` against all PUBLISHED documents
tagged `tars-entity` or `tars-metrics`. Validates required sections, table existence,
SQL syntax, and slug collision. Writes generated `.md` to `sync_output/` and passes
file content to Task 2 via XCom (including `data_product_type` per doc).

Fails (Task 2 skipped) if any document fails validation.

### Task 2 — classify_entity

For each document from Task 1:
- **GitHub check**: does the MD file already exist on master?
  - Domain: `docs/llm_context/business_entities/<slug>.md`
  - Metric: `docs/llm_context/metric_entities/<slug>.md`
  - Yes → `EDIT` (PR shows a diff). No → `NEW`.
- **DataHub check**: does `urn:li:dataProduct:<slug>` already exist? If yes and
  the document's `data_product_id` structured property is not yet set, writes it
  back to the DataHub document sidebar so ops users see the linkage.

Passes the enriched payload (`is_edit`, `existing_dp_urn`, `data_product_type` per doc)
to Task 3.

### Task 3 — open_pr

Opens a GitHub PR to `master` labelled `[NEW]` or `[EDIT]` with the MD file committed
to the correct directory based on document type:
- Domain: `tars-entity-sync/<slug>` branch → `docs/llm_context/business_entities/<slug>.md`
- Metric: `tars-metrics-sync/<slug>` branch → `docs/llm_context/metric_entities/<slug>.md`

On merge, Woodpecker `sync-tars-entities` runs `sync_tars_entities.py --mode direct`
and publishes the Data Product (with the correct `data_product_type`) from in-memory YAML.

### CLI default vs this DAG

`sync_tars_entities.py` defaults to `direct` when `TARS_SYNC_MODE` is unset. This DAG
always runs audit with `--mode gitops` so production delivery is PR-based unless you
override `TARS_SYNC_MODE` on the worker.

### Params

| Param | Default | Description |
|---|---|---|
| `document_urn` | _(empty)_ | Sync a single document by URN; leave empty for full scan |
| `force` | `false` | Re-audit even if content hash is unchanged since last PASS |

### Required Airflow Variables

- `DATAHUB_GRAPHQL_URL` — DataHub GMS GraphQL endpoint
- `DATAHUB_TOKEN` — Editor-role personal access token
- `GITHUB_TOKEN` — GitHub PAT with `repo` write scope (for PR creation)
""",
    params={
        "document_urn": Param(
            default="",
            type="string",
            description=(
                "Audit a single document by URN (e.g. urn:li:document:abc123). "
                "Leave empty to scan all published tars-entity and tars-metrics documents."
            ),
        ),
        "force": Param(
            default=False,
            type="boolean",
            description=(
                "Re-audit even if document content hash matches the last successful audit."
            ),
        ),
    },
) as dag:
    t1 = PythonOperator(
        task_id="audit_document",
        python_callable=audit_document,
    )
    t2 = PythonOperator(
        task_id="classify_entity",
        python_callable=classify_entity,
    )
    t3 = PythonOperator(
        task_id="open_pr",
        python_callable=open_pr,
    )
    t1 >> t2 >> t3
