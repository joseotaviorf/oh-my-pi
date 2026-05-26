---
name: sync-dw-documentation
description: >
  Create or update business facing Markdown documentation for Data Warehouse datasets.
  Uses a mandatory template as the absolute reference for format and section content.
---

# Sync DW documentation (Markdown)

## When to use

Use this skill for creating **new** DW dataset documentation or **updating** existing files. It manages data extraction from **SQL** and **metadata** and applies it to the standard template.

## Absolute reference

**Source of truth for format:** all documentation must strictly follow the structure in:

* **Repo relative (official for tooling):** `.cursor/skills/people/sync-dw-documentation/REFERENCE_TEMPLATE.md`
* **Example with clone folder name:** `bi-etl-ejuice/.cursor/skills/people/sync-dw-documentation/REFERENCE_TEMPLATE.md`

## General Guidelines

### 1. English Only Requirement
The final generated documentation must be written **exclusively in English**. No Portuguese or mixed language prose is permitted in the final business facing output under any circumstances.

### 2. Finding data patterns (Grain) from SQL
Identify how the tables store data over time to fill the Data Model and Tables section. Keep technical jargon to a minimum, using database concepts **only as a clarifying complement**:

| Column pattern | Business grain |
|----------------|----------------|
| `dt_from` / `dt_to` (or validity pairs) | **Validity window** : History of changes over time (SCD Type 2). |
| `reference_month`, `snapshot_date` | **Snapshot** : Data status at a specific point in time, like daily or monthly snapshots (SCD Type 1 equivalent). |
| Event timestamps | **Event level** : Chronological list of specific actions. |
| No history columns | **Current state** : Latest version of the data only, without history (SCD Type 1 equivalent). |

### 3. Reading metadata files (YAML)
* **Automatic descriptions:** scan `metadata/dw/{table}.yml`. Use `description` fields there to pre fill table and logic descriptions in the Markdown. **Official schema for metadata files:** [`.cursor/rules/governance_metadata.mdc`](../../../rules/governance_metadata.mdc); **authoring skill:** [`.cursor/skills/create-metadata-files/SKILL.md`](../../create-metadata-files/SKILL.md).
* **SLA defaults:** if domain is **`people`**, default SLA is **D-1 available by 08:00 BRT**.

### 4. URL & asset construction
Build links using these formats:
* **DataHub:** `https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,hive.{metastore_schema}.{table},PROD)/Schema`
* **GitHub SQL:** `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/queries/dw/{table}.sql`
* **Absolute images (Confluence sync):** `https://raw.githubusercontent.com/quintoandar/bi-etl-ejuice/master/dags/{domain}/{dag_name}/docs/assets/{image}.png`

### 5. Domain logic and finding related tables
* **Mapping Placeholders by Domain:** adapt the template placeholders to your target domain.
    * **People DW mappings:** if domain is 'people', translate placeholders: `{data_catalog_name}` becomes `People Data Catalog`, `{data_catalog_url}` becomes `https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog`, `{main_dimension}` becomes `dw_people.dim_employee`, `{primary_key}` becomes `sk_employee`, and `{alternate_key}` becomes `person_number` (unless DAG SQL proves otherwise).
    * **Other Domains:** map corresponding values based on domain logic.
* **Related Scopes discovery:**
  * Scan sibling folders in `dags/{domain}/`.
  * Scan `JOIN` statements in the SQL files; if a query joins another `dw_` schema, suggest it under **Related Scopes** if highly relevant and useful.

### 6. Information to ask the user
To keep documentation simple and business useful, **ask the user** during authoring:
* **Metric question:** “What would be a good real world business question for the **Metric Analysis** example?”
* **Key columns:** “Besides join keys, are there columns I should highlight as crucial for analysts?”
* **Gotchas:** “Any gotchas or unexpected behaviors (filters, rows that look active but are not)?”
* **Sourced Systems:** "What are the source tools/systems of origin for these tables? Please list **all** systems involved (e.g. PIN, Workday, Greenhouse) so we can document them."

## Steps

1. **Setup:** ensure `docs/` and `docs/assets/` exist for the DAG (`dags/{domain}/{dag_name}/docs/`).
2. **Analysis:** scan `queries/dw/*.sql` and `metadata/dw/*.yml` to gather business context, descriptions, and all source systems.
3. **Writing the draft and talking to the user:** copy **`REFERENCE_TEMPLATE.md`** into **`dags/{domain}/{dag_name}/docs/{doc_basename}.md`**. Populate placeholders from SQL/YAML and from user answers:
   * **Inquiry:** pause and ask the questions from section 6 so **How to Use**, **Attention and Limitations**, **Data Sources**, and **Executive Summary** gain non technical, clear insights.
   * **H1:** clean slide style title. **Mandatory:** no backticks (`` ` ``) on the **`#`** line.
   * **Catalog spacing:** always a **blank line** before any **Catalog row** link.
4. **Who is included (Population):** Describe who is included and excluded using **100% natural, business oriented language**. **Never reference technical table names or SQL fields here.** If readers need lineage, they have DataHub or SQL code.
   * State the **Target Population** using only affirmative, positive statements (what IS included).
   * State **Exclusions** using clear, simple negative statements (what IS NOT included). Avoid double negatives.
   * Under **Out of Scope / Exclusions**, only list items that have a close, confusing overlap or potential risk of misinterpretation. Omit entirely unrelated business domains.
5. **Business Assumptions Optionality:** Evaluate if the **Business Assumptions** section is strictly necessary. Include it **only** in specific, highly relevant cases where a result/logic is unexpected or not clear from simply reading the code. **Do not** list technical pipeline behaviors (e.g. update frequencies, "this table maps to table B", or "data reflects the moment of the update"). If there are no complex business rules, **delete this section** entirely to avoid clutter.
6. **Critical Review & Simplification (Mandatory):** Before completing the draft, perform a thorough review to:
   * **Omit Past Data Processes:** Do not explain the physical data processing, engineering pipelines, cleansing, or transformations (such as deduplication, filtering, or sorting steps) that the data went through. Focus exclusively on the resulting state of the data and its business meaning, not how it was technically processed.
   * **Simplify Engineering Jargon:** Replace complex engineering terms with simple business language. Use words like "gather", "create", "history", "latest version" instead of "orchestrate", "scaffold", "SCD", "lineage".
   * **Ensure All Source Systems Are Listed:** Double-check that **every single** source business tool (e.g., PIN, Workday, Greenhouse) involved in the pipeline is listed in 'Data Sources and System Context'. Do **never** reference intermediate lake or enrichment tables (e.g., enrich_people, identifier_mapping).
   * **Omit Column Level Definitions:** **Do not** include a column level data dictionary or field list in the final Markdown document. This guide is internal only, as authoritative column metadata lives solely in DataHub.
   * **Remove Sensitivity/Access:** Ensure no "Sensitivity and Access" or security/LGPD sections exist in the Markdown. These are managed natively in the catalog.
   * **Verify Section Order:** Confirm that **Related Scopes *(Optional)*** is the absolute final section of the document. If unused, remove both the section and its Table of Contents entry.
   * Hunt down and remove any accidental database table names, technical field tags, or joins inside narrative sections (especially 'Who is included' and 'Data Sources').
   * Ensure all DataHub notes explicitly mention that a **VPN connection is required** for access.
   * Eliminate repetitive information across sections and simplify prose.
   * Ensure the language is completely and cleanly in English.
7. **SQL Updates:** replace SQL placeholders with **exact**, verified `schema.table` and column names from `queries/dw/`. Example SQL in the published doc must follow [`.cursor/rules/sql_conventions.mdc`](../../../rules/sql_conventions.mdc) and [`.cursor/rules/naming_conventions.mdc`](../../../rules/naming_conventions.mdc).
8. **Polishing and cleanup:** remove all `*{...}*` author comments and ensure no `{placeholder}` tokens remain.

## Quality checks

* **English Exclusivity:** Confirm there is no Portuguese or mixed languages in the document body.
* **Simple Business Language:** Ensure the text is clear, readable, and free of overly technical engineering jargon.
* **Resulting State Focus:** Ensure no descriptions of past engineering transformations (such as data cleaning, sorting, or deduplication) remain in the text.
* **Complete Source Systems List:** Confirm that **all** original source tools/systems are listed in 'Data Sources and System Context', and that internal lake/enrichment tables are completely omitted.
* **Business Only Population Wording:** Verify that 'Who is included' contains absolutely zero technical references or table names.
* **No Double Negatives:** Population exclusions are framed as simple negative statements.
* **Close Overlap Only:** Non-related out of scope domains are omitted.
* **Justified Business Assumptions:** 'Business Assumptions' is only present if explaining unexpected business logic. No technical pipeline rules or redundant statements exist here.
* **VPN Requirement Note:** Confirm DataHub indicators explicitly state the VPN requirement.
* **Final Section Check:** Verify that **Related Scopes *(Optional)*** is the last section in the document (if included), and that no "Sensitivity and Access" sections exist.
* **No Column Glossaries:** Confirm no column by column glossaries exist in the Markdown; pointers must redirect users entirely to DataHub.
* **Metadata alignment:** descriptions match `metadata/dw/*.yml` and **[`governance_metadata.mdc`](../../../rules/governance_metadata.mdc)**.
* **H1 cleanliness:** **H1** is plain text only (no backticks on the `#` line).
* **SQL Accuracy:** SQL examples use exact, verified schema and column names; layout matches **`sql_conventions.mdc`** (all keywords in UPPERCASE, strict alignment, clear table aliases, and explicit column selections instead of `SELECT *` in key snapshot queries) and identifiers match **`naming_conventions.mdc`**.