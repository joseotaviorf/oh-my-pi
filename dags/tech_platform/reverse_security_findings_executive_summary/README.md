# Reverse Security Findings Executive Summary DAG

This directory contains the DAG that publishes the Security Data Gateway findings executive
summary for the Base44 dashboard. It runs the allowlisted aggregate SQL from
[IDPLATF-8282](https://quintoandar.atlassian.net/browse/IDPLATF-8282) against
`datalake_security_data_gateway_clean.security_findings` and overwrites a single JSON object in
S3 — KPI counts and risk/PII-type/resource-type/source/day breakdowns only, no emails, resource
ids, names, or raw payloads.

## Files

- `reverse_security_findings_executive_summary_declaration.yml` - DAG configuration (`load_access`, reverse layer)
- `reverse_security_findings_executive_summary_cluster.yml` - EMR cluster, pinned to UTC session timezone
- `queries/reverse/executive_summary.sql` - Allowlisted aggregate query that materializes the reverse table row
- `spark_jobs/load_executive_summary_to_s3.py` - Spark job: reshapes the row into the schema_version 1 JSON contract and uploads it to S3
- `prod_conf.yml` / `forno_conf.yml` - Per-environment S3 bucket/key, resolved via `ConfigurationService`
- `README.md` - This file

## Contract

The JSON shape (`schema_version: "1"`) is defined in
[IDPLATF-8282](https://quintoandar.atlassian.net/browse/IDPLATF-8282):

```json
{
  "schema_version": "1",
  "as_of": "2026-09-10T15:14:59Z",
  "grain": "one table row; lake contract is (source, id_resource)",
  "kpis": {
    "total": 219387,
    "critical": 26164,
    "high_plus_critical": 140414,
    "classified_last_30d": 194372
  },
  "by_risk_level": [{ "risk_level": "CRITICAL", "count": 26164 }],
  "by_pii_type": [{ "pii_type": "full_name", "count": 195589 }],
  "by_resource_type": [{ "resource_type": "google_drive_file", "count": 219387 }],
  "by_source": [{ "source": "drive_historical_backfill", "count": 219387 }],
  "classified_by_day": [{ "date": "2026-08-12", "count": 24 }]
}
```

`as_of` is `MAX(ts_classified)` from the source table, not wall-clock time — `classified_last_30d`
and the 30-day `classified_by_day` spine (zeros included) are both relative to it. Array ordering
(risk-level rank, count desc for the others, day ascending) is applied in Python, not SQL — Spark's
`collect_list` does not guarantee order.

**Never select:** emails, `id_resource`, `resource_name`, `shared_with`, `actor_email`,
`source_raw_payload`.

## Destination

- **Prod:** `s3://5a-base44-office/security_data_gateway/executive_summary/current_summary.json`.
  Owned by Base44, not by this DAG.
- **Forno:** `s3://sdg-forno-executive-summary/security_data_gateway/executive_summary/current_summary.json`.
  A dedicated smoke-test bucket — forno cannot write to `5a-base44-office` (its policy denies every
  principal outside an allow-list that excludes `emr-forno`), so this is a separate bucket
  provisioned in [quintoandar/infrastructure#45315](https://github.com/quintoandar/infrastructure/pull/45315)
  (`cloud/aws-accounts/forno-data/security-data-gateway/s3`), the same pattern People's
  `s3_ingestion` DAG uses for its own forno mirror bucket.

Bucket/key come from `ConfigurationService` (`prod_conf.yml` / `forno_conf.yml`) per environment.
If a future environment's conf leaves the bucket unset, the job logs and skips the upload rather
than failing.

### Outstanding infra dependency

In **prod**, the DAG's execution role does not yet have `s3:PutObject` on that key. Granting it is
a follow-up to [IDPLATF-8284](https://quintoandar.atlassian.net/browse/IDPLATF-8284), tracked in
`quintoandar/infrastructure` — not part of this repo. Until that lands, the upload step fails with
`AccessDenied` in prod. Forno already grants `emr-forno` full access via the Terraform PR above.

## Usage

The DAG has no cron schedule. It is triggered automatically, via `dependencies.yaml` lineage,
as soon as the upstream `security_data_gateway_findings` DAG finishes its clean-layer load. For
manual execution:

1. Access the Airflow UI
2. Navigate to the DAG `tech_platform.reverse_security_findings_executive_summary`
3. Click "Trigger DAG"

## Monitoring

Check the logs of the `load_executive_summary_to_s3` task. A skipped upload (bucket unset for the
environment) logs `msg=no executive-summary S3 bucket provisioned`; a prod run before the
IDPLATF-8284 IAM grant lands fails with `AccessDenied` — both are visible there.
