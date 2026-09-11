# `base_app_ai_adoption` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.base_app_ai_adoption` |
| **Business owner** | AI Governance |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily roster of active employees (work email, assignment number, layer-1 leader's work email, and direct manager's work email) exported as a single CSV object to the Base44 office bucket for the AI Adoption Portal. |
| **Business purpose** | Feeds the [AI Adoption Portal](https://5a-ai-adoption-portal.base44.app/) — a Base44 app that catalogs available AI tools and automation help for QuintoAndar employees. The roster supplies the current active workforce and each person's vertical leadership (L1) so adoption metrics can be aggregated by top-level organizational vertical. |
| **Business consumer** | AI Adoption Portal ([5a-ai-adoption-portal.base44.app](https://5a-ai-adoption-portal.base44.app/)). POC: victor.fonseca@quintoandar.com.br (AI Governance). |
| **Operational source of truth** | `metric_people.employee_snapshots` (`is_current_for_employee = TRUE`, `status = 'active'`). |
| **Delivery channel** | S3 object **`s3://5a-base44-office/aiadoption/vertical_information.csv`** (prod). Canned ACL `bucket-owner-full-control` on write. Forno redirects to `people_bucket` under `reverse_s3_test/aiadoption/vertical_information.csv` (no partner ACL). |
| **Grain** | One row per active employee assignment on `metric_people.employee_snapshots` with `is_current_for_employee = TRUE` and `status = 'active'`. |
| **Contract notes** | Column order: `email`, `assignment_number`, `email_l1`, `email_manager`. All values lowercase. `email_l1` is the work email of the person at organizational layer 1 (one level below the CEO) in the assignment's reporting chain — not the direct manager; `-1` hierarchy sentinels are exported as empty/null. `email_manager` is `manager_work_email` from `employee_snapshots` — the direct manager's (immediate supervisor's) work email, distinct from `email_l1`. CSV written by Spark (`header=true`, comma separator, UTF-8, empty nulls). No date filters — the export is a full snapshot of the current active roster on each run. |
