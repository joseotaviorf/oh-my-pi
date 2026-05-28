# Learning

**Metastore schema:** `datalake_learning`

> Learning consolidates training activity from Degreed (Learning Hub) — QuintoAndar's internal learning platform — giving People Analytics teams a single place to track course completions, pathway progress, and skill plan adherence across the organization.

## People Data Catalog

This schema is indexed in the [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog).

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)

***

## In Scope

**✅ Content Completions** : Individual completion records for every learning item a user has finished, including when and how they completed it.

**✅ Pathway Structure** : The full hierarchy of Degreed pathways — sections, lessons, and their content items — enabling structural and progress reporting.

**✅ Skill Plan Completion** : Per-user progress against organizational Skill Plans, which group pathways into unified compliance or development programs.

**✅ User Identity Mapping** : A bridge linking Degreed user identifiers to internal corporate identifiers (work email and person number).

### Out of Scope

**❌ Performance Reviews** : Goal setting, performance ratings, and review cycles are covered under the Organization and Performance schemas.

**❌ Compensation and Benefits** : Pay, salary ranges, and benefit data belong to the Compensation schema.

### Who is included

* **Target Population:** All users registered in Degreed (Learning Hub) with at least one activity record — completions, pathway enrolments, or skill plan assignments. Former employees with prior learning activity are included; this schema does not filter by current employment status.
* **Exclusions:** Degreed accounts that could not be matched to an internal employee identifier have no person number and cannot be linked to other People schemas.

## Data Model and Tables

### Data Sources and System Context

* **Degreed (Learning Hub)** : QuintoAndar's primary learning platform, used for assigning and tracking mandatory regulatory training, onboarding pathways, and voluntary development content. Degreed structures content into a four-level hierarchy: Pathway → Section → Lesson → Content item. Completion of all mandatory content items in a pathway drives the pathway completion percentage (0–100 %). Skill Plans group multiple pathways into a single compliance or development program.

### About the data

*Detailed definitions for every column, metric, and flag are maintained in DataHub. Do not look for a column-level data dictionary in this document — use DataHub for that.*

* **Temporal coverage:** Mixed — `content_completions` stores a full event history of completions; `all_completions` and `plan_completions` hold aggregated current-state progress per user per object; structural tables (`sections`, `lessons`, `lesson_contents`, `plan_pathways`) reflect current pathway and plan configuration.
* **Airflow DAG:** `bietlejuice.enrich_learning`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `content_completions` | Event level — one row per completion event per (user, content item) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.content_completions,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/content_completions.sql) |
| `all_completions` | Aggregated snapshot — one row per (user, learning object) with progress counts and percentages across the Pathway / Section / Lesson / Content hierarchy | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.all_completions,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/all_completions.sql) |
| `lesson_contents` | Current state — one row per content item placement within a lesson (bridge: lesson ↔ content, with requirement type and sequence) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.lesson_contents,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/lesson_contents.sql) |
| `lessons` | Current state — one row per lesson within a pathway section | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.lessons,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/lessons.sql) |
| `sections` | Current state — one row per section within a pathway | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.sections,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/sections.sql) |
| `plan_pathways` | Current state — one row per (skill plan, pathway) association | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.plan_pathways,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/plan_pathways.sql) |
| `plan_completions` | Aggregated snapshot — one row per (user, skill plan) with pathway completion count and overall plan completion status | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.plan_completions,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/plan_completions.sql) |
| `user_identifier_mapping` | Current state — one row per Degreed user, mapping `id_user` to `work_email` and `person_number` | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_learning.user_identifier_mapping,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/enrich_learning/queries/enrich/user_identifier_mapping.sql) |

> **Note:** VPN connection is required to access DataHub.

### Source Layer (`datalake_degreed_clean`)

The tables above are built from a structured clean layer that normalises the Degreed API responses. Analysts who need raw Degreed objects — such as the full content catalog, user profiles, or group membership — should query this schema directly.

* **Airflow DAG:** `bietlejuice.degreed`
* **SLA:** D-1 available by 08:00 BRT

| Table | Grain | Links |
| :--- | :--- | :--- |
| `completions` | Event level — one row per completion record (deduplicated by id) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.completions,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/completions.sql) |
| `users` | Current state — one row per Degreed user account | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.users,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/users.sql) |
| `pathways` | Current state — one row per learning pathway | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.pathways,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/pathways.sql) |
| `pathway_details` | Current state — one row per pathway with full nested structure (sections, lessons, resources) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.pathway_details,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/pathway_details.sql) |
| `skill_plans` | Current state — one row per skill plan | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.skill_plans,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/skill_plans.sql) |
| `skill_plan_details` | Current state — one row per skill plan with full nested structure (sections, resources) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.skill_plan_details,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/skill_plan_details.sql) |
| `contents` | Current state — one row per content item in the Degreed catalog (articles, videos, courses, books) | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.contents,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/contents.sql) |
| `groups` | Current state — one row per collaborative group | [DataHub](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.datalake_degreed_clean.groups,PROD)/Schema) · [SQL](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/degreed/queries/clean/groups.sql) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `id_user` (Degreed user key — join anchor across all learning tables)
* `person_number` (Internal employee identifier — use `user_identifier_mapping` to bridge to People DW dimensions)

---

> **Future Roadmap — dw_learning**
>
> The tables above represent the current state of the Learning data: a structured enrich layer sourced directly from Degreed. A dedicated dimensional schema (`dw_learning`) is planned for future development. That schema will expose Learning data through standard Kimball-style fact and dimension tables, enable direct joins with `dw_people.dim_employee` via `sk_employee`, and support advanced compliance and training analytics. Until that schema is delivered, analysts should join to People dimensions via `user_identifier_mapping.person_number`.
