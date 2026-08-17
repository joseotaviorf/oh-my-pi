# `talent_review_performa_base` — reverse export governance


| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.talent_review_performa_base` |
| **Business owner** | pedro.teixeira@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Active employee base with Performa score, tenure, org context, and Talent Review rating pivots for the Talent Review Looker dashboard. |
| **Business purpose** | Feeds the Talent Review Looker Studio dashboard (`base` tab) with one row per active assignment: latest Performa calibration score, merit/promotion raise history, HRBP assignment, and calibrated Talent Review dimensions pivoted by committee meeting date (TR Q1/26, Q3/25, Q1/25). |
| **Business consumer** | Talent Review Looker dashboard — [Looker Studio](https://lookerstudio.google.com/reporting/dd5718b9-c5e8-4841-8869-a6aa7622bd9b) |
| **Operational source of truth** | `dw_employee_details.fact_assignment_snapshots` (active current assignments); `dw_employee_details.dim_employee`, `dim_management_hierarchy`; `dw_compensation.dim_job`, `fact_compensations` (current tenure + last merit/promotion raise); `dw_performance.fact_performance_calibrations` + `dim_cycle_period` (`performa_score` from the current calibration cycle via `is_current`, replaces legacy `datalake_people_analytics_sandbox.performance_review`); `dw_performance.fact_talent_reviews` + `dim_talent_rating` (official in-cycle review via `is_latest_for_employee_in_cycle`, joined on `person_number`); `dw_organization.dim_cost_center`; `metric_people.employee_snapshots` (`country`). |
| **Delivery channel** | Google Sheets tab **base** in workbook https://docs.google.com/spreadsheets/d/15ffVBTOETsHI_Xp2KIEwMqec7A1OOkg4vL-D37JcCZQ. Service account editor: `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`. |
| **Contract notes** | Legacy English column names preserved (`assignment_number`, `tr_q1_26_potential`, `elegivel`, etc.). Grain: one row per active current assignment (`is_current_for_employee`, `is_active`, `employment_status = Active`). Tenure comes from `fact_compensations` via `fact.sk_compensation_version` (not `is_current` on employee). Talent Review pivots join `dim_cycle_period.cycle_name` and keep only `is_latest_for_employee_in_cycle` (same pattern as `employee_snapshots`) on `person_number` — sheet labels Q1/25 and Q3/25 map to `Talent Review 2025 H1` / `H2`; Q1/26 maps to `Talent Review 2026 Q1`. `performa_score` = current calibration cycle (`dim_cycle_period.is_current`). `last_raise` excludes future-dated merit/promotion rows (`dt_valid_from <= load date`). `elegivel` uses `TRY_CAST(band AS INT) >= 6` (`dim_job.band` is string-typed). |
