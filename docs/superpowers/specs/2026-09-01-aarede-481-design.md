# AAREDE-481: Strict Primary Market House Classification

## Status

Approved design. Implementation starts after specification review.

## Context

Primary Market source data now exposes `sale_type` on the clean
`listing_sale_model` table. Production currently contains `536` rows with
`sale_type = 'PRIMARY'`, while legacy-primary rows still include `4,767` rows
with `sale_type IS NULL` and `98` rows with `sale_type = 'SECONDARY'`.

The enriched house table currently derives `is_sale_primary_market` from the
legacy `is_primary_market` boolean. That preserves historical classifications
but does not follow the new source-of-truth enum. The existing house query also
uses `QUALIFY`, which is not compatible with EMR Spark 3.5.

## Goal

Update the house enrichment so Primary Market classification follows the
`sale_type` enum while preserving the existing output column, house grain, and
downstream interfaces.

## Scope

Modify only:

- `dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql`
- `dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml`

The SQL change will:

1. Replace `BOOL_OR(lsm.is_primary_market)` with
   `BOOL_OR(lsm.sale_type = 'PRIMARY')` in `listing_info`
2. Add a `listing_business_context_ranked` CTE that ranks rental context
   before sale context per house
3. Join only the ranked context row and remove the final `QUALIFY`

The metadata change will replace lineage from
`listing_sale_model.is_primary_market` with lineage from
`listing_sale_model.sale_type` and document strict enum semantics.

## Semantics

- `sale_type = 'PRIMARY'` produces `TRUE`
- `sale_type = 'SECONDARY'` produces `FALSE`
- `sale_type IS NULL` produces `FALSE` after the existing final `COALESCE`
- Multiple sale model rows are evaluated independently; any `PRIMARY` row wins
- The legacy `is_primary_market` value is not a fallback
- Existing one-row-per-house output and rental-before-sale context selection
  remain unchanged

This intentionally means legacy-primary rows without a populated
`sale_type` will no longer be classified as Primary Market. After source
backfill, the legacy flag can be compared for reconciliation, but it will not
be used in production derivation.

## Non-goals

- Updating `dw_sale.dim_listing` or any downstream fact
- Backfilling or mutating production data
- Adding new tables, columns, or DAG declarations
- Updating TARS, dashboards, events, or other Primary Market documentation
- Adding a dedicated SQL fixture for this existing transformation

## Validation

Run, in order:

1. Databricks/EMR SQL compatibility lint immediately after editing
   `house.sql`
2. Metadata content validation
3. SQL-to-metadata lineage validation
4. FAIR metadata validation
5. Repository lint and style checks
6. Source-layer policy validation
7. LLM-context impact validation

This delivery uses static validation only. A Forno DAG run remains pending and
will not be represented as completed in the pull request description.

## Delivery

Create `AAREDE-481/derive-house-primary-market` from fresh `origin/master`.
Commit the focused change, push the branch, and open a draft pull request
linked to AAREDE-481. Do not change Jira status or add Jira comments.

## Phase 0 Decision Log

- scope: AAREDE-481 house enrich classification and paired metadata
- out-of-scope: DW, downstream facts, backfills, TARS documentation, unrelated ingestion
- success: `PRIMARY` true; `NULL` and other values false; legacy flag never fallback
- edge-cases: `BOOL_OR` across multiple sale rows; preserve house grain and null coalescing
- arch-constraints: preserve `is_sale_primary_market`; support DBR 16.4 and EMR Spark 3.5
- error-handling: retain existing final `COALESCE(..., FALSE)`
- test-coverage: static checks only; no new fixture; Forno remains pending
- delivery: fresh Jira-scoped branch, commit, push, draft PR
