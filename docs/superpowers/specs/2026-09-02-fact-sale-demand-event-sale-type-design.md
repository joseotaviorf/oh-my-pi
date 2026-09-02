# `fact_sale_demand_event` `sale_type` Design

## Goal

Expose the primary-market classification on the consolidated For Sale demand-event
fact without changing its event grain or adding a lookup join.

## Context

`dw_sale.fact_sale_demand_event` produces visit and offer lifecycle events from
`dw_sale.fact_visits` and `dw_sale.fact_offers`. The visit fact already exposes
`sale_type`, while the offer fact does not. The event fact currently carries 3P
flags but no market classification.

## Decision

Add nullable `sale_type` to `dw_sale.fact_sale_demand_event`:

- Visit-derived events (`VISIT_BOOKED`, `VISIT_COMPLETED`, and
  `VISIT_CANCELED`) propagate `dw_sale.fact_visits.sale_type`.
- Offer-derived events emit `CAST(NULL AS STRING) AS sale_type` until the offer
  propagation is implemented separately.
- Missing source values remain `NULL`; they are not converted to `SECONDARY`.
- The column is placed with event characteristics, before the existing 3P
  boolean columns.
- Metadata documents the column with lineage to
  `dw_sale.fact_visits.sale_type` and PRIMARY/SECONDARY categories.

## Scope

In scope:

- `dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql`
- `dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml`
- Static SQL/metadata validation and CI

Out of scope:

- Joins to `listing_sale_type`
- Changes to `fact_offers`, `sale_offer`, buyer-prospect, listing, closing, or
  NPS tables
- DAG declarations or generated dependencies
- Forno execution in this slice

## Compatibility and correctness

The existing event grain remains one row per event key. All `UNION ALL` arms
will project the same `sale_type` position and type. The value is nullable for
offer-derived events and for visit rows whose upstream classification is
missing.

## Validation

Run:

- SQL/metadata lineage consistency
- Metadata schema validation
- EMR Spark 3.5 SQL lint and join-shape validation
- Repository Woodpecker CI
