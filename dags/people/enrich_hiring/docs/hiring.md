# Hiring

**Metastore schema:** `datalake_hiring`

> Provider-agnostic pipeline for Talent Acquisition data, consolidating job openings, candidate applications, and hiring demographics from the ATS into a unified enrich layer ready for analysis and future DW consumption.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)

***

## In Scope

**✅ Job Openings** : Individual headcount requisitions — each open or closed position tracked in the ATS, including status, cost center, recruitment strategy, and compensation details.

**✅ On-Hold Tracking** : Full history of "On Hold" events per job opening — each suspension period with its start date, end date, and duration, enabling SLA and freeze-period analysis.

**✅ Candidate Demographics** : Voluntary demographic answers collected from candidates during the hiring process, including minority group flags for diversity analysis at the pipeline level.

### Out of Scope

**❌ Employee DE&I (`dw_demographics`)** : Demographic data for employees already hired and present in the people system. Candidate-level demographics in this schema cover the full application pipeline and are not limited to hired individuals.

**❌ Employee lifecycle (`dw_employee_details`)** : Post-hire data — org structure, compensation, and headcount management live in the People DW schema, not here.

### Who is included

* **Target Population:** All job openings and candidates who applied to any position tracked in the Applicant Tracking System — including active candidates in open pipelines, candidates from historically closed requisitions, and all demographic responses voluntarily submitted during the application process, regardless of the final hiring outcome.
* **Exclusions:** Post-hire employee records are not in scope. Once a candidate is hired, their data transitions to the people system. Applications or openings created for ATS configuration or testing purposes may be present but do not represent real hiring activity.

## Data Model and Tables

### Data Sources and System Context

* **Greenhouse** : The primary Applicant Tracking System used for managing job openings, candidate pipelines, interview scheduling, and offers.

* **Workable** : A legacy ATS used prior to the full adoption of Greenhouse. Until a consolidated DW for hiring is available, some older records may be absent from Greenhouse and present only in Workable.

### About the data

*Note: Detailed definitions for every column, metric, and flag are maintained in DataHub. Do not create a column-level data dictionary in this document.*

* **Temporal coverage:** Mixed — job openings and candidate demographics reflect the **current state** (latest version only); on-hold events are recorded at the **event level**, preserving the full history of each suspension period.
* **Airflow DAG:** `bietlejuice.enrich_hiring`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `hiring.demographics` | Current state — one row per application, with all demographic answers pivoted into columns | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_hiring.demographics,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_hiring/queries/enrich/demographics.sql) |
| `hiring.job_openings` | Current state — one row per individual headcount requisition | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_hiring.job_openings,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_hiring/queries/enrich/job_openings.sql) |
| `hiring.job_opening_on_hold` | Event level — one row per "On Hold" period for each job opening | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_hiring.job_opening_on_hold,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_hiring/queries/enrich/job_opening_on_hold.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

### Additional Available Layers

Beyond the enrich-ready tables above, more granular data is available in the Greenhouse clean schemas for advanced analyses:

* **`datalake_greenhouse_v3_clean`** — 27 tables from the Greenhouse API, including applications, candidates, jobs, openings, offers, interviews, scorecards, and demographic question sets.
* **`datalake_greenhouse_audit_log_clean`** — Audit log events tracking field-level changes to Greenhouse records over time; primary source for on-hold period reconstruction in `hiring.job_opening_on_hold`.

* `id_opening` — primary key for job openings; links `hiring.job_openings` with `hiring.job_opening_on_hold`
* `id_application` — primary key for candidate applications; primary key for `hiring.demographics`

### Future DW Roadmap

> This schema (`datalake_hiring`) currently represents the **enrich layer** for the Hiring domain. A dedicated Data Warehouse schema (`dw_hiring`) is planned for a future development cycle, following Kimball dimensional modeling conventions consistent with the rest of the People DW. Until `dw_hiring` is created, analyses should consume the enrich tables above directly.
