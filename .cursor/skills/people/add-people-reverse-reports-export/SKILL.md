---
name: add-people-reverse-reports-export
description: >-
  People domain (`dags/people/` only). Add or migrate a Google Sheets export under
  `dags/people/reverse_reports/`. Source priority: DW (`dw_*`) then metric-layer tables;
  avoid enrich and clean unless documented exception. sql_conventions for SQL layout;
  preserve legacy sheet headers via AS when Looker or other consumers require fixed names;
  otherwise naming_conventions. Suggest snake_case table_name. For new reverse tables
  or notebook migrations into bi-etl-ejuice.
---

# Add People `reverse_reports` export

Short guide for **adding or migrating** a People Google Sheets export that flows through `dags/people/reverse_reports/` (lake table → `load_to_gsheet`).

## At a glance

| You are… | Do this first |
|----------|----------------|
| **Implementing in Git** | New `queries/reverse/{table_name}.sql`, governance Markdown from [`reverse_export_governance_template.md`](./reverse_export_governance_template.md) in this skill folder (filled into [`codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md) or a sibling `docs/*.md`), row in `reverse_reports_declaration.yml`, service-account **Editor** on the tab. **Do not** add `metadata/reverse/{table}.yml` unless Data Governance re-enables that path in CI. |
| **Migrating a notebook** | Map reads to **`dw_*` first**, then **metric-layer** tables if the export is rollup-style; **avoid enrich/clean** unless there is no DW/metric path and the PR documents the exception. Replace deprecated objects; keep **sheet column names** stable when Looker or ops depend on them (`AS legacy_name`). |
| **Using an agent** | Paste notebook SQL + sheet link when you have them; expect a suggested `table_name` and a short list of **deprecated → replacement** changes. |

---

## When to use

- Registering a **new** tab in `reverse_reports_declaration.yml`.
- Adding `queries/reverse/{table_name}.sql` for a People table exported to **Google Sheets**.
- Moving a **Daily Pipeline** (or similar) notebook export into **bi-etl-ejuice**.

---

## How agents should behave (and what humans can expect)

**Reduce back-and-forth**

- Reuse what is already in the thread: notebook name, sheet URL, business context, pasted SQL.
- Propose a **`table_name`** in `snake_case` (from notebook name, job, or tab). The author accepts or corrects in one reply.

**Sources**

- Follow **Source priority** in the next major section: **`dw_*` (DW 2.0) first**, then **metric-layer** outputs (`workflow.layer: metric` tables / `metric_*` DAGs where applicable). **Enrich** and **clean** lake paths are **last resort**: **enrich** uses **`datalake_*`** catalog names **without** `_clean` or `_raw` suffixes (tables are built by DAGs whose repo folders use the **`enrich_*`** prefix under `dags/`); **clean** uses catalogs such as **`datalake_*_clean`** (for example **`datalake_pin_*_clean`**). Avoid both for new reverse SQL unless there is **no** DW or metric equivalent and the PR states **why** the exception is unavoidable.
- If there is **no** safe `dw_*` or metric mapping, say so and suggest a dependency ticket (for example: promote fields into DW or publish a metric table)—do not invent joins.

**After you remap SQL**

- Tell the user briefly: *old object → new object* and *why* (for example: deprecated in `people_domain.mdc`).

**SQL and headers**

- Repo SQL: formatting and **`SELECT` column order** from [`sql_conventions.mdc`](../../../rules/sql_conventions.mdc).
- Sheet headers: follow **Export column names** below (migration vs net-new).

**Governance Markdown (not `metadata/reverse`)**

- **Do not invent** business consumers, owning squads, or technical integration patterns (for example **API**, iPaaS, “live feed”) unless the user or an linked artefact (Jira, Confluence, declaration comment) states them. Stick to **stakeholder wording** for why the tab is still Google Sheets.
- If the thread does not spell out **who ingests the tab**, **who owns the upstream source** (when it is not only DW), and **why Sheets**, ask before filling the export-level table in the Markdown doc (see **Governance narrative**). Repository CI rejects governance YAML under `metadata/reverse/`; use **[`reverse_export_governance_template.md`](./reverse_export_governance_template.md)** (same folder as this skill) and paste the filled section into **`docs/codex_pin_gsheet_exports.md`** (CODEX → PIN family) or a new file under **`dags/people/reverse_reports/docs/`**.

**Questions**

- Ask only what is still unknown; see **Essential questions (max three)** plus **optional** governance questions when authoring the Markdown section.

---

## Authoritative references

| Topic | Where to look |
|-------|----------------|
| DW 2.0 layout, deprecations, what not to use | [`people_domain.mdc`](../../../rules/people/people_domain.mdc) |
| Metric DAG pattern (`layer: metric`) | Declarations under `dags/**/` whose DAG folder names start with `metric_` (for example `metric_rent__contracts`); use as reference for curated metric tables. |
| Enrich DAG pattern (`layer: enrich`) | DAG folders under `dags/people/` (and elsewhere) whose names start with **`enrich_`** (for example `enrich_people`); their outputs land in **`datalake_*`** catalogs **without** `_clean` / `_raw` suffixes. |
| DAG wiring, service account | [`reverse_reports_declaration.yml`](../../../../dags/people/reverse_reports/reverse_reports_declaration.yml) |
| Partition filter, column mapping, forno test sheet | [`load_to_gsheet.py`](../../../../dags/people/reverse_reports/spark_jobs/load_to_gsheet.py) |
| Reverse governance Markdown (template + CODEX → PIN examples) | [`reverse_export_governance_template.md`](./reverse_export_governance_template.md), [`codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md) |
| Central metadata YAML (other DAG layers) | [`governance_metadata.mdc`](../../../rules/governance_metadata.mdc), skill [`create-metadata-files`](../../create-metadata-files/SKILL.md) — **not** used for `metadata/reverse/` on this DAG until CI allows it |
| SQL layout, column order | [`sql_conventions.mdc`](../../../rules/sql_conventions.mdc) |
| English `snake_case` names for **new** columns | [`naming_conventions.mdc`](../../../rules/naming_conventions.mdc) |
| Programme / epic context | [DBP-1310](https://quintoandar.atlassian.net/browse/DBP-1310) (Jira); longer written plans may live in Confluence or local programme docs |

---

## SQL style (mandatory)

All pipeline SQL under `dags/people/reverse_reports/queries/reverse/` must follow [`sql_conventions.mdc`](../../../rules/sql_conventions.mdc):

- Formatting, explicit `AS`, and **column arrangement priority** on the outer `SELECT`.
- Do **not** keep a notebook’s random column order when it conflicts with the guide: **reorder** to match the guide, then use **aliases** so downstream tools still see the expected names (next section).
- Keep the **Markdown column inventory** row order aligned with the SQL `SELECT` list (same discipline as metadata YAML elsewhere; see [`people_domain.mdc`](../../../rules/people/people_domain.mdc) for People expectations).

---

## Export column names: migration vs net-new

**Migrated sheet (Looker, fixed headers, or other name-based consumers)**

- Final `SELECT` **aliases** must match legacy **header strings** (notebook / sheet).
- Reorder columns per `sql_conventions.mdc`; use `AS exact_legacy_header` so the first row in Sheets matches what Looker or scripts expect.
- Looker usually binds by **name**, not position—renames or drops need LookML or consumer updates.

**Net-new export, or renames explicitly approved**

- Column names follow [`naming_conventions.mdc`](../../../rules/naming_conventions.mdc) (English, `snake_case`, meaningful), still with `sql_conventions.mdc` order and formatting.

**If it is unclear whether headers are contractual**

- Default to **preserving names with `AS`**, and ask one short yes/no only if the thread gives no hint.

---

## Source SQL: priority, metrics, and deprecation (mandatory)

**Default source priority for `queries/reverse/*.sql`**

| Priority | Use when | Examples / notes |
|----------|-----------|------------------|
| **1 — DW** | Almost always: dimensions, facts, and attributes owned by People DW. | `dw_organization`, `dw_employee_details`, `dw_compensation`, `dw_demographics`, `dw_performance`, `dw_people`, `dw_learning`, `dw_payroll`, `dw_hiring`, `dw_equity`, `dw_survey` — scope per [`people_domain.mdc`](../../../rules/people/people_domain.mdc). |
| **2 — Metrics** | The sheet is a **rollup**, KPI slice, or other output that already exists as a **curated metric table** (DAGs with **`workflow.layer: metric`**, often `metric_*` under `dags/`). | Prefer reading the **published metric table** instead of recomputing from enrich/clean upstreams. People-specific metric DAGs may be added over time; follow the same rule. |
| **3 — Enrich / clean (avoid)** | **Only** when neither DW nor metrics expose the fields, and the gap is accepted as temporary. | **Enrich:** **`datalake_*`** catalogs **without** `_clean` or `_raw` (typically from **`enrich_*`** DAGs). **Clean:** **`datalake_*_clean`** (for example **`datalake_pin_*_clean`**). **Do not** default to these for new exports. If you must, add a **PR comment + ticket** explaining the gap and the plan to move to `dw_*` or metrics. |

**Deprecation and banned paths**

**Do not add new references to** (non-exhaustive; full list in `people_domain.mdc`)

- `datalake_hr_system*`, `datalake_employment`
- **`greenhouse` v1** — prefer **`greenhouse_v3`**
- Legacy enrich outputs called out in `people_domain.mdc` (and treat **enrich/clean** as discouraged for reverse per the table above, even when not formally “deprecated”)
- **`dw_employee`** patterns / DAG being retired — use domain **`dw_*`** tables instead
- **`hr_system` / `hr_system_custom`**-style schemas where marked deprecated

**Migration habit**

- Replace deprecated or notebook-layer references yourself, targeting **`dw_*` or metric-layer** tables first; then summarise: *old → new + one-line reason*.
- No clear **DW or metric** equivalent → state that and propose a dependency story (extend DW, add a metric table, or time-boxed exception for enrich/clean).

---

## Essential questions (only if not already in the thread)

Ask **only** what is still missing. Skip any bullet the user already answered.

1. **Business process** — What does the sheet support? Who uses it, roughly how often?
2. **Why Sheets** — Operational spreadsheet, Looker supplement, or other; confirm Sheets vs Databricks / Superset-only if that is in doubt.
3. **Target sheet** — Production **`sheet_id`**, **tab name**, and **Editor** for `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`.

**Optional (use when authoring governance Markdown — ask if missing)**

4. **Operational consumer** — Who actually applies or ingests the tab (for example **People Systems** loading **PIN / Oracle HCM**), distinct from “People domain” in the abstract.
5. **Upstream source owner** — When truth lives outside DW alone (for example **FP&A** owns the **CODEX** spreadsheet), name that owner so the Markdown **Operational source of truth** row is accurate.
6. **Sheets constraint in the stakeholder’s words** — Why the process is still a tab (for example *no direct integration yet between PIN and the CODEX spreadsheet*). **Do not** add technologies or integration designs you were not told about.
7. **Business owner vs technical owner** — **Business owner:** squad or role accountable for upstream truth and what “correct” means in the sheet (not the same as Data People by default). **Technical owner:** email for whoever maintains SQL, DAG `tables_customization`, and sheet ACLs. Ask if either is unclear.

**Infer by default** (no extra questions unless ambiguous)

- Grain and keys from legacy or proposed SQL.
- Cadence from upstream DAG or “same as the daily notebook”.
- PII treatment from schema + `governance_metadata.mdc`.
- Source remapping from pasted SQL to **`dw_*` or metric-layer tables**—**never** default to **`dw_employee`** or to **enrich/clean** when a DW or metric source exists; use domain `dw_*` per **Source SQL** above.
- Offer `table_name`; ask once if rejected or if there is a naming clash.

**Do not “infer by default”** for the export-level narrative in Markdown (business consumer, upstream owner, why Sheets, business vs technical owner): if Q1–Q3 and optional Q4–Q7 are not answered, **ask**—do not fill with generic teams or patterns.

---

## Governance narrative (Markdown under `docs/`)

Use the filled template tables as the **audit trail** for humans and governance, not as marketing text.

- **One-line summary:** what the export is technically (grain, target system if any—for example rows shaped for PIN ingestion).
- **Business purpose:** one or two sentences from the stakeholder (bridge CODEX → PIN, compensation review in Sheets, etc.).
- **Business consumer:** the team or system that **uses the tab operationally** (ingestion, configuration), not guessed from domain alone.
- **Delivery channel / operational source:** why Google Sheets and where truth lives when stated by stakeholders—**only** using reasons they provided. Avoid invented stack details.
- **Business owner vs technical owner:** document both in the export table—**business** = accountable for spreadsheet semantics and upstream source; **technical** = accountable for pipeline code, DAG wiring, and access to the workbook for the service account.

**Example pattern (CODEX → PIN — wording must match your ticket, not this text verbatim)**

- Consumer: People Systems (PIN ingestion). Upstream: CODEX / FP&A spreadsheet when that is the stated source of truth. Sheets: stakeholder explanation of the gap between PIN and that spreadsheet—without adding APIs or tools they did not mention.

Mirror the same facts in short **`reverse_reports_declaration.yml`** comments on the `tables_customization` entry when helpful for operators.

**Mechanics:** Start from [`reverse_export_governance_template.md`](./reverse_export_governance_template.md); for CODEX → PIN exports, append the filled section to [`docs/codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md).

---

## What to put in the PR or ticket

| Topic | Content |
|-------|---------|
| **Export / `table_name`** | Agreed or suggested `snake_case` name. |
| **Business use case** | From Q1 or thread. |
| **Sheets justification** | From Q2 or thread (and optional Q6). |
| **Target sheet** | From Q3. |
| **Operational consumer / upstream owner** | From optional Q4–Q5 when relevant (PIN ingestion, FP&A CODEX, etc.). |
| **Business owner / technical owner** | From optional Q7; must appear in the Markdown export table. |
| **Sources + deprecation** | Ordered list of **`dw_*` and/or metric** tables used; if any **enrich/clean** reference remains, justify it. Bullets **deprecated → replacement** for every remap. |
| **Column naming** | Legacy headers via `AS` **or** naming_conventions (explicitly approved). |
| **SQL style** | Matches `sql_conventions.mdc` (format + column order). |
| **Governance doc** | Path to the filled Markdown section (`codex_pin_gsheet_exports.md` or sibling under `docs/`). |

---

## Implementation checklist

1. **SQL** — Add `dags/people/reverse_reports/queries/reverse/{table_name}.sql` so the table materialises as `reverse_reports.{table_name}` with **`year`, `month`, `day`** partitions consistent with sibling queries in this DAG.
   - Apply `sql_conventions.mdc` to formatting and `SELECT` order.
   - Grep for deprecated names and for **unwanted layers**: references to **`datalake_*`** without `_clean`/`_raw` (enrich) and **`datalake_*_clean`** (clean) when DW or metric sources should cover the need.
   - Align exported headers with **Export column names** (aliases vs conventions).
   - If headers must match an external system exactly, consider `column_mapping_mode: name` (see **`organization_codex_pin_sync`** in the declaration).
2. **Governance Markdown** — Copy [`reverse_export_governance_template.md`](./reverse_export_governance_template.md); paste a filled `## \`{table_name}\`` section into [`docs/codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md) when the export is part of that programme, **or** add a new `docs/<topic>_gsheet_exports.md` for other reverse tabs. Document column intent and lake sources in the column inventory table; align row order with the SQL `SELECT` list. **Do not** add `metadata/reverse/{table_name}.yml` unless Data Governance and CI explicitly allow it again.
3. **Declaration** — Under `workflow.tables_customization`, add `{table_name}:` with `extra_spark_job_arguments: [<sheet_id>, <sheet_tab>]`. Use `column_mapping_mode: name` when name-based mapping is required.
4. **Sheet ACL** — Share the spreadsheet with **Editor** for the People Airflow service account (see `reverse_reports_declaration.yml`).
5. **Validation** — Run `make validate-dag-declaration-files` and other checks your PR touches. **Do not** expect `make validate-metadata-files-content` / lineage validators to cover these Markdown files; governance review happens in PR like any other doc.

---

## Quality checks before merge

- **Sources** — No new deprecated People sources; **`dw_*` and/or metric-layer** tables as the default. **Enrich/clean** only with an explicit exception note in the PR; no “convenience” reads from those layers when DW or metrics already cover the need.
- **SQL style** — Formatting and column arrangement per `sql_conventions.mdc`.
- **Downstream contract** — Migrated / Looker: aliases match agreed headers. Net-new: names per `naming_conventions.mdc`. File order follows the style guide, not the legacy notebook order.
- **Schema** — Keys and dates match DW contracts; no accidental duplicate natural keys across partitions.
- **Permissions** — Service account can edit the tab; production `sheet_id` has an owner.
- **Volume** — Sane row/column counts; filter or pre-aggregate if near Sheets limits.
- **Privacy** — DAG privileges and documented handling match LGPD expectations for `sensitive` / `highly_personal` when the export touches person-related data.
- **Governance prose** — Markdown export-level tables match **confirmed** consumers and constraints (no invented APIs or teams); declaration comments align.
- **Operations** — Declaration comments name business context; Markdown documents business owner vs technical owner when the sheet feeds a tool (for example PIN sync).

---

## Minimal example (structure only)

**`queries/reverse/example_export.sql`** — Copy patterns from real files in the same folder; include partitions and stable keys.

**`reverse_reports_declaration.yml` fragment:**

```yaml
  tables_customization:
    example_export:
      extra_spark_job_arguments:
        - "<production_sheet_id>"
        - "<tab_name>"
```

**Governance** — Copy [`reverse_export_governance_template.md`](./reverse_export_governance_template.md), fill it, and add it under `docs/` as described in the implementation checklist (no `metadata/reverse/example_export.yml` on this DAG).

---

## Out of scope

- **Other domains** — `reverse_reports`-style DAGs under `dags/for_rent/`, `dags/fintech/`, etc. have their own rules; this skill is **People-only** (`dags/people/`).
- **Infra** — Global DAG schedule or cluster sizing (coordinate with Data People).
- **BI-only** — Looker or dashboard-only migrations without a reverse lake table (see programme phasing in Jira / internal docs).
- **Human ACLs** — Who may open the spreadsheet outside the service account (process outside this repo).
