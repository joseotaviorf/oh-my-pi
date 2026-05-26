# {readable_doc_title}

**Metastore schema:** `{metastore_schema}`

> {Elevator pitch: one or two sentences on what this dataset delivers and for whom. Use product names like PIN.}

## {data_catalog_name}

This schema is indexed in the [{data_catalog_name}]({data_catalog_url}).
[Link to Catalog Row](url-to-row)

## Contents

* [In Scope](#in-scope)
* [Data Model and Tables](#data-model-and-tables)
* [Core Features and Business Logic](#core-features-and-business-logic)
* [Attention and limitations](#attention-and-limitations)
* [How to use](#how-to-use)
* [Glossary](#glossary)
* [Related Scopes](#related-scopes) *{optional : remove if unused}*

***

## In Scope

**✅ {Topic}** : {Short explanation}
**✅ {Topic}** : {Short explanation}

### Who is included

* **Target Population:** {State who IS included using strictly affirmative, positive statements in natural business language. E.g. All active records in the domain. Do NOT reference table names, database schemas, or technical SQL filters.}
* **Exclusions:** {State who IS NOT included using simple, negative statements. E.g. Inactive or test accounts. Avoid double negatives and do NOT reference technical field codes or database objects.}

### Future scope (Roadmap) *(Optional)*

*{Note: Delete this section if there is no planned roadmap or known gaps to be addressed in the future.}*

* **⏳ {Extension}** : {Brief gap description}

## Data Model and Tables

### Data Sources and System Context

*{Provide a high level business context of the original source systems or tools of origin for this data (e.g. PIN, Workday, Greenhouse). Make sure to list **every single** source system utilized. Crucial: Do NOT reference intermediate lake or enrichment tables, such as enrich_people or identifier_mapping, as they are technical implementation details, not original business sources. Do NOT describe engineering data transformations or cleansing processes like deduplication.}*

* **{Source System Name}** : {High level context of what data scope originates from this business tool and its organizational role.}

### About the data

*{Note: Detailed definitions for every column, metric, and flag are maintained in DataHub. Do not create a Column level data dictionary section or list individual columns in this markdown document.}*

* **Temporal coverage:** {Current state (latest version) | History (validity window / SCD Type 2) | Monthly or daily snapshots (SCD Type 1 equivalent)}
* **Airflow DAG:** `bietlejuice.{dag_name}`
* **SLA:** {D-1 available by 08:00 BRT}

| Table | Grain | Links |
| :--- | :--- | :--- |
| `{table_a}` | {Temporality + Entity grain} | [DataHub](url) · [SQL](github_url) |
| `{table_b}` | {Temporality + Entity grain} | [DataHub](url) · [SQL](github_url) |

> **Note:** VPN connection is required to access DataHub.

**Main join identifiers:**

* `{primary_key}` (Standard PK/FK)
* `{alternate_key}` (Business Key)

## Core Features and Business Logic

### Domain logic and core concepts

*{This section is variable. List here the specific concepts, filters, or calculation rules that derive directly from the data scope of this dataset. Focus entirely on business meanings, completely omitting explanations of engineering processes or pipeline transformations.}*

* **{Concept/Logic Topic}** : {Detailed business logic or calculation rule in plain language.}

### Business Assumptions *(Optional)*

*{Note: Include this section ONLY if there are specific business rules or premises that lead to unexpected results or are not clear by reading the SQL queries alone. Do NOT list technical pipeline rules, Airflow triggers, or obvious synchronization details. If the SQL query logic is fully self explanatory, delete this entire subsection.}*

* **{Assumption Label}** : {One or two sentences explaining the not obvious business logic applied.}

## Attention and limitations

*{Only highlight limitations or exclusions when there is a close, potential overlap or high risk of confusion for the analysts. Omit far off or unrelated domains.}*

* **{Gotcha Label}** : {What might be misread and which column clarifies it}
* **{Data Gap}** : {Known issues or specific table behavior}

## How to use

### Standard Join Pattern

When joining this schema's tables with other DW domains:

1. Always join on `{primary_key}` (preferred) or `{alternate_key}`.
2. Reference `{main_dimension}` for central attributes.

### Wide Join (Exploratory Query)

**Question:** How can I see all available data for this domain combined with core dimensions and related organizational structures?

```sql
SELECT
    fact.*,
    dim.*,
    related.* -- Add other related dimensions as needed
FROM
    {metastore_schema}.{table_name} AS fact
LEFT JOIN {main_dimension} AS dim
    ON fact.{primary_key} = dim.{primary_key}
LEFT JOIN {related_dimension} AS related
    ON dim.{related_key} = related.{related_key}
WHERE
    fact.{filter_column} = {value}
LIMIT 100
```

### Analytical Snapshot (Fact + All Related Dims)

**Question:** Get a complete flat view of the business events with all their attributes.

```sql
SELECT
    fact.{primary_key},
    dim.{alternate_key},
    dim.{status_column}
FROM
    {metastore_schema}.{table_name} AS fact
INNER JOIN {main_dimension} AS dim 
    ON fact.{primary_key} = dim.{primary_key}
WHERE
    dim.{status_column} = {active_value}
```

## Glossary

* **Validity Window** : A period of time during which specific attributes of an entity remain constant and true.
* **Snapshot** : A representation of data as it existed at a specific, frozen point in time, such as daily or monthly intervals.
* **Current State** : The latest, real time version of the data representing only the active status of an entity without historical records.
* **SCD (Slowly Changing Dimension)** : A database design pattern used to store and manage both current and historical data over time.

## Related Scopes *(Optional)*

*{Note: Include this section ONLY if there are highly relevant or useful sibling scopes. If there are no clear, useful relationships, delete this entire section and its entry from the Contents.}*

* **{Use Case}** : Use `{related_schema}` for {reason}.