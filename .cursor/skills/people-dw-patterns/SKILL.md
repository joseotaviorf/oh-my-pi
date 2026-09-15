---
name: people-dw-patterns
description: >-
  People DW and metric SQL/metadata patterns: independent source SCD temporal
  resolution, EMR-safe dedup without QUALIFY, business-first metadata (PIN not
  Oracle HCM; no Oracle table names in descriptions). Invoke when editing
  dags/people/dw_* or metric_people SQL/metadata.
---

# People DW — SQL and metadata patterns

**Canonical rules:**

- **`.cursor/rules/people/people_domain.mdc`** — **Temporal attribute resolution (independent source SCDs)**, **DW Layer — SQL (dual-runtime / EMR)**
- **`.cursor/rules/people/people_metadata.mdc`** — Metadata Gold Standard, including **People DW and metric metadata — business audience (FAIR F2-02)**

Read those sections before implementing or reviewing. This skill is a **routing playbook**, not a duplicate of the rule file.

---

## When to use

- Authoring or reviewing **People DW** `.sql` under `dags/people/dw_*` or **metric** metadata under `dags/people/metric_people/`
- Resolving attributes when the **dimension grain** and the **attribute source** have independent effective dating in PIN
- Replacing **`QUALIFY`** for EMR Spark 3.5 compatibility
- **PR review** on People DW/metric metadata (repetitive descriptions, FAIR `too_short` / `boilerplate_or_name_echo`)

---

## Quick checklist — independent source SCD

1. Identify dimension grain (what drives `dt_valid_from` / `sk_*_version`).
2. Identify attribute source with its own effective dates on `pin_*` clean.
3. **Reference date for attribute join:**
   - Historical dimension version → `dt_valid_from`
   - Current dimension version → `CURRENT_DATE` (internal `dt_*` alias in CTE)
4. Dedupe with `ROW_NUMBER()` CTE, not `QUALIFY`.
5. Explain temporal behavior in a **SQL comment**; metadata stays business-facing.
6. Validate: `CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency validate-fair-metadata` when metadata changed.

---

## Quick checklist — metadata (People DW and metric)

| Check | Action |
|-------|--------|
| **Audience** | Business wording — HR / People Insights, not engineering |
| Table `description` | Grain, SCD, consumers — no join algorithm; **PIN** if source named, never Oracle table names |
| Column `description` | Business meaning; no `per_*` / Oracle objects; no per-column "at this version" boilerplate |
| Technical detail | SQL `--` comments only |
| FAIR failures | Expand only failing columns with distinct wording; avoid name echo |

---

## Validation (People tables)

- **Lineage / Yamale / FAIR:** `make validate-lineage-consistency`, `make validate-metadata-files-content`, `make validate-fair-metadata` with `CI_COMMIT_BRANCH` set.
- **Ad-hoc SQL (prod):** Use Trino by default; fall back to Databricks CLI on a running People test cluster, or an ad-hoc EMR cluster via **`emr-run`** (role `emr-people-prod`), only for a brand-new table not deployed to prod yet — see **`people_domain.mdc`** § ad-hoc SQL.

---

## After merge — codify new learnings

If review or Forno exposes a **durable** pattern (not ticket-specific data), extend the rule that owns the concern in a small follow-up PR: **`people_domain.mdc`** for pipeline/SQL behavior, **`people_metadata.mdc`** for metadata authoring. See **`dbp-jira-reference.md`** § Codifying delivery learnings.
