# `comp_employee_roster` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.comp_employee_roster` |
| **Business owner** | Talent Review — pedro.teixeira@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily active-employee roster with Performa and Talent Review ratings for the Comp compensation platform. |
| **Business purpose** | Feeds the Comp (comp.vc) inbound integration with one row per active assignment. Derived from `reverse_reports.talent_review_performa_base` with hierarchy display names and duplicate tenure columns removed so Comp can resolve manager/HRBP/L1–L4 attributes via `assignment_number` self-joins. |
| **Business consumer** | Talent Review + Comp (comp.vc platform) |
| **Operational source of truth** | `metric_people.employee_snapshots` (active current primary assignments); `dw_compensation.fact_compensations` (tenure); `dw_performance.fact_performance_calibrations` + `dim_cycle_period`; `dw_performance.fact_talent_reviews` + `dim_talent_rating`; `dw_organization.dim_cost_center`; `dw_employee_details.fact_assignment_snapshots` (HRBP assignment number). |
| **Delivery channel** | Comp S3 Access Point **`quintoandar-inbound-wikpng8fowgxahxxccrd8j6ogxydnuse2a-s3alias`** (us-east-2). Layout: `s3a://{alias}/quintoandar/comp_employee_roster/year=YYYY/month=M/day=D/part-*.parquet`. Parquet with ZSTD compression; daily full snapshot; no canned ACL and no custom encryption headers (Comp bucket policy). The reverse_s3 EMR cluster pins `fs.s3a.bucket.{alias}.endpoint.region=us-east-2` and clears canned ACL for that alias only. Forno redirects to `people_bucket` under `reverse_s3_test/quintoandar/comp_employee_roster/`. |
| **Grain** | One row per active current primary assignment (`employee_snapshots.is_current_for_employee`, `is_primary_assignment_for_snapshot`, `is_active`, `status = active`). |
| **Contract notes** | Columns intentionally omitted vs `talent_review_performa_base`: `months_tenure_in_*_years` (duplicate month columns), `manager_name`, `hrbp_name`, `l1_name`–`l4_name` (derivable from `manager_assignment_number`, `hrbp_assignment_number`, `assignment_number_l1`–`l4`), `elegivel` (calculated from `band` + `months_tenure_in_company`). Talent Review pivots use calibrated ratings (`is_latest_for_employee_in_cycle`) for `Talent Review 2026 Q1`, `2025 H2`, and `2025 H1`. `performa_score` = current calibration cycle (`dim_cycle_period.is_current`). `performa_score`, Talent Review ratings, and `last_raise_*` are attached only when `dt_employee_hired` is on or before the cycle `dt_valid_from` (or the raise date), so a rehire does not inherit Performa, criticality, or recognition from a prior period of service. Partition columns `year`/`month`/`day` come from `{load_start_date}`. |
