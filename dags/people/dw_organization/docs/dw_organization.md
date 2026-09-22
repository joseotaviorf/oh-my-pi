# Organization Reference Data

**Metastore schema:** `dw_organization`

> Organizational reference tables covering cost centers and Codex team data, business units, public job definitions, and Product & Tech neotribe missions: the structural dimensions used to classify and analyze headcount in People Analytics.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/5474320386/People+Data+Catalog).

[Link to Catalog Row](#)

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

**✅ Cost Centers/Teams** : Full attribute history for each cost center/team, including reporting hierarchies, HRBP ownership, Codex-sourced attributes, activity status, and validity periods.

**✅ Business Units** : All business units recognized by the organization. Business units represent local branches within each country legal entity and serve as the legal affiliation reference for employee assignments.

**✅ Jobs** : Public catalog of all job definitions registered in the organization, including job family and career track classification.

**✅ Product & Tech neotribes** : Current-state catalog of Product and Technology neotribes from the team-formation workbook, including planning objective, mission, and scope for each line × neotribe pair. This is a squad-grouping catalog, not a person roster.

### Out of Scope

Closely related topics that live in sibling schemas, not in `dw_organization`:

❌ **Job compensation and bands** : Pay bands, salary ranges, and compensation data associated with jobs are not in this schema. For that, use `dw_compensation`.
❌ **Employee records** : Individual employee data is not part of this schema. For public employee information, use `dw_people`; for detailed and sensitive employee data, use `dw_employee_details`. Person-level Product & Tech team formation (who sits on which squad) lives in `dw_people.dim_product_tech_team`.

## Data Model and Tables

### Data Sources and System Context

* **PIN** : QuintoAndar's internal HR and organizational management system. The primary source for business unit structures, public job definitions, and core cost center/team attributes.
* **SAP/Codex** : Financial and organizational planning system integrated through Codex. The source for cost center/team financial attributes and Codex-specific classification fields.
* **Product & Tech team-formation workbook** : Google Sheet maintained by P&T leadership. The source for neotribe objective, mission, and scope (`dim_product_tech_neotribe`).

### About the data

* **Temporal coverage:** Mixed. `dim_cost_center` preserves the full history of attribute changes (validity window); `dim_business_unit`, `dim_job`, and `dim_product_tech_neotribe` reflect the current state only.
* **Airflow DAG:** `bietlejuice.dw_organization`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `dim_cost_center` | Validity window · One row per cost center/team version (SCD Type 2) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_organization.dim_cost_center,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_organization/queries/dw/dim_cost_center.sql) |
| `dim_business_unit` | Current state · One row per active business unit | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_organization.dim_business_unit,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_organization/queries/dw/dim_business_unit.sql) |
| `dim_job` | Current state · One row per active job | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_organization.dim_job,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_organization/queries/dw/dim_job.sql) |
| `dim_product_tech_neotribe` | Current state · One row per Product & Tech line × neotribe | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.dw_organization.dim_product_tech_neotribe,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/dw_organization/queries/dw/dim_product_tech_neotribe.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `sk_cost_center_version` (Versioned surrogate key for cost center/team versions, FK to fact tables)
* `cost_center_code` (PIN code that uniquely identifies each cost center/team across systems, business key)
* `sk_business_unit` (Surrogate key for business units, FK to fact tables)
* `sk_job` (Surrogate key for jobs, FK to fact tables)
* `sk_product_tech_neotribe` (Surrogate key for the Product & Tech line × neotribe catalog row)

## Core Features and Business Logic

### Domain logic and core concepts

* **Cost Center/Team Versions** : Each time a cost center/team changes its name, hierarchy, HRBP owner, or classification, a new version is created with its own validity period. The `is_current` flag marks the version active as of today.
* **Cost Center/Team Attribute Structure** : Each cost center/team carries two types of attributes. Fixed attributes are derived from the cost center code itself (`structure`, `team`, `business`, `product`, and `brand`) and remain stable within the same code. Variable attributes may change over time and generate a new version when they do: `chapter`, `line`, `owner_l1_name`, `owner_l2_name`, `owner_l3_name`, and `headcount_type`.
* **HRBP Ownership per Period** : Each cost center/team version records the responsible HRBP at the time, enabling accurate attribution of HR partnership even after ownership changed.
* **Business Unit and Employee Assignments** : Each employee assignment is tied to a business unit. When an employee moves to a different business unit, this is recorded as a transfer: a new assignment is created to reflect the change in organizational affiliation.
* **Product & Tech Neotribes** : Each row describes a neotribe's planning objective, mission, and scope for a Product & Technology line. The grain is line × neotribe. This catalog does not list people; person-level P&T squad membership is in `dw_people.dim_product_tech_team`.

## Attention and Limitations

* **Use is_current or time-travel for dim_cost_center** : Without `is_current = TRUE`, queries return all historical versions of each cost center/team and will produce duplicated rows in any headcount join. When analyzing a past period, use `dt_valid_from` and `dt_valid_to` to select the version that was active at the relevant moment instead.
* **L Owner vs individual management hierarchy** : The `owner_l1_name`, `owner_l2_name`, and `owner_l3_name` columns in `dim_cost_center` represent the managers responsible for the cost center/team as an organizational unit. All employees within the same cost center/team share the same L1, L2, and L3 owners. This is different from the L1, L2, and L3 levels in `dw_people` and `dw_employee_details` (e.g., `dim_manager_hierarchy`), which reflect each employee's individual reporting chain. Different employees within the same cost center/team may have different L1, L2, and L3 managers in their personal hierarchy.

## How to Use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Join on `sk_cost_center_version`, `sk_business_unit`, or `sk_job` depending on the dimension needed.
2. Reference `dw_people.dim_employee` for central employee attributes.
3. Always filter `dim_cost_center` on `is_current = TRUE` unless historical analysis is explicitly intended.

### Analytical Snapshot (Cost Centers by Vertical)

**Question:** Which cost centers/teams belong to the tech vertical?

```sql
SELECT
    cost_center_code,
    cost_center_name,
    team,
    chapter,
    is_active
FROM
    dw_organization.dim_cost_center
WHERE
    vertical = 'Tech'
    AND is_current = TRUE
ORDER BY
    cost_center_name
```

### Wide Join (Exploratory Query)

**Question:** How can I see employee data combined with their current cost center/team and business unit?

```sql
SELECT
    fact.sk_employee,
    cc.cost_center_name,
    cc.vertical,
    cc.headcount_type,
    bu.business_unit_name
FROM
    dw_people.fact_employee AS fact
LEFT JOIN dw_organization.dim_cost_center AS cc
    ON fact.sk_cost_center_version = cc.sk_cost_center_version
LEFT JOIN dw_organization.dim_business_unit AS bu
    ON fact.sk_business_unit = bu.sk_business_unit
WHERE
    cc.is_current = TRUE
```

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true.
* **Current State** : The latest, real-time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A database design pattern used to store and manage both current and historical data over time.

## See Also

* **Codex** : The official reference for cost center/team taxonomy and financial attributes is maintained in the [Codex spreadsheet](https://docs.google.com/spreadsheets/d/1-85ApczFAw1B7ZfU59WJ_qwTaYGVmkw8efSa9K9umeA/edit?usp=sharing).
