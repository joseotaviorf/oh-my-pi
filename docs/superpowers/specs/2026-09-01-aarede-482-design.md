# AAREDE-482: Document dim_listing Primary Market passthrough

## Status

Approved design. Implementation starts after this specification.

## Context

`dw_sale.dim_listing.is_primary_market` already exists as a passthrough:

```sql
h.is_sale_primary_market AS is_primary_market
```

AAREDE-481 changes the house derivation to `BOOL_OR(lsm.sale_type = 'PRIMARY')`.
Once that enrich DAG runs, `dim_listing` follows with no extra SQL.

Ticket DoD also requires a documented join pattern for facts that still lack
their own Primary Market flag.

## Goal

Make `dim_listing.is_primary_market` metadata match the saleType-derived house
truth, and document how facts should join until Wave 2 denormalization.

## Scope

Modify only:

- `dags/house_and_listing/dw_sale_listings/metadata/dw/dim_listing.yml`
- Primary Market wiki (`concepts/downstream-lineage-propagation.md`, `log.md`)
- Superpowers spec and plan under `docs/superpowers/`

Do not modify `dim_listing.sql`, fact tables, or the AAREDE-481 house PR.

## Semantics

- True only when enrich house `is_sale_primary_market` is true
- After 481: that means any LSM row for the house has `sale_type = 'PRIMARY'`
- NULL and non-PRIMARY stay false; no legacy boolean fallback
- Lineage stays `datalake_ebdb_listing.house.is_sale_primary_market`

## Interim fact join

Prefer existing consumers' pattern:

```sql
LEFT JOIN dw_sale.dim_listing AS dl
  ON fact.sk_house = dl.sk_house
WHERE dl.is_primary_market
```

If the fact already has `sk_sale_listing`, join on that key instead (dim grain).
Wave 2 (AAREDE-484+) denormalizes the flag onto facts.

## Out of scope

- SQL changes and Forno
- Exposing `sale_type` on `dim_listing`
- Pilot row-level validation in production (blocked until 481 is in Forno/prod)
- Fact denormalization
