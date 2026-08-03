# Property Integrity Onboarding

## Ownership

**Data Owner:**
- carolina.espinoza@quintoandar.com.br
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- victor.prado@quintoandar.com.br

## Overview

**Property Integrity** is a set of three metric-entity docs that cover the For Rent
Post Contract property-integrity theme across the rental lifecycle:

1. [Property Integrity Offboarding](property_integrity_offboarding.md) — exit /
   termination quality
2. **Property Integrity Onboarding** (this file) — entry inspection review engagement
3. **Property Integrity Ongoing** (forthcoming) — ongoing repairs / in-contract integrity

**Property Integrity Onboarding** is a family of **tenant engagement** metrics for
For Rent entry (onboarding) inspections — how often tenants **access**, **finish**,
and **comment on** the entry inspection report. It covers five indicators built on
the OBT Onboarding grain (one row per contract = latest executed onboarding
inspection): **total inspections**, **% Tenant Accessed**, **% Tenant Finished**,
**% Tenant Finalização / Access**, and **% Tenant Comentarios / Access**.

This release is **tenant-first** because the H2'2026 OKR (KR 1.2) tracks tenant
review completion. **Owner-side engagement ratios are planned for a later revision**
of this doc — the OBT already carries the owner fields needed to add them.

A naive pool over all inspection bookings (including never-executed ones) or over
offboarding inspections produces the wrong number. The official universe is only
**executed** onboarding inspections, deduplicated to the latest per contract, with
approval/comment signals from the raw clean review chain and access signals from
`fact_report_inspections` (Amplitude).

**Exists exclusively for For Rent onboarding (entry) inspections under Post Contract
— Property Integrity. No FS equivalent; do not mix with Property Integrity
Offboarding.**

## Related Business Entities

- Inspection

## Catalog

| Metric | Type |
| :---- | :---- |
| total inspections | Health Metric |
| % Tenant Accessed | Health Metric |
| % Tenant Finished | OKR |
| % Tenant Finalização / Access | Health Metric |
| % Tenant Comentarios / Access | Health Metric |

## MBR

**Name** Post Contract
**Category** Property Integrity

## Glossary and Synonyms

- **Property Integrity Onboarding**, **integridade do imóvel onboarding**, **onboarding report review** → this family of metrics
- **Tenant**, **TT**, **IQ**, **inquilino** → Tenant (`reviewer_type = 'TENANT'` in the raw clean layer; TT/IQ/inquilino are Portuguese names/abbreviations for the same role, not distinct `reviewer_type` values)
- **% Tenant Accessed**, **% Tenant Access**, **acesso do inquilino ao laudo de entrada** → % Tenant Accessed
- **% Tenant Finished**, **% Tenant Finalização**, **completion rate**, **share of tenants completing the entry inspection review**, **KR 1.2** → % Tenant Finished (the H2'2026 OKR indicator)
- **% Tenant Finalização / Access**, **% Tenant Finished of Accessed** → % Tenant Finalização / Access
- **% Tenant Comentarios / Access**, **% Tenant Comments / Access** → % Tenant Comentarios / Access
- **OBT Onboarding**, **onboarding OBT** → the contract-grain base these ratios are built on (not yet a materialized lake table)

## Scope

**Included**: For Rent **onboarding** (entry) inspections that were **actually
executed** (`dim_inspection.inspection_type = 'onboarding'` AND
`fact_inspection.ts_inspected IS NOT NULL`). Grain is one row per `sk_contract` —
the latest executed onboarding inspection for that contract
(`ROW_NUMBER() OVER (PARTITION BY sk_contract ORDER BY ts_updated DESC, ts_inspected DESC, sk_inspection) = 1`).

**Excluded**: never-executed bookings (`ts_inspected IS NULL`); offboarding /
verification inspections; non-latest duplicate onboarding inspections per contract.

**Owner metrics (deferred):** official owner-side engagement ratios
(`% Owner Accessed`, `% Owner Finished`, and of-accessed variants) are **not part
of this doc yet**. The OBT already exposes the owner access/approval/comment
fields; they should be added in a follow-up once the tenant OKR set is stable.
Today we publish **tenant-only** ratios because KR 1.2 (H2'2026) is the share of
**tenants** completing the entry inspection review.

## Calculation

There is no single ratio — five aggregate keys share the same OBT Onboarding base.
There is **no materialized `obt_onboarding` table** in the lake yet; assemble the
grain from DW + clean (same pattern as the product-files OBT query), then apply
the ratios.

```
total_inspections              = COUNT(*)

% Tenant Accessed              = count_if(has_tenant_accessed_review = true) / count(*)

% Tenant Finished              = count_if(has_tenant_approved_review = true) / count(*)

% Tenant Finalização / Access  = count_if(has_tenant_approved_review = true)
                                 / count_if(has_tenant_accessed_review = true)

% Tenant Comentarios / Access  = count_if(total_tenant_comments > 0)
                                 / count_if(has_tenant_accessed_review = true)
```

where, on the OBT grain:

- **`has_tenant_accessed_review`** — aliased from
  `fact_report_inspections.has_tenant_access_review` (Amplitude page-view signal).
- **`has_tenant_approved_review`** — from the raw clean review chain
  (`datalake_inspection_services_clean.assessment` → `reviewer` → `review`),
  `BOOL_OR(reviewer_type = 'TENANT' AND is_approved)`, aggregated across all
  assessment versions ("ever" semantics).
- **`total_tenant_comments`** — distinct non-null tenant `review.comment` rows
  across all assessment versions.

**Do not** read tenant approval/comments only from `fact_report_inspections` for
this metric family — the official OBT sources those from the raw clean layer
because the DW report fact does not fully cover onboarding review engagement.

### Canonical Filter

Apply when assembling the OBT Onboarding base from `dw_inspections.fact_inspection`
+ `dim_inspection`:

```sql
di.inspection_type = 'onboarding'
AND fi.ts_inspected IS NOT NULL
AND rni = 1   -- latest executed onboarding inspection per sk_contract
```

**Warning**: dropping `ts_inspected IS NOT NULL` lets never-executed bookings into
the denominator and **deflates every engagement ratio**. Dropping the
`inspection_type = 'onboarding'` filter mixes exit inspections into an entry-only
metric. Skipping the `rni = 1` dedup silently double-counts contracts with multiple
onboarding bookings.

### Nuances

**No weight / parameter table** — ratios are unweighted counts over the OBT grain.
OKR targets for H2'2026 are fixed period goals (see Targets and OKRs), not runtime
coefficients.

| Signal | Source | Notes |
| :----- | :----- | :---- |
| Access | `fact_report_inspections.has_tenant_access_review` | Amplitude-derived; ad-blockers may produce false nulls |
| Approval | clean `reviewer.is_approved` where `reviewer_type = 'TENANT'` | "Ever" across assessment versions; pre-aggregate before join |
| Comments | clean `review.comment` via tenant reviewer | Distinct non-null comments; "ever" semantics |

**Fan-out guard**: the raw chain `assessment → reviewer(s) → review(s)` multiplies
rows. Always pre-aggregate `raw_review` to **one row per `id_inspection`** before
joining to the inspection base, or totals leave contract grain.

**CAST rule**: `fact_inspection.sk_inspection` is VARCHAR and may carry a
non-numeric prefix. Join raw `id_inspection` (BIGINT) as
`CAST(id_inspection AS VARCHAR) = sk_inspection` — never cast the SK down to
BIGINT.

**Two "review started" flags** exist on the OBT (`has_review_started` from the
report fact vs `has_review_started_option_two` from raw tenant/owner review). They
can disagree — pick one deliberately; neither is used in the five official ratios
above.

**Fallback**: when a parameter/period is missing there is nothing to fall back to
for the ratios themselves. For the H2'2026 OKR, compare actual **% Tenant Finished**
against the fixed targets below — do not invent intermediate targets.

## Dos and Don'ts

**Do:**

- Restrict to executed onboarding inspections and dedup to latest per `sk_contract`.
- Pre-aggregate the raw review chain to one row per inspection before joining.
- Use `has_tenant_access_review` from `fact_report_inspections` for access, and the
  raw clean `reviewer`/`review` path for approval and comments.
- Treat **% Tenant Finished** as the OKR indicator (KR 1.2) when reporting H2'2026
  progress.

**Don't:**

- Don't include never-executed bookings or offboarding inspections in the base.
- Don't hardcode engagement rates or skip the fan-out guard on `raw_review`.
- Don't use `fact_report_inspections.has_tenant_approved_review` alone as the
  official approval signal for this family — follow the OBT raw-clean path.
- Don't average or substitute `has_review_started` / `has_review_started_option_two`
  for the five official ratios.
- Don't build owner-side % metrics and present them as part of this official set
  yet — they are deferred (see Scope); tenant ratios are the OKR surface for H2'2026.

## Targets and OKRs

**OKR** — KR 1.2: increase the share of tenants completing the entry inspection
review (H2'2026). Engagement with the entry report is the first step toward an
accurate record of the property's condition; **completion = % Tenant Finished**.

- **Source table:** no GSheets / lake target table — period goals live in the H2'2026
  Property Integrity OKR definition; monitor actuals on Superset
  ([slice 61062](https://superset.apps.data-prd.habitat.zone/explore/?form_data_key=EaugNXjtT-i2ucxW_USDH_qR30_rtrFA29V9nM2UwSuVH7b6b58XupZVE0y_pV_Y&slice_id=61062&save_action=overwrite))
  over the golden dataset below
- **Filter key / metric name:** `KR 1.2` / `% Tenant Finished` /
  `pct_tenant_finished`
- **Period grain:** H2'2026 (semester)
- **Aliases / search terms:** meta de finalização de revisão de entrada, OKR
  onboarding review completion, KR 1.2, share of tenants completing entry
  inspection review
- **Targets (H1 baseline 49.0%):**
  - **70%:** 51.4% (≈ +5% relative lift — minimum seen in the offboarding comms
    overhaul)
  - **100%:** 56.3% (≈ +15% relative lift — average offboarding lift)
  - **120%:** 61.2% (≈ +25% relative lift — high end of offboarding range)
- **Caveat:** there is no onboarding-specific historical lift benchmark; targets
  apply the offboarding communications-overhaul lift range to the 49.0% H1
  baseline. Compare actual **% Tenant Finished** (executed onboarding base) to
  these fixed H2 goals — do not substitute access-only or comments-of-accessed
  ratios for the OKR.

## Golden Queries

Assembles the OBT Onboarding grain (same pattern as the product-files OBT —
component identity/execution from `fact_inspection` + `dim_inspection`, access from
`fact_report_inspections`, approval/comments from clean `assessment`/`reviewer`/
`review`), then computes the five official ratios by month of `ts_sent_to_review`.
Trino dialect.

```sql
WITH raw_review AS (
    -- Tenant review / approval / comments — "ever" across assessment versions.
    -- Pre-aggregate to one row per inspection BEFORE joining (fan-out guard).
    SELECT
        a.id_inspection,
        BOOL_OR(
            r.reviewer_type = 'TENANT'
            AND r.is_approved
        ) AS has_tenant_approved_review,
        COUNT(
            DISTINCT CASE
                WHEN r.reviewer_type = 'TENANT'
                    AND rv.comment IS NOT NULL THEN rv.id_review
            END
        ) AS total_tenant_comments
    FROM datalake_inspection_services_clean.assessment AS a
    JOIN datalake_inspection_services_clean.reviewer AS r
        ON r.id_assessment = a.id_assessment
        AND r.reviewer_type = 'TENANT'
    LEFT JOIN datalake_inspection_services_clean.review AS rv
        ON rv.id_reviewer = r.id_reviewer
    GROUP BY 1
),
onboarding_inspections AS (
    SELECT
        fi.sk_contract,
        fi.sk_inspection,
        fi.ts_inspected,
        fri.ts_sent_to_review,
        fri.has_tenant_access_review AS has_tenant_accessed_review,
        COALESCE(rr.has_tenant_approved_review, FALSE) AS has_tenant_approved_review,
        COALESCE(rr.total_tenant_comments, 0) AS total_tenant_comments,
        ROW_NUMBER() OVER (
            PARTITION BY fi.sk_contract
            ORDER BY
                fi.ts_updated DESC,
                fi.ts_inspected DESC,
                fi.sk_inspection
        ) AS rni
    FROM dw_inspections.fact_inspection AS fi
    INNER JOIN dw_inspections.dim_inspection AS di
        ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN dw_inspections.fact_report_inspections AS fri
        ON fi.sk_inspection = CAST(fri.sk_inspection AS VARCHAR)
    LEFT JOIN raw_review AS rr
        ON CAST(rr.id_inspection AS VARCHAR) = fi.sk_inspection
    WHERE di.inspection_type = 'onboarding'
        AND fi.ts_inspected IS NOT NULL
),
obt_onboarding AS (
    SELECT
        sk_contract,
        sk_inspection,
        ts_inspected,
        ts_sent_to_review,
        has_tenant_accessed_review,
        has_tenant_approved_review,
        total_tenant_comments
    FROM onboarding_inspections
    WHERE rni = 1
)
SELECT
    DATE_TRUNC('month', CAST(obt.ts_sent_to_review AS DATE)) AS ref_month,
    COUNT(*) AS total_inspections,
    CAST(COUNT_IF(obt.has_tenant_accessed_review = TRUE) AS DOUBLE)
        / COUNT(*) AS pct_tenant_accessed,
    CAST(COUNT_IF(obt.has_tenant_approved_review = TRUE) AS DOUBLE)
        / COUNT(*) AS pct_tenant_finished,
    CAST(COUNT_IF(obt.has_tenant_approved_review = TRUE) AS DOUBLE)
        / CAST(NULLIF(COUNT_IF(obt.has_tenant_accessed_review = TRUE), 0) AS DOUBLE)
        AS pct_tenant_finished_of_accessed,
    CAST(COUNT_IF(obt.total_tenant_comments > 0) AS DOUBLE)
        / CAST(NULLIF(COUNT_IF(obt.has_tenant_accessed_review = TRUE), 0) AS DOUBLE)
        AS pct_tenant_commented_of_accessed
FROM obt_onboarding AS obt
WHERE CAST(obt.ts_sent_to_review AS DATE) >= DATE_ADD('month', -24, CURRENT_DATE)
    AND CAST(obt.ts_sent_to_review AS DATE) < CURRENT_DATE
GROUP BY 1
ORDER BY 1
```

To isolate the H2'2026 OKR indicator, keep only `pct_tenant_finished` (and
`total_inspections`) with the same `FROM` / `WHERE` / grain.

## Superset Golden Assets

- **Onboarding report review [For Rent] [Property Integrity]** — canonical Superset
  dataset for onboarding report-review engagement (access, finish, comments). URN:
  `urn:li:dataset:(urn:li:dataPlatform:superset,22529,PROD)`
  ([explore](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=22529))
- **KR 1.2 monitor (Superset chart)** — H2'2026 OKR progress for % Tenant Finished.
  URN: `urn:li:chart:(superset,chart.61062)`
  ([explore](https://superset.apps.data-prd.habitat.zone/explore/?form_data_key=EaugNXjtT-i2ucxW_USDH_qR30_rtrFA29V9nM2UwSuVH7b6b58XupZVE0y_pV_Y&slice_id=61062&save_action=overwrite))
