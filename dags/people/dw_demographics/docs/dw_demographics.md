# DW Demographics - DE&I Data: dw_demographics

## People Data Catalog

**Progress** (status) and **confidence level** for **`dw_demographics`** are maintained in the Confluence People Data Catalog Database—not in this Markdown file.

[Open this schema's catalog row](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/database/4638474284?contentId=4638474284&entryId=a5f75849-69fc-4796-9540-cc6b587ed925&savedViewId=136c293b-f5c1-48d6-a161-9586a403e181).

## Contents

- [People Data Catalog](#people-data-catalog)
- [Description](#description)
- [Scope](#scope)
- [Out of scope](#out-of-scope)
- [Tables](#tables)
- [Data model](#data-model)
- [Full data model on GitHub](#full-data-model-on-github)
- [Executive summary](#executive-summary)
- [Business logic](#business-logic)
- [Data dictionary](#data-dictionary)
- [How to use](#how-to-use)
- [Sensitivity and access](#sensitivity-and-access)

---

## Description

The **`dw_demographics`** schema delivers **DE&I (diversity, equity, and inclusion)** attributes for People analytics: a **time-aware profile** of self-reported and standardized demographic fields, plus **documented disability** detail where it exists in **PIN** (QuintoAndar’s HR master data). It is built for reporting that respects **legislation**, **self-declaration**, and **how values change over time**.

## Scope

**✅ Demographic profile** — Ethnicity, religion, gender identity, sexual orientation, neurodiversity signals, and related inclusion flags, versioned per employee and **legislation** (country/region context), with **current row** and **history** for trends and as-of reporting.

**✅ Documented disability** — Rows for **documented disability records** (categories, status, accessibility needs, quota-related signals where applicable), linked to the same **employee** and **legislation** context as the profile table.

**✅ People in scope** — Active **employees and contractors** on a **current assignment** in PIN; test and non-production accounts are excluded so composition metrics reflect the real workforce.

## Out of scope

**❌ Organization and job catalog** — Cost centers, business units, and job definitions live in **`dw_organization`** (and related enrich sources); join through facts or shared keys, not inside this schema.

**❌ Employment facts and monthly headcount** — Active counts, org slices, and tenure on a **monthly grain** are modeled in **`dw_people`** (for example **`fact_employees`**). Use **`dw_demographics`** as **attributes** joined to those facts; do not treat this schema as the place where headcount is stored.

**❌ Compensation and pay** — Salary, bands, and job history for pay are in **`dw_compensation`**.

**❌ Performance management** — Review cycles and ratings are in **`dw_performance`**.

**❌ Extended HR operational detail** — Contract and assignment detail beyond DE&I attributes may live in **`dw_employee_details`** or **`dw_employee`** depending on the question.

---

## Tables

Explore schemas and column-level detail in **DataHub** (lineage and definitions). Use **Explore in GitHub** to open the matching **`queries/dw/{table}.sql`** on the default branch.

| Table | Explore in DataHub | Explore in GitHub |
|-------|-------------------|-------------------|
| `dim_employee_demographic` | [Open schema](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_demographics.dim_employee_demographic,PROD)/Schema?is_lineage_mode=false&schemaFilter=) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_demographics/queries/dw/dim_employee_demographic.sql) |
| `dim_employee_disability` | [Open schema](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_demographics.dim_employee_disability,PROD)/Schema?is_lineage_mode=false&schemaFilter=) | [View SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_demographics/queries/dw/dim_employee_disability.sql) |

---

## Data model

**Grain**

- **`dim_employee_demographic`:** One row per **employee** per **legislation** per **period** where the DE&I attribute set did not change. When something in that set changes in PIN, a **new** period starts; **earlier** periods remain so you can report **as-of** a past date. Consecutive identical periods are merged into a single row.
- **`dim_employee_disability`:** One row per employee per legislation per **documented disability record** over time. Join to the demographic table on **employee** and **legislation** so disability detail aligns with the same legal context.

### Full data model on GitHub

For a **relationship overview and join patterns** for technical readers, see:

- **Open on GitHub:** [data_model.md on `master`](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_demographics/docs/data_model.md)
- Same folder: [data_model.md](data_model.md)

---

## Executive summary

The **`dw_demographics`** schema supports **DE&I** reporting: a **profile table** with demographic and derived inclusion attributes, plus a **disability detail table** for documented conditions and accessibility context. Data originates from **PIN** and related People data products. Use it for analyses that respect **self-declaration**, **legislation**, and **validity over time** (today’s row vs history).

### Key concepts

- For **today’s profile**, filter **`dim_employee_demographic`** to **`is_current = true`** (or the row whose end date is open-ended).
- **Legislation** groups attributes by legal context (country/region). Some indicators (for example race/ethnicity underrepresentation for Brazil) apply only when legislation is **BR**.
- **Disability** rows are optional: not everyone has rows in **`dim_employee_disability`**. Join when you need taxonomy or medically documented fields.

### Refresh and availability

People warehouse **DW layer SLA**: data is expected to be **available by 8:00** (once per day). This pipeline runs when upstream People data has finished loading.

### Granularity

- **`dim_employee_demographic`:** One row per employee per legislation per **version window** (start/end dates of that attribute set).
- **`dim_employee_disability`:** One row per employee per legislation per **disability record** over its validity period.

### Where to find the data

**Schema:** `dw_demographics` · **Airflow pipeline:** `bietlejuice.dw_demographics`

---

## Business logic

### Who is included

The population is **people with an active employment relationship** in PIN as **employees or contractors**, using the **current assignment** in People data. **Pending hires** and **test accounts** are excluded so metrics reflect real workforce composition.

### Demographic profile (`dim_employee_demographic`)

- Attributes (ethnicity, religion, gender identity, sexual orientation, neurodiversity, and related fields) come from **PIN** legislative and person records, with standardized labels for reporting.
- **History:** When an attribute set changes, a new validity window opens; older windows remain for trend and audit use.
- If legislative data is missing for someone in scope, the pipeline still produces a row with **unknown** codes where applicable so joins do not drop people silently.

### Disability detail (`dim_employee_disability`)

- Rows reflect **documented disability** records in PIN, including status (active/pending/inactive) and quota-related signals where applicable.
- **Primary** disability per person and legislation is flagged when quota information indicates the main record.

**Reporting tip:** For **composition today**, start from **`dim_employee_demographic`** with **`is_current`**, then **left join** **`dim_employee_disability`** only when you need disability breakdowns.

### Terms and column-level rules

Official **definitions of metrics and flags** (for example BIM, LGBT+, URG, PwD) are maintained in **DataHub metadata** on each column — use those descriptions for formulas, null handling, and governance. This avoids duplicating rules that may evolve independently of this page.

---

## Data dictionary

Summary of **business meaning** only. **Authoritative** descriptions, categories, and lineage: **DataHub** (same links as [Tables](#tables)).

## `dw_demographics.dim_employee_demographic`

| Column | Business definition | Notes |
|--------|---------------------|-------|
| `sk_employee` | Internal employee person key for joins across People datasets. | |
| `person_number` | Stable person identifier from HR (PIN). | |
| `legislation_code` | Country/region legal context for the row. | Drives which diversity rules apply. |
| `ethnicity` | Self-declared ethnicity (standardized label). | Unknown mapped for analytics. |
| `religion` | Self-declared religion (standardized label). | |
| `gender_identity_reported` | Value as captured in PIN before standard buckets. | Audit / exact wording. |
| `gender_identity` | Standardized buckets for reporting. | Sensitive personal data. |
| `sexual_orientation` | Self-declared orientation (standardized label). | Sensitive personal data. |
| `is_underrepresented_race` | Brazil-specific underrepresented race/ethnicity signal. | See DataHub for codes and null rules. |
| `is_lgbtqia` | LGBT+ inclusion signal from orientation and gender. | See DataHub for null rules. |
| `is_underrepresented_gender` | Broader gender inclusion flag. | See DataHub vs `is_woman`. |
| `is_woman` | Women signal (cis and trans per mapping). | |
| `is_neurodivergent` | Neurodiversity vs neurotypical where declared. | |
| `has_self_declared_pwd` | Self-declared disability (legislative answer). | |
| `has_medical_disability_record` | Documented disability overlapping the period. | Distinct from self-declaration only. |
| `is_urg` | Composite underrepresented-group flag. | See DataHub for composition. |
| `is_current` | Whether this is the **current** open validity window. | |
| `dt_valid_from` / `dt_valid_to` | Inclusive validity of this attribute set. | Open-ended uses end date sentinel. |
| `ts_load` | When the row was loaded into the warehouse. | |

## `dw_demographics.dim_employee_disability`

| Column | Business definition | Notes |
|--------|---------------------|-------|
| `sk_employee` | Same person key as the demographic table. | Join key. |
| `person_number` | HR person number (PIN). | |
| `legislation_code` | Legal context of the disability record. | Join key. |
| `category` | High-level disability category (standardized label). | |
| `documented_name` | Documented disability type / sub-class label. | |
| `self_declared_name` | Self-declared type or answer when available. | |
| `neurodiversity` | Neurodiversity detail from legislative data. | |
| `accessibility_need` | Declared workplace accessibility need. | |
| `disability_status` | Human-readable status (active, pending, inactive, unknown). | |
| `is_active` | Whether the record is active. | |
| `is_primary` | Primary disability row for that person and legislation when quota indicates. | |
| `is_quota_eligible` | Eligibility signal from quota fields. | |
| `dt_valid_from` / `dt_valid_to` | Validity of the disability record. | |
| `ts_load` | Load timestamp. | |

---

## How to use

This schema holds **dimensions** (attributes and flags), not stored **counts** or **rates**. For **headcount**, **FTE**, or **org-sliced** workforce metrics, join to **`dw_people.fact_employees`** (and org dimensions as needed) on **`sk_employee`**, then attach **`dw_demographics`** for DE&I breakdowns.

**Example questions:**

- What does **DE&I composition** look like **today** (ethnicity, gender identity, URG, LGBT+ flags) for **current** employees?
- How do **documented disability** categories break down among people with a **current** demographic row?
- What was the **as-of** profile for a **past** month (validity windows vs **`fact_employees.dt_reference`**)?
- How do I avoid **double-counting** when a person has **multiple** disability rows?

### Current employee DE&I profile (dimension only)

**Question:** Who are our people **today** with DE&I attributes, without org headcount?

```sql
SELECT
    emp_demographic.sk_employee,
    emp_demographic.person_number,
    emp_demographic.legislation_code,
    emp_demographic.ethnicity,
    emp_demographic.gender_identity,
    emp_demographic.sexual_orientation,
    emp_demographic.is_urg,
    emp_demographic.is_current,
    emp_demographic.dt_valid_from,
    emp_demographic.dt_valid_to
FROM
    dw_demographics.dim_employee_demographic AS emp_demographic
WHERE
    emp_demographic.is_current = TRUE
```

### Demographics with active documented disability rows

**Question:** For **current** demographic rows, who has **active** documented disability lines aligned in time?

```sql
SELECT
    emp_demographic.sk_employee,
    emp_demographic.legislation_code,
    emp_demographic.gender_identity,
    emp_disability.documented_name,
    emp_disability.disability_status,
    emp_disability.is_active
FROM
    dw_demographics.dim_employee_demographic AS emp_demographic
LEFT JOIN
    dw_demographics.dim_employee_disability AS emp_disability
        ON emp_disability.sk_employee = emp_demographic.sk_employee
        AND emp_disability.legislation_code = emp_demographic.legislation_code
        AND emp_disability.dt_valid_from <= emp_demographic.dt_valid_to
        AND emp_disability.dt_valid_to >= emp_demographic.dt_valid_from
WHERE
    emp_demographic.is_current = TRUE
    AND COALESCE(emp_disability.is_active, TRUE)
```

### Headcount by ethnicity (fact + dimension)

**Question:** How many **active** employees **last month** by **ethnicity** (illustrative — align **`dt_reference`** with your reporting month)?

```sql
SELECT
    emp_demographic.ethnicity,
    COUNT(DISTINCT fact_employees.sk_employee) AS employee_count
FROM
    dw_people.fact_employees AS fact_employees
INNER JOIN
    dw_demographics.dim_employee_demographic AS emp_demographic
        ON emp_demographic.sk_employee = fact_employees.sk_employee
        AND emp_demographic.dt_valid_from <= fact_employees.dt_reference
        AND emp_demographic.dt_valid_to >= fact_employees.dt_reference
WHERE
    fact_employees.is_current = TRUE
    AND fact_employees.is_active = TRUE
GROUP BY
    emp_demographic.ethnicity
ORDER BY
    employee_count DESC
```

For an **as-of** historical date, filter validity windows to that date instead of only **`is_current`**.

---

## Sensitivity and access

Gender identity, sexual orientation, ethnicity, religion, and disability are **sensitive** under LGPD and internal policy. Use only in **approved** People analytics contexts and with the access groups granted for this schema. **DataHub** metadata marks classifications and lineage for governance.

Engineering detail (sources, DAG settings) lives in repository **metadata** and declarations — not required for typical business consumption.
