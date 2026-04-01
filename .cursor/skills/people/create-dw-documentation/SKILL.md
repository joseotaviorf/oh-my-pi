---
name: create-dw-documentation
description: >-
  People domain: scaffold or update business-facing Markdown documentation for People Data Warehouse
  DAGs under ``dags/people/`` (`workflow.layer: dw`).   Produces documentation under ``dags/people/{dag}/docs/`` aimed at business readers and Confluence;
  optional GitHub-only ``data_model.md`` with relationship diagrams for technical readers. Tables section includes DataHub plus **Explore in GitHub** (``queries/dw/{table}.sql``). **How to use** leads with KPI-style questions and clarifies dimension-only vs metrics from facts. DataHub-first column detail, PNG data model
  for Confluence when needed, PIN-friendly source naming, no duplicated glossary when metadata is authoritative. H1 format (People):
  ``DW {topic} - {short label}: {metastore_schema}`` (e.g. ``DW Demographics - DE&I Data: dw_demographics``); other DAGs may use
  ``{Readable title}: {metastore_schema}`` (e.g. Compensation Data Warehouse: dw_compensation). Prefer plain
  language over dimensional modeling jargon in published text. Include Description, Scope, Future scope
  (optional), and Out of scope with cross-schema pointers. Use when adding docs/, refreshing after schema
  changes, or narrative docs alongside SQL and metadata for People DW pipelines. Other domains or layers
  (clean, enrich, metric) are out of scope here; add a separate skill later if needed.
---

# Create DW documentation (Markdown)

## When to use

- A **DW** DAG needs **business-first** narrative docs next to **`queries/dw/`** and **`metadata/dw/`**.
- First-time **`docs/`** folder for a DW pipeline, or refresh after new tables or rule changes.
- Optional publish to **Confluence** (many teams use Confluence as the primary reader — wiki Markdown does **not** show relationship diagrams the same way **GitHub** does; use **PNG** in the wiki or link to the GitHub companion file).

## Audience and tone (default)

The default output is for **business and analytics consumers**, not engineers authoring SQL in the repo.

| Do | Avoid in the published doc |
|----|----------------------------|
| Lead with **product** source names stakeholders know (e.g. **PIN** for HR master data — avoid leading with vendor names such as Oracle HCM in narrative). | Opening **meta** paragraphs (file conventions, “this file covers one schema”, Confluence MCP instructions). |
| **Tables** section: **DataHub** link per table **and** **Explore in GitHub** to `queries/{layer}/{table}.sql` on the default branch (see **REFERENCE_TEMPLATE.md**). | Long **DataHub URL pattern** blocks, “link checks”, governance **YAML paths** in the narrative body, or omitting the **GitHub** column when the DAG has matching query files. |
| **PNG** under `docs/assets/` for the data model when the wiki needs an embedded image (Confluence-safe). | Large **diagram blocks** only in the **GitHub** companion — prefer **`docs/data_model.md`** linked from the main doc (see below). |
| **Optional `data_model.md`** linked from the main doc: full ER / join cheatsheet for engineers; **absolute** `github.com/quintoandar/bi-etl-ejuice/blob/master/.../docs/data_model.md` for readers who open GitHub. Link text in the **main** doc uses **plain language** (e.g. relationship overview for technical readers) — **no** implementation tool names. | Duplicating large diagram blocks in both places without maintaining one source. |
| **H1** as **`DW {topic} - {short label}: {metastore_schema}`** for People DW (example: **`DW Demographics - DE&I Data: dw_demographics`**), or **`{Readable title}: {metastore_schema}`** when that reads better (e.g. Compensation). Technical **`dw_*`** after the final colon (wiki-style). | Leading with only **`{metastore_schema}`** or the old pattern **`schema (short name)`** when a clearer title exists. |
| **Population** and scope in plain language (who is in / out). | Raw **technical filters** (table names, internal codes like assignment types) without translation. |
| **Glossary / metric definitions** that belong in governance | Duplicating them here — point to **DataHub metadata** (fed from YAML) as source of truth. |
| **Refresh**: state **layer SLA** when the DAG has no cron (e.g. People DW by **8:00** daily). | Only “dataset-scheduled” with no business-readable timing. |
| Describe **history and “current vs past”** in everyday terms (periods, what changed, how to filter by date). | Dimensional jargon: **slowly changing**, **SCD Type 1/2**, **surrogate key**, **degenerate dimension** — readers in HR/Finance often do not use these terms. |
| **`sk_*` columns** in the data dictionary: **internal identifier** / link to the period or entity — short wording. | Labeling keys as “surrogate key” without a business explanation. |
| **How to use:** **KPI-style business questions** first (e.g. headcount by cost center, turnover or exits by org slice), then **subsections** with **Question** + **example SQL**; when the DAG only outputs **dimensions**, state clearly that **counts and rates** come from **facts** in other schemas (e.g. `dw_people.fact_employees`) **joined** to this schema — avoid implying the DW table stores headcount. | **How to use** that only lists technical join mechanics with no **business questions**, or KPI wording that suggests metrics are **stored** in dimension-only schemas. |

**Vendor vs product names:** Technical staff may map sources to underlying vendors; **do not** headline business docs with vendor stack. Use agreed **product** names (e.g. **PIN**) in narrative.

**English** for all documentation text in the repo.

Authoritative **lineage and PII** remain in **`metadata/{layer}/{table}.yml`**; the doc summarizes **usage** and **business meaning**.

### Plain language for historical tables

When tables keep **multiple rows over time** for the same business key:

- Explain **grain** as: *one row per period where values stayed the same*, or *one row per X per month*, in **business** words — not “SCD2”.
- For **why** multiple rows exist: *when band / salary / targets change in the source, earlier rows remain so you can report as-of a past date*.
- For **current vs history**: tell readers to use **`is_current`** or **date range filters** (`dt_valid_from` / `dt_valid_to`) without assuming they know “validity windows” unless you define that phrase once in context.
- For **reference / lookup** dimensions with only current definitions, say *only today’s labels* (or equivalent) instead of “SCD Type 1”.

Technical terms belong in **metadata YAML** and **DataHub**; the Markdown doc stays readable for **stakeholders who do not model star schemas**.

### Scope, future scope, and out of scope (default)

Place these **after** the contents list and **before** the **Tables** section, matching the **People Data Dictionary** style (short title line + bullets).

| Section | Purpose |
|---------|---------|
| **Description** | One tight paragraph: what this schema delivers for the business (value and main topics). Avoid duplicating the whole executive summary; expand detail there. |
| **Scope** | **✅** bullets — what **is** in this DAG/schema (topics, grain at a high level, historical behavior if relevant). |
| **Future scope** | **⏳** bullets — planned or possible extensions **only** when there is a credible narrative (roadmap, known gaps). **Omit the section** if nothing should be promised. |
| **Out of scope** | **❌** bullets — what **is not** here; point to **real** sibling schemas or domains (verify names under `dags/` or DataHub). Typical pattern: demographics vs core employee vs performance vs hiring vs operational systems. |

**Rules:** Use **plain product names** (e.g. PIN) in scope; **do not** invent schema names — grep the repo or DataHub before citing **`dw_*`**. Out-of-scope bullets should help readers **route** to the right dataset, not list every unrelated domain.

## Inputs to collect

| Input | Source |
|-------|--------|
| `domain` | Folder under `dags/` (e.g. `people`, `for_rent`) |
| `dag_name` | DAG folder and `{name}_declaration.yml` |
| `layer` | **`dw`** (this skill targets DW DAGs only) |
| `metastore_schema` | From naming rules + `custom_schema` / DAG name |
| `readable_doc_title` | Text for the **H1** before the final **`{metastore_schema}`** segment. **People DW** convention: **`DW {topic} - {short label}`** (e.g. **`DW Demographics - DE&I Data`**). Otherwise a single readable phrase (e.g. **Compensation Data Warehouse**). Derive from `dag_purpose` and topic — not the raw folder name alone. |
| Tables | `queries/dw/*.sql` |
| GitHub SQL URL (per table) | `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/queries/dw/{table}.sql` (adjust `queries/{layer}/` if needed) |
| Purpose | `dag.documentation.dag_purpose` or metadata table descriptions |
| Layer SLA / refresh | Team convention or domain rules (e.g. People DW 8am daily) |

## Steps

1. **Create** `dags/{domain}/{dag_name}/docs/` if missing; add **`docs/assets/`** when a diagram PNG is needed for Confluence.
2. **Copy** **`REFERENCE_TEMPLATE.md`** to **`docs/{doc_basename}.md`** (main Confluence-oriented doc), or merge into an existing file.
3. **Replace placeholders** and remove any **template-only** instructions before merge (nothing about MCP, “one file per schema” in the body, or link-check boilerplate). Set the **H1** to **`{readable_doc_title}: {metastore_schema}`** — for **People DW**, prefer **`DW {topic} - {short label}: {metastore_schema}`** when it matches the catalog naming pattern (see template). **People Data Catalog:** **do not** add a markdown catalog table; metadata lives in the **Confluence Database** on the hub. For a **new** dataset, create the row in the Database (**Progress** **`In review`**, **Confidence level** **`Low`**) and **embed or link** the database on the schema’s wiki page **manually**. When the section includes a **row-level** Database URL, add a **blank line** before that markdown link so it renders as its own block (readability in GitHub and Confluence). If the **People Data Catalog** section is omitted entirely, remove its **Contents** entry (see **REFERENCE_TEMPLATE.md**).
4. **Description, Scope, Future scope, Out of scope:** fill from `dag_purpose`, metadata, and domain context; **omit Future scope** if there is nothing to say (remove its **Contents** entry too). **Out of scope** must reference **existing** schemas/pipelines where possible.
5. **Tables:** one row per output table with **DataHub** and **Explore in GitHub** links to **`dags/{domain}/{dag_name}/queries/{layer}/{table}.sql`** (see **REFERENCE_TEMPLATE.md**). Use link text such as **View SQL**; align `{layer}` with the DAG’s query folder (`dw` for People DW).
6. **Data model (main doc):** prose **grain** and relationships in plain language; optional **PNG** (`![alt](assets/...)`) for Confluence when a static image is required.
7. **Data model (GitHub companion, optional):** add **`docs/data_model.md`** with a **relationship-only** diagram (repo convention: `erDiagram` fenced blocks in that file — **do not** list every column inside the diagram — unreadable for wide tables). **Column inventories belong in DataHub** (metadata YAML); avoid duplicating full column lists in Markdown. Include **entity grain**, **cross-schema FK** notes, and **join cheatsheets**. **GitHub** displays the companion diagram; **Confluence** usually does not — link out. In the **main** Markdown (`dw_*.md`), add a **Full data model on GitHub** subsection under **Data model** with: (a) absolute `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/{domain}/{dag_name}/docs/data_model.md` and (b) same-folder `[data_model.md](data_model.md)`. Use **business-friendly** link wording, e.g. **Open on GitHub:** … — **relationship overview and join patterns for technical readers** — not names of diagram tools or markup languages. Keep the Confluence-target body free of large diagram blocks unless the team only publishes to GitHub.
8. **Executive summary** and **Business logic** from metadata and `dag_purpose`; **population** in business language.
9. **Calculation rules (when needed):** For **derived metrics** built in SQL (tenure, compa-style ratios, eligibility flags, etc.), add a **Business logic** subsection in **plain language**: reference dates, start anchors, edge cases (e.g. transfers, breaks in history). Align wording with **`dags/{domain}/{dag_name}/queries/dw/`** and **`metadata/dw/`**; **DataHub** stays authoritative for lineage and column text—do not contradict YAML.
10. **Data dictionary:** business columns only; **defer** metric definitions to DataHub. Describe **`sk_*`** columns as **internal identifiers** (and what they link), not “surrogate keys”, unless the audience is explicitly engineering-only. Cross-link **Notes** to any **calculation rules** subsection for those columns.
11. **How to use:** Start from **business / KPI questions** as bullets (e.g. headcount by cost center, breakdown by Codex segment or business unit, exits in a period by org slice — tuned to the domain). Add a **lead paragraph** when the DAG is **dimension-only**: metrics are computed by joining to **`dw_people.fact_employees`** and related facts, not stored in this schema. Then **subsections** each with a stated **Question**, a short **pattern** / disclaimer if needed (e.g. turnover definition, cross-schema job keys), and **example SQL** — including **aggregations** (`GROUP BY`, `COUNT(DISTINCT)`) where they illustrate KPIs. Call out cross-schema keys when applicable. **Example SQL** must follow **`.cursor/rules/sql_conventions.mdc`** (UPPERCASE keywords and built‑ins, **descriptive** `AS` aliases — no single-letter table aliases, explicit column lists, join layout with `ON` / `AND` on separate lines and indentation, no `SELECT *`). Column names must match **`naming_conventions.mdc`** for the layers referenced. If an example is intentionally simplified (e.g. no partition filter), say so in one line so readers do not copy an unbounded scan.
12. **Sensitivity and access** (LGPD / policy) instead of a long **Technical documentation** dump; optional one line for engineers pointing to repo metadata or **`data_model.md`**.
13. **Optional:** `docs/README.md` only if the team wants a folder index.

## Confluence publish (agent-only — do not paste into the business doc)

- **`updateConfluencePage` replaces the entire page body** with the Markdown you send. Anything that exists **only** in Confluence (macros, embedded **Confluence Databases**, some Smart Links, manual callouts) is **removed on the next sync** unless the same content also lives in the **repo** `docs/*.md` file (Markdown cannot represent native Database embeds, so those pieces are **Confluence-only**).
- **People Data Catalog:** **`## People Data Catalog`** in git is a **short pointer** (hub link + instruction to embed the Database on the wiki page)—**not** a duplicate catalog table. **Scope**, **Progress**, **Document updated at**, and other fields live **only** in the **Confluence Database**. **Creating or updating** rows and **re-linking / re-embedding** the database on the doc page after **`updateConfluencePage`** are **manual** (MCP does not edit Databases; full replace can drop embeds). If you link to a **specific catalog row**, put a **blank line** before that link in Markdown so it displays as a separate paragraph. After every sync, **verify** the embed still works—see **`publish-confluence-markdown`** (“People Data Catalog: Confluence Database”).
- When refreshing narrative sections from SQL/metadata, do **not** regenerate a markdown catalog table. Do **not** blindly overwrite **`REFERENCE_TEMPLATE.md`** into an existing doc unless the user asks for a full rewrite.
- If the page title in Confluence matches the Markdown H1, **strip the leading `#` line** from the body you send so the title is not duplicated.
- **People DW 2.0** wiki pages must be **children of [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)** — page id **`4635951235`** for MCP **`parentId`** when **creating** a page. Do **not** default to **Refining — DW 2.0** or other parents unless the user explicitly asks.
- If unsure whether the page should sit directly under the Catalog or under a specific subpage, **ask the user** (confirm against the live Catalog tree).
- **createConfluencePage** / **updateConfluencePage** with `contentFormat: markdown` when publishing from the repo file; use **`status: draft`** (see **`publish-confluence-markdown`**) so a human **publishes** in Confluence after review.
- Images: prefer **PNG** in the page; use `raw.githubusercontent.com/.../docs/assets/{image}.png` when the wiki must load a stable URL.
- **Full data model on GitHub:** If the main doc links to **`data_model.md`**, use **`https://github.com/quintoandar/bi-etl-ejuice/blob/master/.../docs/data_model.md`** so readers open the diagram in the browser. Do not paste large diagram source into Confluence unless your space renders it.

## Quality checks (authoring)

- **Business wording:** No unexplained **SCD**, **slowly changing**, or **surrogate key** in the published doc unless the page is an engineer appendix. **Confluence-target** `dw_*.md` files do **not** name diagram tools or markup libraries (business readers do not need them); the GitHub companion may use standard repo diagram blocks.
- **Title (H1):** **`{readable_doc_title}: {metastore_schema}`** — readable fragment first, **`dw_*`** schema id after the **last** colon. **People DW** example: **`DW Demographics - DE&I Data: dw_demographics`**. Matches Confluence when published.
- **Scope boundaries:** **Description**, **Scope**, and **Out of scope** are present; **Future scope** is either useful or omitted (no empty filler).
- **Cross-schema pointers:** Names in **Out of scope** match **real** DAGs/schemas in the repo or DataHub when cited.
- Definitions match **metadata YAML** and **SQL**; do not drift from DataHub.
- **Derived metrics:** If consumers ask *how* a metric is computed, the doc has a **calculation rules** subsection or the **Notes** column points to one—aligned with the query file, not ad hoc wording.
- **GitHub companion:** If **`data_model.md`** exists, the main doc links to it with a valid **`master`** branch path under `quintoandar/bi-etl-ejuice`; update the URL if the default branch differs.
- **Tables section:** Each row includes **Explore in GitHub** to the **`queries/{layer}/{table}.sql`** file when that file exists.
- **How to use:** **Business / KPI questions** lead; dimension-only docs state that **counts and rates** require **fact** tables + joins; **aggregated** SQL examples when they help (headcount by dimension, etc.). **Example SQL** matches **`sql_conventions.mdc`** (style, aliases, joins).
- **People Data Catalog:** A **catalog row** link (Database deep link), if present, is preceded by a **blank line** so the link is its own paragraph.
- **Verify** DataHub and asset links where possible (VPN/SSO may block automated checks).
- No hardcoded environment names outside documented URL patterns.
- If SQL or metadata changed, run applicable **`make validate-metadata-*`** (and related checks).

## Reference files

| File | Role |
|------|------|
| **`REFERENCE_TEMPLATE.md`** | Business-oriented skeleton (copy into `docs/`) |
| **`dags/people/dw_demographics/docs/dw_demographics.md`** | Example: H1 **`DW Demographics - DE&I Data: dw_demographics`**; DataHub-first, PNG model, PIN naming, SLA, glossary deferred to metadata |
| **`dags/people/dw_compensation/docs/dw_compensation.md`** | Example: H1 **`Compensation Data Warehouse: dw_compensation`**; **Description / Scope / Future scope / Out of scope**; **Tenure metrics (calculation rules)** with repo SQL path; history and keys in **plain language** (no SCD/surrogate-key jargon); DataHub links; SLA |
| **`dags/people/dw_employee_details/docs/data_model.md`** | Example: **GitHub-only** relationship diagram + join cheatsheet; main doc **`dw_employee_details.md`** links with plain-language anchor text |
| **`dags/people/dw_organization/docs/dw_organization.md`** | Example: **KPI-first How to use** (headcount / exits by org slice), **dimension vs fact** caveat, **Tables** with DataHub + **Explore in GitHub** |
