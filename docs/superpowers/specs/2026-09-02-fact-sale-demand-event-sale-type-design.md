# `fact_sale_demand_event` `sale_type` Design

## Goal

Expose the primary-market classification across the For Sale offer and demand-event
facts without changing their grains or adding lookup joins.

## Context

`dw_sale.fact_sale_demand_event` produces visit and offer lifecycle events from
`dw_sale.fact_visits` and `dw_sale.fact_offers`. The visit fact already exposes
`sale_type`, while the offer path now starts at the merged `core_sale_offer`
change but is not yet passed through `sale_offer` and `fact_offers`. The event
fact currently carries 3P flags but no market classification.

## Decision

Propagate nullable `sale_type` through the offer and event paths:

- `datalake_sale_offer.core_sale_offer.sale_type` passes through
  `datalake_sale_offer.sale_offer.sale_type` into
  `dw_sale.fact_offers.sale_type`.
- Visit-derived events (`VISIT_BOOKED`, `VISIT_COMPLETED`, and
  `VISIT_CANCELED`) propagate `dw_sale.fact_visits.sale_type`.
- Offer-derived events (`OFFER_SUBMITTED`, `OFFER_ACCEPTED`,
  `SALE_AGREEMENT_CREATED`, `SALE_AGREEMENT_SIGNED`, and `OFFER_DISMISSED`)
  propagate `dw_sale.fact_offers.sale_type`.
- Firestore-only and other source rows without classification remain `NULL`.
- Missing source values remain `NULL`; they are not converted to `SECONDARY`.
- The column is placed with characteristics, before the existing 3P boolean
  columns.
- Metadata documents the offer and event columns with their direct upstream
  lineage and PRIMARY/SECONDARY categories.

## Scope

In scope:

- `dags/for_sale/enrich_sale_offer/queries/enrich/sale_offer.sql`
- `dags/for_sale/enrich_sale_offer/metadata/enrich/sale_offer.yml`
- `dags/for_sale/dw_sale_offers/queries/dw/fact_offers.sql`
- `dags/for_sale/dw_sale_offers/metadata/dw/fact_offers.yml`
- `dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql`
- `dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml`
- Static SQL/metadata validation and CI

Out of scope:

- Joins to `listing_sale_type`
- Changes to `dim_offer`, `dim_sale_agreement`, buyer-prospect, listing,
  closing, or NPS tables
- DAG declarations or generated dependencies
- Forno execution in this slice

## Compatibility and correctness

The existing offer and event grains remain unchanged. The event `UNION ALL` arms
will project the same `sale_type` position and type. Visit events use the visit
classification; offer events use the offer classification. No event arm derives
one grain's classification by joining the other grain.

## Validation

Run:

- SQL/metadata lineage consistency
- Metadata schema validation
- EMR Spark 3.5 SQL lint and join-shape validation
- Repository Woodpecker CI
