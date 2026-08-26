# `allocationtool_org_roster` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.allocationtool_org_roster` |
| **Business owner** | People Insights |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Active-employee org / management-hierarchy roster exported as a single CSV object under `allocationtool/import/` for the Allocation Tool app to pull from. |
| **Business purpose** | Feeds Allocation Tool's import step with the same active-employee org/gestor base already scheduled to Google Sheets from `reverse_reports.public_information`, trimmed to the columns Allocation Tool actually consumes: identity (`matricula`, `nome`, `email`, `gestor`, `cargo`), org structure (`vertical`/`structure`/`team`/`chapter`), the `l0_gestor`–`l8_gestor` management chain, `fl_lider`, and `ts_load`. |
| **Business consumer** | Allocation Tool app ([resource-allocation-tool-a1c1e997.base44.app](https://resource-allocation-tool-a1c1e997.base44.app/)). |
| **Operational source of truth** | `metric_people.employee_snapshots` (same wide roster table as `base_app_org_health`), instead of joining the raw `dw_employee_details`/`dw_compensation`/`dw_organization` tables directly like `reverse_reports.public_information` does. |
| **Delivery channel** | S3 object **`s3://5a-base44-office/allocationtool/import/public_info.csv`** (prod) — same shared bucket as `base_app_org_health` / `base_app_ai_adoption`. Forno redirects to `people_bucket` under `reverse_s3_test/allocationtool/import/public_info.csv`. |
| **Grain** | One row per active employee assignment (`fact_assignment_snapshots.is_current_for_employee = TRUE`, not terminated), excluding `@ext.` external contractor emails. |
