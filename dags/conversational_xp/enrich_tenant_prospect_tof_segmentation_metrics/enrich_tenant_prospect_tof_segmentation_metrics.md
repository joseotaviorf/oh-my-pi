## Tenant Prospect ToF Segmentation Metrics

### Purpose

This pipeline builds the **rent** cohort base for tenant prospects (new activations and recoveries) and ToF users, tracks their daily search / LPV / schedule / visit / offer-submission activity in post-activation windows, and publishes segment-level business metrics for top-of-funnel dashboards and experimentation monitoring.

Each run processes the inclusive `start_date` to `end_date` interval (Airflow `load_start_date` and `load_end_date`). A daily schedule uses a one-day interval, while a backfill emits the same daily slices for every date in the requested range. The three output tables are loaded in sequence: cohort base → daily user activity → aggregated segment metrics.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Pipeline overview

```
prospect_daily_results (+ concierge_demand) ──┐
schedule_search_listing_events (ToF users) ───┼──► tenant_prospect_base          ← monthly cohort refresh (merge + delete)
                                              │
                                              ▼
search_impressions, Amplitude LPV/schedule,   │
  rent_flows (visit + offer per id_rent_flow) ─┼──► tenant_prospect_segmentation  ← daily activity slice (merge upsert)
                                              │
                                              ▼
                        tenant_prospect_segment_metrics ← monthly metrics rebuild (partition overwrite)
```

**Post-activation windows** (from activation timestamp):

| Label | Duration                 | Template param   |
| ----- | ------------------------ | ---------------- |
| 4w    | 27 days after activation | `window_4w_days` |
| 8w    | 55 days after activation | `window_8w_days` |

### Update strategy (per table)

#### 1. `datalake_search.tenant_prospect_base`

**What each run does:** Reloads every full calendar month intersecting the input interval from `datalake_demand_flows.prospect_daily_results` (rent conversions: first activation or recovery) and `datalake_amplitude_page_viewed_events.schedule_search_listing_events` (ToF users). ToF `id_user` values are normalized (trim, remove trailing dot, cast to bigint) before deduplication. The query deduplicates to one row per `(id_user, dt_activation_month)` and enriches tenant-prospect conversions with the Concierge flag from `datalake_search.concierge_demand`. Tenant-prospect conversions take precedence when the same user has a ToF event in the same month; otherwise, the earliest event is retained. The `segment_type` column identifies tenant-prospect (`tp`) and ToF (`tof`) cohort members. `is_concierge_prospect` indicates whether a tenant-prospect conversion is linked to a visit booked through Concierge - therefore, in this table, it is always false for ToF users that are not prospects.

**Write method:** Delta **MERGE** on `(id_user, dt_activation_month)`.

- Matching rows are updated.
- New rows are inserted.
- Rows in target activation months intersecting the input interval that are **not** in the new batch are **deleted** (`when_not_matched_by_source_delete_condition`).

This replaces every activation-month cohort touched by the interval. Older months are untouched.

**Grain:** one row per user per activation month.

**Partitions:** `year`, `month`, `day` (derived from `dt_activation_month`, with `day = 1`).

#### 2. `datalake_search.tenant_prospect_segmentation`

**What each run does:** For every date in the inclusive input interval, collects rent activity from search impressions, Amplitude LPV / schedule events, and `datalake_rent_flows.rent_flows` (first visit booking and first offer submission per `id_rent_flow`, including direct offers). Only users whose **8-week post-activation window includes that date** are included (read from `tenant_prospect_base`). Users with no events on a date still get a row with zero counts.

Rent flows are resolved in two steps: (1) candidate flows with any booking or offer event on a date in the load interval, then (2) `MIN(ts_booking_created)`, `MIN(ts_offer_submitted)`, and `MIN(ts_direct_offer_submitted)` across all event rows for each candidate `id_rent_flow`. Visit and offer events are emitted only when that first timestamp falls on `dt_partition` within the load interval.

Each row stores **that day's** activity counts within the tenant's 4w/8w windows (not a running total). The row also retains the tenant activation timestamp and 4w/8w end dates plus daily per-listing event arrays:

- `id_house_partition_spv_ts` stores the first search-result impression per listing; `is_4w` is `1` for 4-week-window activity and `0` otherwise, while `has_lpv` is `1` when any same-day search for that listing matched an LPV and `0` otherwise.
- `id_house_partition_lpv_ts` stores the first LPV timestamp per listing and numeric `is_4w` (`1` for the 4-week window, otherwise `0`).
- `id_house_partition_vb_ts` stores the first visit booking timestamp per listing (`MIN(ts_booking_created)` per `id_rent_flow`) and numeric `is_4w` (`1` for the 4-week window, otherwise `0`).

Window totals for additive metrics are built downstream by summing daily rows. Distinct-listing metrics use the merged arrays and their 4w/LPV flags, while LPV-to-visit metrics compare visit-booking timestamps with the first LPV timestamp for each listing.

**Write method:** Delta **MERGE** on `(dt_partition, dt_activation_month, id_user)`.

- `dt_partition` is each calendar date in the requested interval.
- Re-running an interval overwrites each included daily slice for each user/cohort.

**Grain:** one row per user per activation month per partition date (`dt_partition`).

**Partitions:** `year`, `month`, `day` (derived from `dt_partition`).

**Activity sources:**

| Event type               | Source                                                        |
| ------------------------ | ------------------------------------------------------------- |
| Search impressions       | `datalake_search.search_impressions`                          |
| Listing page views (LPV) | `datalake_amplitude_clean.170698_listing_page_viewed_events`  |
| Schedule page views      | `datalake_amplitude_clean.170698_schedule_page_viewed_events` |
| Visit bookings           | `datalake_rent_flows.rent_flows` (`MIN(ts_booking_created)` per `id_rent_flow`) |
| Offer submissions        | `datalake_rent_flows.rent_flows` (`COALESCE(MIN(ts_offer_submitted), MIN(ts_direct_offer_submitted))` per `id_rent_flow`) |

#### 3. `datalake_search.tenant_prospect_segment_metrics`

**What each run does:**

1. Finds activation months (`dt_activation_month`) that received a new `dt_partition` row in the requested interval in `tenant_prospect_segmentation`.
2. For those months, **sums all daily segmentation rows** per user to get full-window activity totals and merges daily listing arrays.
3. Derives the number of distinct listings with an LPV followed by a visit booking, separately for the 4w and 8w windows.
4. Assigns each user to an activity **segment** (separately for 4w and 8w windows).
5. Computes cohort- and segment-level metrics separately for each Concierge-prospect status, then pivots them into long format (`metric` + value per segment column).

**Write method:** **Partition overwrite** on `(year, month, day)` where partition values come from `dt_activation_month` (always day 1 of the activation month). Only activation months affected by the requested interval are written; existing data for other months is preserved.

Requires `spark.sql.sources.partitionOverwriteMode = dynamic` (configured on the cluster).

**Grain:** one row per activation month × business context × tenant-prospect segment type (`segment_type`) × Concierge-prospect status (`is_concierge_prospect`) × cohort window (`4w` / `8w`) × metric name.

### Activity segments

Segments are derived from cumulative search **interactions** (distinct search impression timestamps), LPVs, and schedule page views after summing daily segmentation rows.

| Segment                   | 8w / 4w rule                                        |
| ------------------------- | --------------------------------------------------- |
| `qualified_search_active` | More than 10 search interactions                    |
| `low_search_active`       | 1–10 search interactions                            |
| `active_no_search`        | 0 search interactions, but ≥ 1 LPV or schedule view |
| `inactive`                | No search interactions, LPVs, or schedule views     |

The `overall` column in `tenant_prospect_segment_metrics` holds cohort-wide metrics (e.g. `search_participation_rate`, `discovery_rate`, `bes`). `bes` is the share of tenant prospects in the cohort who have at least three first visit bookings per rent flow, or at least one first visit booking after a first offer submission per rent flow, within the applicable 4w or 8w window.


### Sync checklist (when updating sale sibling DAG)

When changing logic in `enrich_buyer_prospect_tof_segmentation_metrics`, review whether the same change applies here:

- Cohort base dedup, ToF union, ToF id normalization, and Concierge join logic
- Daily activity aggregation; rent-flow visit/offer sourcing (`sale_flow` vs `rent_flows`)
- Segment thresholds and BES definition
- Metric pivot columns in segment_metrics

### Outputs

This pipeline produces the following output tables on the enrich layer (`datalake_search`):

| Table                            | Role                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------ |
| `tenant_prospect_base`            | Cohort spine: activation timestamp, `tp`/`tof` segment type, 4w/8w window ends, and Concierge flag |
| `tenant_prospect_segmentation`    | Daily activity counts, offer-submission flags, cohort-window boundaries, and per-listing SPV/LPV/visit event arrays |
| `tenant_prospect_segment_metrics` | Pivoted segment metrics by tenant-prospect segment type, including distinct-listing and LPV-to-visit measures |

</details>
