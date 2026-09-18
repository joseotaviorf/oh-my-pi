# Spark-job review backlog — cluster right-sizing flags

**Status:** planning backlog, to be worked separately from the recommender rollout.
**Source:** `scripts/recommend_cluster_specs.py` `review_flags` (14-day ARM window, generated 2026-06-11).
Regenerate the tables by re-running the recommender; the flags are emitted in
`recommendations.csv` (`review_flags` column).
**How to analyze each DAG:** `docs/platform/cluster_rightsizing_low_cpu_dag_analysis.md`
(step-by-step playbook with verdict taxonomy and worked examples).

These DAGs have pathological worker-utilization shapes that right-sizing alone
cannot fix. The recommender still right-sizes them where safe (see the cohort
column), but each one needs a Spark-job / SQL-level fix to stop wasting the
cluster in the first place.

## Cohort A — `io_scan_review` (16 DAGs)

Workers spend the wall waiting on I/O (`wrk_wait_p95` > 40%) with a low CPU
base (`wrk_cpu_p50` < 25%): small-file S3 scans, unpruned partition reads, or
skewed shuffles. Typical fixes, in order of observed payoff:

1. **Partition pruning** — push `hour`/`year/month/day` filters into the query
   (e.g. `dw_repairs` scans y/m/d-partitioned ticket tables without pushing
   those partition columns into the predicates).
2. **Upstream compaction** — enable `run_optimize` on upstream tables emitting
   many small Parquet files (e.g. `amplitude_subpartitioned` feeds
   `enrich_search` with `run_optimize: false` on the search event tables).
3. **Ingestion batching** — replace per-file listing + `spark.read.json(file_list)`
   loops with coarser reads (e.g. `langfuse` boto3-lists the whole export bucket
   hourly; `house_listing_search` `dbutils.fs.ls`-walks gzip-JSON CDC landing
   per day across 7 tables x 3 layers).
4. **Skew handling** — AQE skew-join / repartition before high-cardinality
   partition shuffles (e.g. `amplitude_new`: ~20k `event_type` partitions with
   heavy skew; local NVMe does not help because nothing spills).

Photon on these DAGs is suspected to act as an S3-download accelerator rather
than a query engine win (its C++ reader masks the scan cost at ~3x DBU). When a
DAG here runs Photon, validate the drop with a shadow run before removing.

| DAG | workers | n | cpu p50 | cpu p95 | io-wait p95 | wall p50 | cost 14d | Photon | recommender cohort |
|---|---|---|---|---|---|---|---|---|---|
| enrich_search | m6gd.4xlarge | 4 | 17.9% | 76.3% | 67.4% | 95.9m | $125 | yes | right_size_multi |
| dw_datamarts_growth_cross | m6g.8xlarge | 3 | 19.8% | 79.2% | 68.5% | 137.1m | $59 |  | right_size_multi |
| enrich_chatbot | r6g.4xlarge | 6 | 13.8% | 67.8% | 67.8% | 22.7m | $33 |  | keep_multi_memory |
| house_listing_search | r6g.4xlarge | 3 | 17.1% | 70.4% | 55.2% | 68.1m | $31 |  | right_size_multi |
| dw_repairs | r6g.4xlarge | 4 | 9.8% | 80.1% | 64.9% | 28.9m | $11 |  | right_size_multi |
| enrich_amplitude_agents_app | r6g.4xlarge | 3 | 22.1% | 98.4% | 63.5% | 30.3m | $7 |  | keep_multi_cost |
| enrich_braze_events_dispatches | r6gd.xlarge | 2 | 23.5% | 61.8% | 64.4% | 42.5m | $6 | yes | right_size_multi |
| enrich_invoice | c6g.4xlarge | 3 | 19.4% | 72.0% | 57.0% | 23.6m | $5 |  | right_size_multi |
| enrich_online_attribution | m6gd.4xlarge | 3 | 20.2% | 84.3% | 68.1% | 47.3m | $3 | yes | recent_config_change |
| enrich_ebdb_contract | c6g.8xlarge | 2 | 9.6% | 50.2% | 62.7% | 12.2m | $3 |  | right_size_multi |
| enrich_firestore | m6g.4xlarge | 3 | 19.7% | 92.0% | 40.5% | 13.7m | $3 |  | right_size_multi |
| enrich_amplitude_visit | c6g.2xlarge | 3 | 12.0% | 35.1% | 72.0% | 53.2m | $3 |  | right_size_multi |
| enrich_agent_accreditation | m6g.2xlarge | 2 | 15.4% | 90.8% | 55.3% | 16.3m | $2 |  | right_size_multi |
| enrich_ebdb_affiliates_cost | m6gd.xlarge | 3 | 21.4% | 53.8% | 41.8% | 12.8m | $1 | yes | right_size_multi |
| dw_smart_price | c6g.2xlarge | 3 | 22.7% | 57.8% | 63.9% | 23.2m | $1 |  | right_size_multi |
| enrich_rent_listings_lenses | c6g.2xlarge | 3 | 19.8% | 80.4% | 59.0% | 18.2m | $1 |  | right_size_multi |

## Cohort B — `driver_bound_review` (26 DAGs)

Workers are idle (`wrk_cpu_p50` < 5%) with near-zero I/O wait (`wrk_wait_p95`
< 10%): the driver does the real work (REST pagination, collect-heavy logic)
while workers burn money waiting for the final materialization burst. The
cluster shape is wrong in kind, not in size:

- Collapse to a right-sized single node (the recommender already proposes this
  where the cost model allows), or
- Move the API extraction off Spark entirely (plain Python task) and keep a
  small cluster only for the materialization step (e.g. `greenhouse_v3`: the
  driver serially paginates the Greenhouse Harvest API across 27 tables while
  3x r6g.4xlarge workers idle).

| DAG | workers | n | cpu p50 | cpu p95 | io-wait p95 | wall p50 | cost 14d | Photon | recommender cohort |
|---|---|---|---|---|---|---|---|---|---|
| batch_inference | m6g.8xlarge | 4 | 0.5% | 3.5% | 0.1% | 70.5m | $52 |  | right_size_multi |
| greenhouse_v3 | r6g.2xlarge | 3 | 2.2% | 55.0% | 1.2% | 57.3m | $29 |  | right_size_multi |
| inspection_services | m6g.2xlarge | 3 | 4.0% | 54.5% | 0.8% | 49.5m | $24 |  | right_size_multi |
| enrich_visit | c6g.12xlarge | 8 | 3.7% | 66.2% | 5.4% | 18.9m | $23 |  | right_size_multi |
| hr_system | r6g.2xlarge | 3 | 2.0% | 24.8% | 0.7% | 81.8m | $21 |  | right_size_multi |
| enrich_spark_event_logs | c6g.2xlarge | 2 | 4.5% | 21.2% | 2.9% | 39.8m | $16 |  | collapse_to_single |
| metric_fintech__collections_segmentation | r6g.8xlarge | 6 | 1.9% | 83.0% | 3.1% | 10.4m | $15 |  | right_size_multi |
| rental_transact | m6g.2xlarge | 3 | 3.8% | 50.9% | 0.7% | 51.3m | $14 |  | right_size_multi |
| internal_chat | m6g.2xlarge | 3 | 2.0% | 15.1% | 0.1% | 80.0m | $13 |  | right_size_multi |
| reverse_birdie_access | m6g.2xlarge | 3 | 2.0% | 17.8% | 0.8% | 56.8m | $10 |  | right_size_multi |
| enrich_landlord_journey | m6gd.4xlarge | 4 | 3.6% | 58.1% | 4.2% | 13.0m | $10 | yes | right_size_multi |
| heimdall | r6g.2xlarge | 3 | 2.5% | 37.6% | 7.1% | 22.4m | $9 |  | right_size_multi |
| braze_events | r6g.xlarge | 2 | 3.9% | 29.0% | 0.3% | 130.6m | $9 |  | collapse_to_single |
| dw_listing | m6gd.4xlarge | 3 | 4.8% | 99.1% | 6.0% | 14.7m | $8 | yes | right_size_multi |
| sauron | c6g.4xlarge | 3 | 1.6% | 31.4% | 1.4% | 28.5m | $7 |  | right_size_multi |
| google_analytics_classified | r6g.4xlarge | 5 | 3.5% | 16.2% | 2.1% | 22.1m | $6 |  | right_size_multi |
| collections_score_batch_inference | m6g.8xlarge | 4 | 2.7% | 6.1% | 3.5% | 9.4m | $6 |  | right_size_multi |
| enrich_rent_flows | m6gd.4xlarge | 3 | 2.1% | 64.9% | 3.4% | 11.1m | $5 | yes | right_size_multi |
| firestore | r6g.2xlarge | 2 | 3.0% | 30.3% | 7.2% | 19.6m | $5 |  | right_size_multi |
| enrich_atlas_db_quality_metrics | r6gd.4xlarge | 3 | 2.3% | 11.1% | 6.1% | 9.1m | $4 | yes | right_size_multi |
| enrich_seo_funnel | r6gd.4xlarge | 3 | 3.2% | 18.3% | 6.1% | 10.5m | $3 | yes | right_size_multi |
| enrich_content_funnel | r6gd.4xlarge | 3 | 3.8% | 14.4% | 6.0% | 10.7m | $3 | yes | right_size_multi |
| reverse_webhelp_access | m6g.2xlarge | 3 | 3.9% | 45.7% | 5.2% | 15.3m | $3 |  | right_size_multi |
| openapi | m6g.2xlarge | 2 | 3.5% | 31.4% | 2.6% | 15.6m | $2 |  | right_size_multi |
| enrich_proposal | m6g.4xlarge | 2 | 3.5% | 82.7% | 2.9% | 11.0m | $2 |  | right_size_multi |
| enrich_nps_quintocred | m6g.xlarge | 2 | 4.9% | 88.6% | 9.8% | 16.7m | $1 |  | right_size_multi |

## Deep-dive verdicts (2026-06-11 code inspection)

| DAG | verdict | evidence |
|---|---|---|
| langfuse | io_scan (ingestion batching) | boto3 recursive bucket listing + `spark.read.json(file_list)` over many small exports; driver-bound REST enrichment with rate-limit sleeps |
| house_listing_search | io_scan (CDC landing) | per-day `dbutils.fs.ls` over gzip-JSON Debezium landing; y/m/d/h output partitions; 7 tables x 3 layers serially |
| enrich_search | io_scan (upstream compaction) | upstream `run_optimize: false` -> small Parquet files; full daily rebuild, `year >= 2021` pruning only; Photon ON |
| dw_repairs | io_scan (partition pruning) | unpruned scans of y/m/d tables (`fact_ticket_events`, `ticket_comments` full scan); 6+ window dedups |
| greenhouse_v3 | driver_bound | driver paginates Greenhouse API; workers idle; p95 burst is the final JSON materialization |
| enrich_visit | cpu_ok (bursty shuffle) | pure Delta SQL window/non-equi joins; no pathology; safe to shrink via cpu_eff |
| dw_listing | cpu_ok (bursty shuffle) | pure Delta SQL; p95 bursts from wide joins; safe to shrink via cpu_eff |

## Out of scope (tracked separately)

- `facebook_insights_*` validation wall blowups: runs sat queued without
  starting the job; infrastructure issue under separate investigation.
- `amplitude_new`: revert r6gd NVMe workers (no spill, NVMe is dead weight);
  real fix is the `event_type` shuffle skew. Owner: platform.
