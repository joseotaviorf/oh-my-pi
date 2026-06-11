# Performance

**Metastore schema:** `dw_performance`

> Performance and talent cycle data for QuintoAndar employees — Performa scores, calibration outcomes, talent review assessments, goal achievements, and continuous management practices (Mid-Year Checkpoint, PDI, and One-on-One) — enabling HR teams and business leaders to understand how employees are evaluated, developed, and recognized across every review period.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

[Link to Catalog Row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474582571/Performance)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and Limitations](#attention-and-limitations)
* [How to Use](#how-to-use)
* [Glossary](#glossary)
* [See Also](#see-also)

***

## In Scope

**✅ Performa evaluations** : Self and manager assessments captured during each annual review cycle, covering Impact, Behavior, and Leadership dimensions for every participating employee.

**✅ Calibration results** : Final Performa scores and IPA multipliers produced by committee calibration meetings, including the ratings as they stood before and after each meeting.

**✅ Talent Review assessments** : Multi-dimensional ratings — criticality, potential, readiness, and risk of loss — for every employee assessed in a Talent Review committee, both as submitted by the manager and after calibration.

**✅ Goals (Impact Alignment)** : Individual goal records, achievement percentages, and overall weighted goal result for each employee across every review period and goal plan.

**✅ Data quality flags** : Five smoke-detector signals that surface rating inconsistencies between goal results, self and manager evaluations, and prior-cycle calibration outcomes.

**✅ Continuous management (Check-in)** : Mid-Year Checkpoint, Individual Development Plan (PDI), and One-on-One sessions registered in PIN, including questionnaire responses and manager feedback linked to each check-in meeting.

### Out of Scope

**❌ Employee identity, contact, and org chain** : Preferred name, work email, documents, and reporting hierarchy are in `dw_employee_details` and `dw_people`.

**❌ PLR and compensation calculation** : The Performa IPA multiplier feeds into `dw_compensation.fact_plr_monthly` for the full annual PLR calculation; the monetary outcome and bonus parameters live there.

### Who is included

* **Target Population:** All active employees with an assignment recorded in PIN who have participated in at least one Performa evaluation cycle, Talent Review committee, goal-setting period, or continuous management check-in (Mid-Year Checkpoint, PDI, or One-on-One). Both self and manager evaluation records are included for each completed cycle.
* **Exclusions:** Employees who have not yet been included in any Performa cycle (e.g. new hires admitted after the cycle close date), test and non-production accounts, and pending hires not yet active in PIN.

## Data Model and Tables

### Data Sources and System Context

* **Oracle HCM Cloud (PIN)** : QuintoAndar's HR system of record, integrated via SFTP through Oracle Integration Cloud (OIC). All performance evaluation templates, rating scales, calibration meeting records, talent review assessments, goal plans, check-in meetings, discussion topics, and questionnaire responses originate from Oracle HCM Cloud and flow into the warehouse through this integration.

### About the data

*Note: Detailed definitions for every column, metric, and flag are maintained in DataHub. Do not create a column-level data dictionary section or list individual columns in this markdown document.*

* **Temporal coverage:** Mixed. Evaluation and calibration dimensions carry full history as Validity Windows (SCD Type 2). Variation and rating dimensions are Current State lookup tables. Fact tables store one canonical row per grain event (evaluation, calibration, talent review, goal, check-in meeting, or cycle) rather than historical snapshots.
* **Airflow DAG:** `bietlejuice.dw_performance`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_committee_meeting` | Current state: one record per committee meeting event | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_committee_meeting,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_committee_meeting.sql) |
| `dim_performance_evaluation` | Validity window: one record per evaluation per version (each meaningful rating change opens a new version) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_performance_evaluation,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_performance_evaluation.sql) |
| `dim_performance_calibration` | Validity window: one record per calibration per version | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_performance_calibration,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_performance_calibration.sql) |
| `dim_performance_variation` | Current state: one record per unique combination of Impact, Behavior, and Leadership variation trends (Increased / Maintained / Decreased) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_performance_variation,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_performance_variation.sql) |
| `dim_talent_rating` | Current state: one record per unique combination of criticality, potential, readiness, and risk-of-loss rating levels | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_talent_rating,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_talent_rating.sql) |
| `dim_talent_variation` | Current state: one record per unique combination of talent dimension variation trends | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.dim_talent_variation,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/dim_talent_variation.sql) |
| `fact_performance_evaluations` | One record per assignment per cycle, with manager and self-assessment ratings side by side | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_performance_evaluations,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_performance_evaluations.sql) |
| `fact_performance_calibrations` | One record per person per meeting year — the single canonical calibration result after committee de-duplication | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_performance_calibrations,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_performance_calibrations.sql) |
| `fact_talent_reviews` | One record per assignment per committee meeting | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_talent_reviews,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_talent_reviews.sql) |
| `fact_goal_achievements` | One record per goal (person × review period × goal plan × goal name) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_goal_achievements,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_goal_achievements.sql) |
| `fact_smoke_detectors` | One record per assignment per performance cycle — five data quality flags | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_smoke_detectors,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_smoke_detectors.sql) |
| `fact_continuous_management` | One record per check-in meeting (Mid-Year Checkpoint, PDI, or One-on-One) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_performance.fact_continuous_management,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_performance/queries/dw/fact_continuous_management.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `person_number` (Business key — present in calibration, goal, smoke-detector, and continuous-management facts; use to join to `dw_people.dim_employee`)
* `manager_person_number` (Manager business key — present in continuous-management facts; use to join manager attributes via `dw_people.dim_employee`)
* `review_period_name` (Review cycle label — present in continuous-management facts; e.g. Performa 2025)
* `assignment_number` (Assignment-level grain key — present in evaluation, talent review, and smoke-detector facts)

## Core Features and Business Logic

### Domain logic and core concepts

* **Performa Score** : A weighted numeric score summarizing each employee's calibrated performance. For employees without a leadership role, the formula is 60% Impact + 40% Behavior. For managers, it is 60% Impact + 20% Behavior + 20% Leadership. The result maps to five named bands: Insufficient (below 70), Partially misses expectations (70–89), Meets expectations (90–109), Above expectations (110–137), and Outstanding (138–150).

* **IPA multiplier** : Derived directly from the Performa Score band, this numeric multiplier is used downstream in the annual PLR bonus calculation. Bands map to: Insufficient → 0.00, Partially misses → 0.70, Meets expectations → 1.00, Above expectations → 1.20, Outstanding → 1.50.

* **Calibrated vs. pre-calibration ratings** : Both the manager's initial ratings (before the committee meeting) and the final calibrated ratings (after the meeting) are stored side by side. Comparing the `calibrated_*` and `pre_calibration_*` columns reveals whether a rating was kept, raised, or lowered during calibration.

* **Talent Review dimensions** : Each Talent Review row captures four independent dimensions — Criticality, Potential, Readiness, and Risk of Loss — from both the manager's initial assessment and the committee's calibrated outcome.

* **Regrettable loss** : An employee is flagged as a regrettable loss (`is_regrettable_loss = TRUE`) when the calibrated criticality score marks them as Critical OR the calibrated potential score marks them as High Potential.

* **Goal categories** : Goals are classified as KPI (measured against a minimum / target / maximum numeric range) or Project (a percentage completion score). Achievement is capped at 120% regardless of actual outperformance. The `goal_result` column gives the overall weighted achievement score for the employee across all goals in a review period.

* **Smoke detectors** : Five boolean flags (SD1–SD5) surface data quality inconsistencies: goal score misaligned with manager impact band (SD1); self-vs-manager gap of two or more steps on Impact (SD2) or Behavior (SD3); and drift of two or more steps between the resolved manager rating and the prior-cycle calibrated rating on Impact (SD4) or Behavior (SD5). These flags do not block data from other facts — they are additional quality signals.

* **Continuous management document types** : Each check-in meeting is classified as `mid_year_checkpoint`, `pdi`, `one_on_one`, or `unknown` based on the Oracle check-in template. Mid-Year Checkpoint and PDI are tied to the Performa review period; One-on-One sessions are recurring manager–worker conversations that may include agenda topics and linked notes.

* **Questionnaire vs. discussion content** : Free-text responses from worker and manager questionnaires (career goals, self-awareness, action plans, leader comments) are consolidated in `worker_questionnaire_text` and `manager_questionnaire_text`. For Mid-Year Checkpoint, the manager's evaluation of the employee typically appears in `manager_questionnaire_text` even though the PIN form is labeled under the manager's name. Additional notes attached to One-on-One discussion topics are stored separately in `manager_feedback_text`.

* **Checkpoint completion status** : `checkpoint_status` (`filled`, `in_progress`, `not_started`) is derived from questionnaire answers, discussion topics, and linked notes in the lake. It may differ from the PIN list view label "Discutido com [manager]" when Oracle flags (`is_worker_questionnaire_discussed`, `is_manager_questionnaire_discussed`) remain unset.

### Business Assumptions

* **Calibration meetings lag one calendar year behind the review cycle** : Performa committee meetings for a given review cycle (e.g. cycle year 2024) typically take place in the following calendar year (meeting year 2025). When joining calibration results back to evaluation or goal data by cycle year, account for this offset (meeting_year = cycle_year + 1).

## Attention and Limitations

* **Leadership rating is NULL for non-managerial employees** : The Leadership dimension is only collected for employees in a managerial role. For all other employees, `leadership_*` columns are NULL, and the Performa Score formula automatically switches to the two-dimension weighting (Impact + Behavior). Treat NULL leadership as expected, not as missing data.

* **One canonical calibration row per person per year** : `fact_performance_calibrations` stores a single row per person per meeting year, even when a person appeared in multiple committee meetings. The row selected is the one with the most complete calibrated ratings; ties are broken by the most recent meeting timestamp and then by meeting ID. Queries counting calibration records will therefore produce one row per person per year, never one row per meeting attended.

* **Aggregated questionnaire text** : `worker_questionnaire_text` and `manager_questionnaire_text` concatenate all answers for a meeting into a single string (answers separated by ` | `). Question-level detail is not available in this fact; use clean-layer `pin_questionnaires` tables for per-question analysis.

* **Coverage varies by document type** : PDI and most Mid-Year Checkpoint meetings do not create discussion topics in Oracle; One-on-One sessions are more likely to have agenda topics and linked notes. Absence of discussion topics does not necessarily mean the session was not held in PIN.

## How to Use

### Standard Join Pattern

When joining performance data with other DW domains:

1. Join on `person_number` to reach `dw_people.dim_employee` for employee attributes.
2. Join on `assignment_number` when linking evaluations or talent reviews to assignment-level dimensions.
3. Filter continuous-management facts on `review_period_name` and `document_type` when analyzing a specific Performa cycle or check-in type.

### Continuous Management (Exploratory Query)

**Question:** What share of Mid-Year Checkpoint meetings are marked as filled in a given Performa cycle?

```sql
SELECT
    fact.checkpoint_status,
    COUNT(DISTINCT fact.person_number) AS headcount
FROM
    dw_performance.fact_continuous_management AS fact
WHERE
    fact.document_type = 'mid_year_checkpoint'
    AND fact.review_period_name = 'Performa 2025'
GROUP BY
    fact.checkpoint_status
ORDER BY
    headcount DESC
LIMIT 100
```

### Wide Join (Exploratory Query)

**Question:** What is the distribution of Performa scores across the company in the most recent calibration cycle?

```sql
SELECT
    fact.performa_score,
    COUNT(DISTINCT fact.person_number) AS headcount
FROM
    dw_performance.fact_performance_calibrations AS fact
INNER JOIN dw_performance.dim_committee_meeting AS meeting
    ON fact.sk_committee_meeting = meeting.sk_meeting
WHERE
    meeting.meeting_year = YEAR(CURRENT_DATE()) - 1
GROUP BY
    fact.performa_score
ORDER BY
    headcount DESC
LIMIT 100
```

### Analytical Snapshot (Fact + Employee Dimension)

**Question:** Get a flat view of calibration results with employee identifiers for the most recent cycle.

```sql
SELECT
    emp.person_number,
    fact.performa_score,
    fact.performa_score_numeric,
    fact.performa_ipa,
    fact.calibrated_impact_description,
    fact.calibrated_behavior_description,
    fact.calibrated_leadership_description
FROM
    dw_performance.fact_performance_calibrations AS fact
INNER JOIN dw_people.dim_employee AS emp
    ON fact.person_number = emp.person_number
INNER JOIN dw_performance.dim_committee_meeting AS meeting
    ON fact.sk_committee_meeting = meeting.sk_meeting
WHERE
    meeting.meeting_year = YEAR(CURRENT_DATE()) - 1
    AND emp.is_current = TRUE
LIMIT 100
```

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true.
* **Current State** : The latest, real-time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A design pattern used to store and manage both current and historical data over time.
* **Performa** : QuintoAndar's annual performance review process, comprising self-assessment, manager evaluation, and committee calibration phases.
* **IPA (Individual Performance Assessment)** : The numeric multiplier derived from the Performa Score, used in the annual PLR bonus calculation.
* **Calibration** : The committee review phase where initial manager ratings are reviewed and, when needed, adjusted to ensure consistency across the organization.
* **Continuous management** : Ongoing manager–worker practices in PIN outside the formal Performa evaluation form, including Mid-Year Checkpoint, PDI, and One-on-One sessions.
* **Mid-Year Checkpoint** : Mid-cycle performance conversation between manager and employee, usually including the manager's written assessment of first-semester delivery and second-semester direction.
* **PDI (Individual Development Plan)** : Career development document where the employee records goals, strengths, development areas, and action plans for the review period.
* **One-on-One** : Recurring manager–worker check-in that may include agenda topics and discussion notes.

## See Also

* **[DW Performance](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4702568457/DW+Performance)** : Detailed documentation for the `dw_performance` schema — table-level descriptions, grain, SLA, and DataHub links for every dimension and fact covered in this domain.
* **[Goals](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4642635856/Goals)** : Detailed documentation for goal-setting and achievement data, covering the `fact_goal_achievements` table and the Impact Alignment process.
* **`dw_compensation`** : The PLR fact table in the compensation schema consumes the IPA multiplier produced here. Use `dw_compensation.fact_plr_monthly` when the goal is to analyze the full bonus calculation, including corporate goal factors and eligibility rules.
