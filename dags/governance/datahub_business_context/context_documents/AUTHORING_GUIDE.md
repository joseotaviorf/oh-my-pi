# TARS Entity Context — Self-Service Authoring Guide

This guide is for **QuintoAndar business users** who want to contribute entity context for **TARS** (the data analyst AI) without GitHub access.

## What you are creating

A **DataHub Context Document** tagged `tars-entity`. After domain-owner approval and publication, an automated pipeline converts it into a **Data Product** that TARS reads via DataHub.

```
You write in DataHub  →  Domain owner publishes  →  Pipeline syncs  →  TARS uses Data Product
```

## Step-by-step

### 1. Create the document

1. Open [DataHub](https://datahub.apps.data-prd.habitat.zone) → **Documents**.
2. Find the **[TARS Entity Template](https://datahub.apps.data-prd.habitat.zone/document/urn:li:document:tars-entity-template)** document (`urn:li:document:tars-entity-template`).
3. Copy its full content.
4. Click **+ New**, choose **Process Guide**, paste the copied content, and replace all `{placeholders}` with real content for your entity.

### 2. Set metadata

| Field | Value |
|-------|-------|
| **Title** | Entity display name (e.g. "Collections", "Payments") |
| **Domain** | The data domain this entity belongs to (Fintech, Growth, People, etc.) |
| **Tag** | `tars-entity` (required — pipeline only picks up tagged documents) |
| **Owners** | Yourself + the domain data owner / steward |
| **Related assets** | Link the main DW tables your document describes (optional but recommended) |

### 3. Fill Structured Properties (sidebar)

These fields are **required** for the sync pipeline. Ask your data steward if unsure.

| Property | Example | Notes |
|----------|---------|-------|
| `domain_urn` | `urn:li:domain:fintech` | DataHub domain URN — never guess; ask your steward |
| `data_product_id` | `collections` | kebab-case slug; becomes `urn:li:dataProduct:collections` |
| `primary_datasets` | `dw_losses.fact_accounts_receivable,dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline` | Comma-separated `schema.table` pairs |
| `golden_query_stable_urn` | `urn:li:query:a1b2c3d4-e5f6-7890-abcd-ef1234567890` | Generate once; **never change** after first publish |
| `glossary_parent_node_urn` | `urn:li:glossaryNode:fintech` | Optional; defaults to domain node |

Generate a UUID for `golden_query_stable_urn`:

```bash
python -c "import uuid; print(f'urn:li:query:{uuid.uuid4()}')"
```

### 4. Draft → review → publish

1. Save as **Draft** while writing.
2. Ask your **domain data owner** to review content, tables, and golden queries.
3. Domain owner toggles **Published** when ready.
4. The sync pipeline runs daily (or on next scheduled run) and opens a PR for engineering review (Phase 2) or pushes directly (Phase 3).

### 5. Versioning

DataHub tracks every edit automatically:

- Title changes, content changes, publish/unpublish events
- Who changed what and when (equivalent to Git blame)
- Restore any previous version from the document **History** tab

To roll back a Data Product: restore the previous document version in DataHub → re-publish → pipeline re-syncs.

## Required document sections

Every published `tars-entity` document **must** include these markdown sections (matching the template):

| Section | Purpose |
|---------|---------|
| `# {Entity Name}` | Display title |
| `## Overview` | What the entity is and why it matters |
| `## Glossary and Synonyms` | PT-BR terms → technical mapping |
| `## Tables` | "You need… / Use this table" routing |
| `## Key Metrics` | 5–10 KPIs with column references |
| `## Relationships with Other Entities` | JOIN patterns and cardinality |
| `## Dos and Don'ts` | Filters, grains, common mistakes |
| `## Golden Queries` | At least one Trino SQL example |

## Who can do what

See [`../policies/tars_entity_metadata_policies.yml`](../policies/tars_entity_metadata_policies.yml) for the full access-control matrix. Summary:

| Role | Create draft | Edit own draft | Publish | Edit published |
|------|-------------|----------------|---------|----------------|
| Business contributor | ✅ (own domain) | ✅ | ❌ | ❌ |
| Domain data steward | ✅ | ✅ | ✅ | ✅ |
| Data Governance admin | ✅ | ✅ | ✅ | ✅ |

## Getting help

- **Guide in DataHub:** [TARS Entity Authoring Guide](https://datahub.apps.data-prd.habitat.zone/document/urn:li:document:tars-entity-authoring-guide) (`urn:li:document:tars-entity-authoring-guide`)
- **Template in DataHub:** [TARS Entity Template](https://datahub.apps.data-prd.habitat.zone/document/urn:li:document:tars-entity-template) (`urn:li:document:tars-entity-template`)
- **Engineer path (GitHub):** [`docs/llm_context/business_entities/_TEMPLATE.md`](../../../../docs/llm_context/business_entities/_TEMPLATE.md)
- **Data Governance squad:** `#data-governance` on Slack

## How the template stays up to date

Both this guide and the template are managed as Git source-of-truth Markdown files and automatically pushed to DataHub by the `push-context-documents` Woodpecker CI step on every merge to `master`. You do not need to manually update them in DataHub — any edits merged to Git will appear in DataHub within minutes of the CI run completing.
