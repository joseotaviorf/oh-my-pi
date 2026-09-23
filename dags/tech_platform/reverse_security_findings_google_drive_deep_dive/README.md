# Reverse Security Findings Google Drive Deep Dive DAG

This directory contains the DAG that publishes the Security Data Gateway Google Drive findings
deep-dive snapshot for the Base44 dashboard's Deep dive tab. Same pattern as its sibling
`reverse_security_findings_executive_summary` DAG, but for the deep-dive breakdowns instead of
the executive KPIs. It runs an aggregate query against
`datalake_security_data_gateway_clean.security_findings` and overwrites a single JSON object in
S3 — MIME-type/shared-drive/external-grantee/org-unit/PII-combination/exposure-matrix
breakdowns, plus two Privacy-approved raw-email panels (`top_external_users`, `top_owners`;
see CORESEC-73 — internal/partner Workspace accounts, not customer PII). No resource ids,
names, or raw payloads anywhere.

## Files

- `reverse_security_findings_google_drive_deep_dive_declaration.yml` - DAG configuration (`load_access`, reverse layer)
- `reverse_security_findings_google_drive_deep_dive_cluster.yml` - EMR cluster, pinned to UTC session timezone
- `queries/reverse/google_drive_deep_dive.sql` - Aggregate query that materializes the reverse table row
- `spark_jobs/load_google_drive_deep_dive_to_s3.py` - Spark job: pivots each breakdown into the schema_version 1 JSON contract and uploads it to S3
- `README.md` - This file

Per-environment S3 bucket/key live in the shared core `forno_conf.yml` / `prod_conf.yml`
(`packages/bietlejuice-core/src/bietlejuice/config/`), not a DAG-level conf.yml — this job runs
on EMR, where the `dags` package is never on `sys.path`, so `ConfigurationService` can't resolve
a per-DAG conf.yml there (that resolution path is Composer/Databricks-only).

## Contract

The JSON shape (`schema_version: "1"`) is tracked in
[CORESEC-73](https://quintoandar.atlassian.net/browse/CORESEC-73); confirm/adjust with whoever
reviews the PR if it needs to change:

```json
{
  "schema_version": "1",
  "as_of": "2026-09-17T12:00:00Z",
  "kpis": {
    "org_units_with_findings": 2,
    "shared_drives_affected": 96,
    "external_users_with_pii_access": 317,
    "exposed_beyond_domain": 168370
  },
  "exposed_pct_note": "38.8% of findings have at least one external-domain grantee",
  "pii_findings_total": 433553,
  "total_findings": 433576,
  "by_mime_type": [{ "label": "application/pdf", "count": 183673, "mix": {"CRITICAL": 7897, "HIGH": 138243, "MEDIUM": 1850, "LOW": 35683} }],
  "top_shared_drives": [ /* same shape, top 10 by count */ ],
  "top_external_users": [ /* same shape, label = raw grantee email, top 10, PII findings only */ ],
  "top_owners": [ /* same shape, label = raw actor_email, top 10, PII findings only. Empty today. */ ],
  "by_org_unit": [ /* same shape */ ],
  "riskiest_combinations": [{ "label": "full_name · EXTERNAL_GRANTEE", "count": 127674 }],
  "exposure_matrix": {
    "sharing_states": ["EXTERNAL_GRANTEE", "INTERNAL_ONLY"],
    "risk_levels": ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
    "cells": { "EXTERNAL_GRANTEE": {"CRITICAL": 5320, "HIGH": 107844, "MEDIUM": 1594, "LOW": 53612}, "INTERNAL_ONLY": {...} }
  }
}
```

`as_of` is `MAX(ts_classified)` from the source table, not wall-clock time. Every panel's array
ordering (count desc, label asc) and the `label`/`mix` pivot are applied in Python, not SQL —
Spark's `collect_list` does not guarantee order.

**Data caveats (verified via Trino against production, not assumed from docs):**
- `sharing_state` has exactly one distinct value in this table today, so `riskiest_combinations`
  and `exposure_matrix` are keyed on an `EXTERNAL_GRANTEE` / `INTERNAL_ONLY` flag derived from
  `shared_with[].email` domain instead. Revisit once the table has organic sharing_state variety.
- `actor_email` is 0% populated today (shared-drive-only scan scope) — `top_owners` returns an
  empty array with a `top_owners_note`; the query is production-ready and needs no changes once
  file-owner identity is captured.
- `ou_path` only has 2 real non-empty values today, both Workspace-root-level.
- Internal-domain classification (best-effort, confirm with the Drive-to-domain mapping owner):
  internal = `@quintoandar.com.br`, `@quintoandar.com`, `@ext.quintoandar.com.br`; service
  account = `*.iam.gserviceaccount.com`; everything else = external.

**Never select:** `id_resource`, `resource_name`, `source_raw_payload`. `actor_email` and
`shared_with[].email` are the one approved exception — Privacy signed off (CORESEC-73) on
emitting them as raw addresses in `top_owners` / `top_external_users` only, since these are
internal/partner Workspace accounts, not customer PII. No other panel exposes an email.

## Destination

- **Prod:** `s3://5a-base44-office/security_data_gateway/executive_summary/google_drive_deep_dive.json`.
  Owned by Base44, same bucket **and same prefix** as the executive summary export
  (`current_summary.json` lives alongside it), just a different file.
- **Forno:** `s3://sdg-forno-executive-summary/security_data_gateway/executive_summary/google_drive_deep_dive.json`.
  Same forno smoke-test bucket and prefix as the executive summary export
  ([quintoandar/infrastructure#45315](https://github.com/quintoandar/infrastructure/pull/45315)).

Bucket/key come from `ConfigurationService` (core `prod_conf.yml` / `forno_conf.yml`) per
environment. If a future environment's conf leaves the bucket unset, the job logs and skips the
upload rather than failing.

Because this key shares the executive summary export's prefix
(`security_data_gateway/executive_summary/`), the existing IDPLATF-8284 `s3:PutObject` grant
already covers it — no new IAM follow-up is needed for prod.

## Usage

The DAG has no cron schedule. It is triggered automatically, via `dependencies.yaml` lineage, as
soon as the upstream `security_data_gateway_findings` DAG finishes its clean-layer load — same
trigger as `reverse_security_findings_executive_summary`. For manual execution:

1. Access the Airflow UI
2. Navigate to the DAG `tech_platform.reverse_security_findings_google_drive_deep_dive`
3. Click "Trigger DAG"

## Monitoring

Check the logs of the `load_google_drive_deep_dive_to_s3` task. A skipped upload (bucket unset
for the environment) logs `msg=no Google Drive deep-dive S3 bucket provisioned` — visible there.
