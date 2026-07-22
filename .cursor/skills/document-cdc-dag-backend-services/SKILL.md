---
name: document-cdc-dag-backend-services
description: >
  Document a backend-services CDC ingestion DAG from end to end. Creates a Markdown
  technical reference sourced from the backend-services application (Flyway migrations,
  JPA entities, enums, README), improves clean-layer metadata YAML files, and creates
  data quality YAML files. Use when the user asks to document a CDC DAG whose source
  service lives in backend-services, create its `.md` documentation, improve its
  metadata, or add data quality checks.
---

# Document a CDC DAG (Backend Services)

This skill automates the full documentation lifecycle for a CDC (Change Data Capture)
ingestion DAG in bi-etl-ejuice:

1. Validate the DAG is CDC
2. Locate the backend source and resolve fallbacks
3. Analyse the source schema and enums
4. Gather any missing business context from the user
5. Create the Markdown technical reference
6. Improve clean-layer metadata YAML files
7. Create data quality YAML files

Reference format: [`dags/growth/alias/alias.md`](../../dags/growth/alias/alias.md)

---

## Step 0 — Identify and validate the DAG as CDC

Read `dags/<domain>/<dag_name>/<dag_name>_declaration.yml` and confirm:

```yaml
workflow:
  type: cdc           # required
  source_database:    # source DB name (e.g. "alias", "ebdb", "company")
  source_schema:      # "public" for Postgres, database name for MySQL
```

**If `type != cdc`:** stop and tell the user this skill only covers CDC DAGs.
Point them to `create-dag` for other workflow types.

Extract:
- `<source_database>` — used in Step 1 to locate the backend application
- `<source_schema>` — used to understand DB engine and schema
- `<domain>` — business domain folder (e.g. `growth`, `broker_xp`)
- `tables_customization` keys — the exact list of ingested tables

---

## Step 1 — Locate the backend source

### 1a — Ask if the service is in backend-services

Ask the user:

> "Is `<source_database>` an application in the `backend-services` monorepo?"

- **If no:** ask the user to provide the path or GitHub URL to the source service's
  code (Flyway migrations, entity files). Adapt Steps 2–3 accordingly — the remaining
  steps are the same.

- **If yes:** proceed to Step 1b.

### 1b — Detect whether backend-services is cloned locally

```bash
# Try common workspace layouts
ls /Users/*/Documents/projects/backend-services/applications/ 2>/dev/null \
  || ls ~/projects/backend-services/applications/ 2>/dev/null \
  || ls "$(git -C . rev-parse --show-toplevel 2>/dev/null)/../backend-services/applications/" 2>/dev/null
```

**If found:** resolve `APP_PATH=<backend-services-root>/applications/<source_database>` and
proceed to Step 2.

**If not found:** present the three alternatives below and wait for the user to choose
before continuing.

---

### Fallback options (when backend-services is not cloned)

#### Option A — Clone the repository (recommended)

```bash
git clone git@github.com:quintoandar/backend-services.git \
  /Users/<you>/Documents/projects/backend-services
```

After cloning, add the folder to the Cursor workspace, reload, and re-run this skill.

#### Option B — GitHub raw (no clone required)

The skill reads individual files via GitHub API without a full clone. This requires
a valid GitHub token (`GH_TOKEN` or `GITHUB_TOKEN` in the environment, or `gh auth login`).

```bash
# Verify token
gh auth status 2>/dev/null || echo "NOT_AUTH"

# Example: read a Flyway migration
gh api \
  "repos/quintoandar/backend-services/contents/applications/<app>/src/main/resources/db/migration" \
  --jq '.[].name'
```

If the token is missing or invalid, fall back to Option C.

#### Option C — Assisted offline mode

The skill works with existing DAG artifacts only:
- `queries/clean/*.sql` — column names and transformations already applied
- `metadata/clean/*.yml` — existing metadata (may be incomplete)
- `*_declaration.yml` — ingested table list

The generated documentation will include `TODO:` markers in every field that requires
human verification. The user will be asked to provide enum values and business context
interactively in the chat before the skill writes the final files.

---

## Step 2 — Analyse the backend (schema, enums, context)

Perform all reads from `APP_PATH` (or via GitHub API in Option B).

### 2a — Tables and schema (Flyway is the source of truth)

```bash
ls APP_PATH/src/main/resources/db/migration/V*.sql | sort
```

For each migration file, extract:
- `CREATE TABLE` / `ALTER TABLE` statements → column names, types, `NOT NULL`, defaults
- `PRIMARY KEY` and `UNIQUE` constraints
- `FOREIGN KEY … REFERENCES` → FK relationships
- `CREATE INDEX` → relevant access patterns
- `DROP TABLE` / `DROP COLUMN` → tables or columns removed before the current schema

**JPA entities as supplement** (not primary):
Read `*Entity.java` / `*Entity.kt` files for:
- `@Column(nullable = false)` — confirms NOT NULL for columns the DDL doesn't make explicit
- `@ManyToOne`, `@OneToMany`, `@JoinColumn` — FK semantics and cardinality
- `@Enumerated` — confirms which columns carry enum values

### 2b — Enums

Collect all enum types that write to the database:

1. **PostgreSQL native enums** — `CREATE TYPE … AS ENUM (…)` in Flyway DDL
2. **JPA-mapped Java/Kotlin enums** — `public enum` / `enum class` files referenced
   by `@Enumerated` columns in entities. Read the enum source file to get the exact values.
3. **Application-level VARCHAR enums** — columns typed `VARCHAR` in DDL but constrained
   in code; look for `@Column` + `EnumType.STRING` or explicit `CHECK` constraints.

For each enum, record: name, values (exact, case-sensitive), and the entity column(s) that use it.

### 2c — Business context

In priority order:
1. `APP_PATH/README.md` — overall service purpose and architecture
2. `APP_PATH/docs/` — ADRs, `architecture.html`, flow diagrams, API contracts
3. Javadoc/KDoc on the main entity classes — field-level business meaning

Note any lifecycle flows, state machines, or multi-step processes described in the docs —
these become the ASCII/Mermaid diagrams in Step 4.

---

## Step 3 — Gather missing context from the user

Before writing any files, ask (only the questions that could not be answered from the source):

1. Are there tables in the source database that are **intentionally not ingested**? If yes,
   which ones and why? (These go into the "Removed/non-ingested tables" section.)
2. Is there business context not covered by the README that is important for analysts using
   this data?
3. Who is the **owner email** for the metadata files? (If not already set in `*_declaration.yml`.)

If all three answers are available from the source, skip this step.

---

## Step 4 — Create the Markdown documentation

Create `dags/<domain>/<dag_name>/<dag_name>.md`.

Follow the structure of [`alias.md`](../../dags/growth/alias/alias.md) **exactly**:

```
# <Service Name> — <Engine> Database (Production)

## About <Service Name>
  One paragraph: what the service does, who uses it, its role in the product.
  - Link to backend-services GitHub application folder
  - Link to TechDocs / Backstage (if available)

## <Main lifecycle / flow sections>
  One section per key process (e.g. "Lead lifecycle", "Onboarding flow").
  Use ASCII diagrams or Mermaid flowcharts derived from the README/ADRs.
  Each step should reference the relevant DB table(s).

## Connection (production)
  Markdown table: Engine | Host | Port | Database | Schema | JDBC URL | Driver | Vault credentials
  Also include Forno and Staging connection strings if known.

## Entity-relationship diagram
  Mermaid erDiagram block. Rules:
  - Include ALL tables in the source database, even non-ingested ones
  - Use clean-layer column names (id_*, uuid_*, ts_*, dt_*, is_*, has_*)
  - Mark PK and FK on every relevant column
  - Show cardinality (||--o{ etc.)

## Removed/non-ingested tables (omit section if none)
  Markdown table: Table | Reason | Notes

## PostgreSQL enum types
  One subsection per enum:
  ### `<enum_name>`
  Used by: `<table>.<column>`
  Markdown table: Value | Description
  (Each value must have a brief English description.)

## Tables
  One subsection per ingested table (### `<table_name>`):
  - One paragraph of business context (grain, purpose, key relationships)
  - Markdown table: Column | Type | Nullable | Constraints
    - PK columns: **PK** in Constraints column
    - FK columns: **FK → <target_table>** in Constraints column
    - Enum columns: "enum" in Constraints column
    - PII columns: **PII** in Constraints column
  - Notable indexes (if any)

## Sensitive columns summary
  Markdown table: Table | Columns | Handling
```

### Mandatory rules for the documentation

- **All** tables in the source database must appear in the ER diagram, even tables not
  ingested by the DAG. Use the Flyway migrations to build the complete list.
- Enum values must be **exactly** as found in the source code — never invent or paraphrase.
- Each enum value must have a short, plain-language English description.
- Column names in the ER diagram use the **clean layer** naming conventions:
  - `*_id` → `id_*` (e.g. `user_id` → `id_user`)
  - `created_at` → `ts_created`, `updated_at` → `ts_updated`
  - `*_uuid` or `uuid_*` → `uuid_*`
  - Dates: `dt_*`; booleans: `is_*` / `has_*`
- PK and FK columns must be **bold** in the Tables section.
- PII columns must be explicitly flagged (phone, email, CPF, name, etc.).

---

## Step 5 — Create or improve clean-layer metadata files

For each table in `dags/<domain>/<dag_name>/metadata/clean/`:

**Read the existing file first.** Then apply the following improvements:

### 5a — `categories:` blocks for enum columns

Add or update `categories:` using **dict format** (not list) with English descriptions:

```yaml
status:
  description: "Current entity status in the service lifecycle."
  lineage:
    - datalake_<schema>_raw.<table>.status
  categories:
    ACTIVE: Entity is active and operational on the platform.
    INACTIVE: Entity is inactive or disabled on the platform.
```

Values must match the enum exactly as found in Step 2b.

### 5b — PK and FK descriptions

- **PK column:** `"Primary key. Unique identifier of <entity> in <service>."`
- **Simple FK:** `"Foreign key → datalake_<schema>_clean.<target_table>. <brief join context>."`
- **Composite PK** (audit tables): mention both columns in the description of each.

### 5c — NOT NULL enrichment

For every NOT NULL column that has a generic description (e.g. "Creation timestamp"),
improve it to include business meaning:
`"Timestamp UTC of when the <entity> was first created in <service>. NOT NULL — always set at insert."`

### 5d — Validate

```bash
make validate-metadata-files-content
make validate-lineage-consistency
```

Fix any errors before proceeding to Step 6.

---

## Step 6 — Create data quality files

Create `dags/<domain>/<dag_name>/data_quality/clean/<table>.yml` for every clean table.

### DQ file template

```yaml
---
table_name: datalake_<schema>_clean.<table>
alert_channel: "#alerts-de-airflow-dags"

table_level_validations:
  has_size:
    greater_than: 0
    severity_level: Error
  has_size_variation:
    variation_type: percentage
    greater_than_or_equal_to: -10
    less_than_or_equal_to: 50
    severity_level: Warning

column_level_validations:
  <pk_col>:
    is_unique:
      severity_level: Error
    is_complete:
      severity_level: Error
  <not_null_col>:
    is_complete:
      severity_level: Error
  <enum_col_not_null>:
    is_contained_in:
      values:
        - VAL_A
        - VAL_B
      severity_level: Error
  <enum_col_nullable>:
    is_contained_in:
      values:
        - VAL_A
        - VAL_B
      severity_level: Warning
  year:
    is_complete:
      severity_level: Error
  month:
    is_complete:
      severity_level: Error
    has_min_value:
      greater_than_or_equal_to: 1
      severity_level: Error
    has_max_value:
      less_than_or_equal_to: 12
      severity_level: Error
  day:
    is_complete:
      severity_level: Error
    has_min_value:
      greater_than_or_equal_to: 1
      severity_level: Error
    has_max_value:
      less_than_or_equal_to: 31
      severity_level: Error
```

### Rules per column type

| Column type | Validation | Severity |
|---|---|---|
| Simple PK | `is_unique` + `is_complete` | Error |
| Composite PK (audit `*_aud`) | `custom` GROUP BY + `is_complete` | Error |
| NOT NULL (non-PK) | `is_complete` | Error |
| Enum, NOT NULL | `is_contained_in` with exact values | Error |
| Enum, nullable | `is_contained_in` with exact values | Warning |
| Partition `year` | `is_complete` | Error |
| Partition `month` | `is_complete` + `has_min_value` (`greater_than_or_equal_to: 1`) + `has_max_value` (`less_than_or_equal_to: 12`) | Error |
| Partition `day` | `is_complete` + `has_min_value` (`greater_than_or_equal_to: 1`) + `has_max_value` (`less_than_or_equal_to: 31`) | Error |

### `is_contained_in` value format

Use a **YAML dash list** under `values:` (same as `dags/growth/alias/data_quality/`).
Do **not** use unquoted inline arrays such as `values: [BLOCK, ALERT, ALLOW]` — YAML may
coerce tokens like `YES`/`NO` to booleans. Quote only when needed (e.g. rev_type audit codes
`"0"`, `"1"`, `"2"`, or values containing `/` like `"N/A"`).

```yaml
  status:
    is_contained_in:
      values:
        - BLOCK
        - ALERT
        - ALLOW
      severity_level: Error
  rev_type:
    is_contained_in:
      values:
        - "0"
        - "1"
        - "2"
      severity_level: Error
```

### Composite PK pattern (audit tables ending in `_aud`)

```yaml
  id:
    is_complete:
      severity_level: Error
    custom:
      constraint: "GROUP BY id, rev HAVING COUNT(*) > 1"
      empty_result_is_valid: true
      severity_level: Error
  rev:
    is_complete:
      severity_level: Error
```

### Append-only tables (CDC replay risk)

For tables that are append-only audit logs (e.g. `*_history`, `*_event`, `*_log`),
use **Warning** instead of Error for `is_unique` on the PK — CDC replays may legitimately
produce duplicate IDs during backfill:

```yaml
  id:
    is_unique:
      severity_level: Warning
    is_complete:
      severity_level: Error
```

---

## Checklist before finishing

- [ ] `<dag_name>.md` created with all sections from the alias.md format
- [ ] All source DB tables present in the ER diagram (including non-ingested)
- [ ] All enum values exactly match the backend source code
- [ ] Each enum value has an English description
- [ ] PK, FK, and PII columns are explicitly flagged in the Tables section
- [ ] `metadata/clean/*.yml` updated with `categories:` blocks in dict format
- [ ] PK/FK descriptions updated in metadata
- [ ] `make validate-metadata-files-content` passes
- [ ] `data_quality/clean/*.yml` created for every clean table
- [ ] DQ `is_contained_in` values match the enum values in the documentation (dash-list format under `values:`)
- [ ] Audit tables (`*_aud`) use the composite PK `custom` constraint pattern

---

## Behavior rules

- **Never invent enum values** — always read from source code.
- If backend-services is not available and Option C (offline) is chosen, mark every
  inferred field with `TODO:` so the engineer knows what to validate manually.
- Ask the user for context before writing, not after — avoid rework.
- If the DAG has more than 20 tables, process documentation and DQ in batches of 10,
  reporting progress to the user after each batch.
- Always read existing metadata files before editing — preserve lineage, domain, owner,
  and any field not being improved.
- The `categories:` format is always a **dictionary** (`key: description`), never a list.
