# Calibration examples

Worked from `local/etl_gantt/output.csv` with hop 0 = [`datalake_ciq.ciq_listing_purchase`](dags/agents/enrich_ciq_listing_purchase/queries/enrich/ciq_listing_purchase.sql) (seed start 10:47, end 11:07 UTC). Use these as classification templates, not as standing facts. Report output must link tables the same way.

## Passthrough + simple logic (recommend)

**[`ciq_supply_events_tracking`](dags/agents/enrich_ciq_listing_purchase/queries/enrich/ciq_supply_events_tracking.sql) (hop 1, 10:47) → [`supply_events_tracking`](dags/growth/enrich_supply_tracking/queries/enrich/supply_events_tracking.sql) (09:31) or [`conversion_tracking`](dags/growth/enrich_supply_tracking/queries/enrich/conversion_tracking.sql) (09:20)**

Hop 0 uses a distinct `id_house` where `business_context = 'RENT'` and funnel step 6, remapping `company_report_origin`. The CIQ table is CASE maps on `application` / `ops_agent` / `supply_source` already on the supply-tracking tables, plus an `inner_dependencies` wait. Inlining is a delivery win; meaning unchanged if the same CASE and filters are copied.

**[`valid_first_listing`](dags/agents/enrich_listing_deduplication/queries/enrich/valid_first_listing.sql) (10:34) → [`first_listing`](dags/agents/enrich_listing_deduplication/queries/enrich/first_listing.sql) (09:59)**

Hop 0 uses only `hybrid_creation_order = 'SALE > RENT'`, a CASE on `ts_first_listing_rent` vs `_sale` and `is_hybrid_house` (two contexts with `has_first_listing`). Do **not** substitute clean [`listing_business_context`](dags/house_and_listing/ebdb_listing_fast_lane/queries/clean/listing_business_context.sql) `ts_first_publication`: enrich first-listing time and last-CIQ grain differ.

## Passthrough that does not move hop 0

**[`atlas_house_deduplication`](dags/agents/enrich_listing_deduplication/queries/enrich/atlas_house_deduplication.sql) → [`similar_property`](dags/growth/property_dedup/queries/clean/similar_property.sql) + [`duplicity_output`](dags/growth/property_dedup/queries/clean/duplicity_output.sql) (03:19)**

SQL is a join + last-duplicity window. Those cleans finish hours earlier, but hop 0 still waits on [`listing_deduplication`](dags/agents/enrich_listing_deduplication/queries/enrich/listing_deduplication.sql) (10:09) in the same producer DAG. Recommend the SQL move only together with dropping/splitting that DAG wait.

## Real transform (do not skip)

**[`listing_deduplication`](dags/agents/enrich_listing_deduplication/queries/enrich/listing_deduplication.sql)**: complement parse + window over `address_parsed_short` for `has_duplicates` / `first_listing_order`. `address_full` alone could come from clean [`house`](dags/house_and_listing/ebdb_house_fast_lane/queries/clean/house.sql), which on that seed day ended *later* (10:16).

**[`house_listing`](dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house_listing.sql) (enrich)**: listing-version grain. Finished 02:59 — not the afternoon bottleneck.

## Already upstream (not a win)

Hop 0 already reads **clean** [`listing_business_context`](dags/house_and_listing/ebdb_listing_fast_lane/queries/clean/listing_business_context.sql) (00:22). Enrich [`listing_business_context`](dags/house_and_listing/enrich_ebdb_listing/queries/enrich/listing_business_context.sql) (02:25) would be slower.

## Orchestration / DAG grain

Most hop-2/3 HubSpot, Person, Sorting Hat, Company rows are not in hop-0 SQL. `enrich_listing_deduplication` started ~09:38 after [`supply_events_tracking`](dags/growth/enrich_supply_tracking/queries/enrich/supply_events_tracking.sql) even though [`listing_deduplication`](dags/agents/enrich_listing_deduplication/queries/enrich/listing_deduplication.sql) SQL reads [`conversion_lookup`](dags/growth/enrich_supply_acquisition/queries/enrich/conversion_lookup.sql) (~08:44), not supply events.

## Idle: clock wait (cron)

Hop 0 DAG has `schedule_interval` (America/Sao_Paulo). SQL sources ended hours earlier; hop 0 `latest_ts_started` sits on/after the next cron tick. Lineage will not start the DAG earlier — report as **clock wait**, not a passthrough.

## Idle: split upstream DAG

SQL-needed producer task ended before the idle gap; a sibling on the same producer `id_dag` still overlaps the gap or ends later. Consumer `dependencies.yaml` lists both tasks (dataset AND). Splitting the producer so the needed table’s dataset fires without the long-running rest is an orchestration idea, not a SQL skip.
