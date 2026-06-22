---
name: create-metadata-files
description: Author and fix metadata YAML files for bi-etl-ejuice. Follows .cursor/rules/governance_metadata.mdc for schema and governance fields. Use when creating metadata for new SQL files, updating metadata after SQL changes, or fixing metadata CI failures.
---

# Create Metadata Files

## Required rule

**Before creating or editing any metadata file**, read [`.cursor/rules/governance_metadata.mdc`](.cursor/rules/governance_metadata.mdc) and [`.cursor/rules/fairness_metadata.mdc`](.cursor/rules/fairness_metadata.mdc), and apply them as the authoritative source for:
- Valid domains (canonical allowlist in `fairness_metadata.mdc`)
- Column schema (`description`, `lineage`, categories, metric blocks)
- FAIR F2-01 / F2-02 and common mistakes and validation commands

**Phase 1 rollout:** Do **not** add `columns.*.privacy` when creating or fixing metadata on normal feature PRs. PII catalog + CI exist as infra only; classification rolls out in dedicated governance PRs later. If you see `personal_data_classification`, remove it (CI rejects it) — do not replace with `privacy` unless the user explicitly asked for classification.

## When to use

Use this skill when:
- creating `metadata/{layer}/{table}.yml` file for **new** `.sql` files (use the "Workflow: Create metadata for new SQL files" section);
- updating metadata after SQL column changes;
- fixing CI failures in metadata validation steps.

## Important: User responsibility and review

**Automated file creation may contain errors.** The agent is here to guide and help improve the quality of descriptions and metadata structure, but the final output is ultimately the responsibility of the data engineer.

- Always review all generated or modified files before submitting PRs
- Validate locally with `make validate-metadata-files-content`, `make validate-lineage-consistency`, and `make validate-fair-metadata`
- Fill or correct any TODO placeholders, generic descriptions, or inferred values that need business context

## Golden Rule

Every `.sql` file in `queries/{layer}/` **must** have a matching `.yml` in `metadata/{layer}/` with the same base name. CI fails without it.

The metadata file name must be `{table_name}.yml`, and the YAML `table_name` field must be **identical** to that file stem (without `.yml`). Example: `fact_agent_daily.yml` requires `table_name: fact_agent_daily`. A mismatch (e.g. `dim_media_setup.yml` with `table_name: media_setup`) fails `validate-metadata-files-content`.

## Workflow: Create metadata for new SQL files

Use this workflow when you have **new** `.sql` files (tables) that don't have corresponding metadata yet. It reuses existing validation scripts — no new scripts required.

### Step 1 — Find SQL files without metadata

```bash
make validate-metadata-files-exist
```

If it fails, the output lists files under "Queries that don't have a corresponding metadata file:". Each line has format `file=dags/{domain}/{dag_name}/queries/{layer}/{table}.sql`.

### Step 2 — Create a minimal skeleton for each SQL file

For each SQL listed, create `dags/{domain}/{dag_name}/metadata/{layer}/{table}.yml` with:

- Mandatory fields for the layer (database_name, table_name, description, domain, owner)
- `columns:` with **one placeholder column** (e.g. `_placeholder`) so the schema validates

Infer values from the path and DAG declaration:
- `table_name` = SQL filename without `.sql`
- `database_name` = from [naming_conventions.mdc](.cursor/rules/naming_conventions.mdc): `datalake_{source}_{context}` (enrich), `dw_{schema}` (dw), `metric_{context}` (metric)
- `domain` = map `dag.owner` from `{dag_name}_declaration.yml` to a valid domain (e.g. "Data SS" → "Support and Services")
- `owner` = email from `{dag_name}_declaration.yml`

**Raw/Clean skeleton (with placeholder):**

```yaml
database_name: "datalake_xxx_yyy"
table_name: "table_name"
description: "TODO: business description with at least 10 characters."
domain: "Support and Services"
owner: "owner@quintoandar.com.br"
columns:
  _placeholder:
    description: "Temporary placeholder - will be replaced by real columns."
```

**Enrich/DW skeleton (with placeholder):**

```yaml
database_name: "datalake_xxx_yyy"
table_name: "table_name"
description: "TODO: business description with at least 10 characters."
domain: "For Rent"
owner: "owner@quintoandar.com.br"
columns:
  _placeholder:
    description: "Temporary placeholder - will be replaced by real columns."
    lineage:
      - "dummy.dummy.dummy"
```

**Metric skeleton (with placeholder):**

```yaml
database_name: "metric_xxx"
table_name: "table_name"
description: "TODO: business description with at least 10 characters."
domain: "For Rent"
owner: "owner@quintoandar.com.br"
columns:
  _placeholder:
    description: "Temporary placeholder - will be replaced by real columns."
    dimension: true
```


### Step 3 — FAIR: validate Findable metadata (F2-01, F2-02)

After the skeleton exists, run FAIR authoring checks on changed metadata (does **not** compare YAML to SQL; does **not** run I1-01):

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
```

Fix F2-01/F2-02 per **`fairness_metadata.mdc`**. For **bulk FAIR remediation or domain audits**, use **`fair-metadata`** — PLAN gate mandatory (`.cursor/skills/fair-metadata/reference/plan_gate.md`): post plan and stop; no metadata edits until user approves execution. Creating a **new** table skeleton in this skill is allowed; rewriting many files for FAIR is not — that goes through the plan workflow.

### Step 4 — Run validate-lineage-consistency (metadata ↔ SQL, sqlglot)

Woodpecker step **`validate-lineage-consistency`** — validates metadata `columns` against the paired SQL using **sqlglot** (works before the table exists in the metastore):

```bash
make validate-lineage-consistency
```

The output will include something like:

```
Columns in SQL query but missing in metadata: [col_a, col_b, col_c]
Columns in metadata but missing in SQL query: [_placeholder]
```

**Extract** the list `[col_a, col_b, col_c]` from the error message — these are the SQL columns.

### Step 5 — Update metadata with real columns

- Remove `_placeholder`
- Add each column from the list with `description` and, for enrich/dw, `lineage`; for metric, use `dimension: true` or `metric: { ... }` per column type
- Use "TODO" placeholders where needed to pass validation initially

### Step 6 — Validate in a loop

```bash
make validate-metadata-files-content
make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
```

Fix until all pass. Fill descriptions and lineage per [governance_metadata.mdc](.cursor/rules/governance_metadata.mdc) and [fairness_metadata.mdc](.cursor/rules/fairness_metadata.mdc).

### Special case: SQL with SELECT *

If `validate-lineage-consistency` fails with "SQL query uses SELECT * which prevents column validation", ask the user to replace `SELECT *` with explicit column names in the SQL before continuing.

---

## Step 1 - Identify layer and target file

1. Confirm the target layer from the file path:
   - `dags/{domain}/{dag_name}/metadata/raw/{table}.yml`
   - `dags/{domain}/{dag_name}/metadata/clean/{table}.yml`
   - `dags/{domain}/{dag_name}/metadata/core/{table}.yml`
   - `dags/{domain}/{dag_name}/metadata/enrich/{table}.yml`
   - `dags/{domain}/{dag_name}/metadata/dw/{table}.yml`
   - `dags/{domain}/{dag_name}/metadata/metric/{table}.yml`
2. Never create metadata for `reverse` layer.
3. Keep base filename equal to the SQL filename in `queries/{layer}/`.

## Step 2 - Fill mandatory metadata contract

Use this baseline in every file (team standard, even when schema marks fields optional):

```yaml
database_name: "..."
table_name: "..."
description: "Business description with at least 10 characters."
domain: "..."
owner: "name@quintoandar.com.br"
columns:
  column_name:
    description: "Column meaning and business context with at least 10 characters."
```

Quality rules:
- `description` must explain meaning, not repeat the field name.
- avoid generic descriptions like `"Table with data"` or `"Status column"`.
- keep `owner` in valid email format.
- ensure each SQL output column exists under `columns:`.

## Step 2.1 - Write high-quality descriptions

### Table description checklist

A good table description should answer:
1. what business entity or process the table represents;
2. which layer/business context it serves (analytics, reporting, monitoring, etc.);
3. grain (one row per contract, per ticket, per user-day, etc.);
4. main use cases and decision context.

Good table description examples:
- `"Contract-level summary table used for For Rent operational monitoring and conversion analysis, with one row per contract."`
- `"Weekly KPI table for customer support productivity, aggregated by analyst and week for performance tracking."`

Bad table description examples:
- `"Support table"`
- `"Metrics data about renting process"`

### Column description checklist

A good column description should include:
1. business meaning (what the field represents);
2. unit or format when relevant (currency, timestamp timezone, percentage);
3. calculation/logic intent when derived;
4. important caveats (nullable behavior, categorical meaning, filters).

Good column description examples:
- `"Monthly rent amount in BRL currency defined in the signed contract."`
- `"Timestamp in UTC when the ticket was first solved by the analyst."`
- `"Boolean flag indicating whether the contract was active at the end of the reference month."`

Bad column description examples:
- `"Rent value"`
- `"Created date"`
- `"Status"`
- `"… Persisted in the governance lake for lineage, documentation metrics, and FAIR assessments."` (platform filler — no business meaning)

## Step 3 - Apply layer-specific schema rules

### 3.1 Domain values by layer (must match exactly)

Use one exact value from the FAIR/CI allowlist ([`fairness_metadata.mdc`](../../rules/fairness_metadata.mdc), mirrored in [`governance_metadata.mdc`](../../rules/governance_metadata.mdc)):

`Agents`, `Atlas DB`, `Broker XP`, `Conversational XP`, `Cross`, `Data Life Cycle`, `Data Ops & Governance`, `Data Platform`, `DS Pricing`, `Fintech`, `For Rent`, `For Sale`, `Growth`, `House and Listing`, `International`, `Journey Optimizer`, `MLOps`, `People`, `QCX`, `Rede`, `Support and Services`, `Tech Platform`

### 3.2 Raw

- validator allows `description`, `columns`, and `owner` to be optional;
- repository standard: include all of them anyway;
- column supports:
  - `description` (recommended),
  - `categories` (optional),
  - `tags` (optional).

#### Raw and Clean — business context, keys, and table relationships

For raw and clean layers, metadata must provide enough business context for downstream consumers to understand the data model:

1. **Business context** — In the table `description`, explain:
   - what domain or process the table belongs to (e.g. rental contracts, support tickets, agent slots);
   - how the data is produced (CDC, API pull, batch job);
   - main use cases and who consumes it.

2. **Main keys and concepts** — In the table `description` or column `description`s, explicitly state:
   - primary key(s) and what they uniquely identify;
   - natural keys vs surrogate keys when relevant;
   - grain (one row per contract, per ticket, per user-day, etc.).

3. **Table relationships** — Document how this table relates to others in the same DAG or source:
   - foreign keys and which tables they reference (e.g. `id_contract` → `contract` table);
   - parent-child or one-to-many relationships;
   - join paths that downstream enrich/dw layers will use.

Good raw/clean table description example:
- `"Raw CDC mirror of the contract table from EBDB. One row per contract. Primary key: id_contract. Relates to user via id_user (FK to user), to house via id_house (FK to house). Used as source for contract enrich and DW fact tables."`

Good raw/clean column description for a key:
- `"Primary key. Unique identifier of the contract in the transactional source."`
- `"Foreign key to datalake_ebdb_clean.user. Identifies the tenant who signed the contract."`

### 3.3 Clean and Core

- required: `database_name`, `table_name`, `domain`, `description`, `columns`;
- `owner` is optional in `clean` and required in `core`;
- each column must have `description` with at least 10 chars;
- optional: `lineage`, `categories`.

### 3.4 Enrich and DW

- required: `database_name`, `table_name`, `owner`, `domain`, `description`, `columns`;
- each column must have `description` with at least 10 chars;
- **`lineage` is required** for every enrich/dw column — CI fails without it; format: `database.table.column`;
- optional: `categories`.

#### Enrich/DW description workflow for transformed columns

For each output column in enrich/dw:
1. identify all source columns used in SQL (`SELECT`, joins, CTEs, CASE, aggregations);
2. classify transformation type:
   - direct mapping (`target = source`),
   - renamed mapping,
   - business rule (`CASE WHEN`, filters),
   - aggregation (`SUM`, `COUNT`, `AVG`),
   - composite derivation (multiple sources);
3. write `lineage` with one or more `database.table.column` entries;
4. write description in this format:
   - **Meaning**: what this output represents for the business;
   - **How built**: key transformation logic in plain language;
   - **Source context**: where it comes from (main source domains/tables).

Recommended sentence pattern:
- `"Business meaning. Built by <transformation rule> using <source columns/tables>."`

Examples:
- Direct mapping:
  - Description: `"Unique identifier of the contract in the transactional source system."`
  - Lineage: `datalake_ebdb_clean.contract.id_contract`
- CASE/business rule:
  - Description: `"Lifecycle status bucket for contracts. Built by mapping raw status values into ACTIVE, CHURN_RISK, and CLOSED categories."`
  - Lineage: `datalake_ebdb_clean.contract.contract_status`
- Multi-source derivation:
  - Description: `"Net revenue in BRL after discounts. Built as gross rent amount minus negotiated discount using contract and proposal sources."`
  - Lineage:
    - `datalake_ebdb_clean.contract.rent_amount`
    - `datalake_ebdb_clean.proposal.discount_amount`
- Aggregation:
  - Description: `"Count of unique contracts signed during the week, aggregated by week_start_date."`
  - Lineage: `datalake_ebdb_clean.contract.id_contract`

### 3.5 Metric

- required: `database_name`, `table_name`, `owner`, `domain`, `description`, `columns`;
- each column must be exactly one of:
  - dimension column (`dimension: true`), or
  - metric column (`metric:` block with full metric metadata).
- metric block fields:
  - `name`, `description`, `acronym`, `is_additive`, `business_stage`, `hierarchy`, `approved_by`, optional `link_to_metric`.

## Step 4 — PII privacy (deferred — not for normal authoring)

**Skip this step** on routine metadata creation unless the user or ticket explicitly requests PII classification (dedicated governance PR).

When classification **is** explicitly requested, add a `privacy` section (never `personal_data_classification`):

```yaml
columns:
  cpf:
    description: "Brazilian CPF."
    lineage:
      - datalake_example_clean.person.cpf
    privacy:
      piiType: cpf  # slug in pii_catalog.yml
      dataSubjectType: [customer]      # customer | employee | partner
```

- **`customer`** → must be masked in authX after merge to `master` (unless RAE in `governance/pii_anonymization_controls/`).
- **`employee`** / **`partner` only** → classify PII, no Trino mask.
- Omit `privacy` entirely for non-PII columns.

### Defaults by domain (`dataSubjectType`)

Pick the slug from [`governance/pii_catalog/pii_catalog.yml`](../../governance/pii_catalog/pii_catalog.yml). Use these defaults when titular is obvious; otherwise ask the data owner.

| Context | Default `dataSubjectType` |
|---------|---------------------------|
| `People` domain, HR/employee tables, `dags/people/reverse_reports/` | `[employee]` |
| Agent / partner / 3P tables (`*_agent*`, broker, partner) | `[partner]` or `[partner, customer]` if end-customer data |
| Rent, sale, fintech, growth customer data | `[customer]` |
| RAE exception (mask waived) | `[customer]` + row in `governance/pii_anonymization_controls/rae.yml` |

**People pitfall:** do not use `[customer]` for employee CPF/email in HR exports — that triggers customer masking in authX.

LGPD controls (`table_privileges`, `k_anonymity`) live in the **declaration** or qube spec, not in metadata. When `privacy.piiType` is declared, use the catalog-derived tier; otherwise infer from domain rules and column semantics — see [governance_metadata.mdc](.cursor/rules/governance_metadata.mdc) → "Personal Data Handling".

## Step 5 - Use these templates

### Enrich/DW template

```yaml
database_name: "datalake_ebdb_contract"
table_name: "contract_summary"
description: "Contract-level summary used by analytics and monitoring."
domain: "For Rent"
owner: "owner@quintoandar.com.br"
columns:
  id_contract:
    description: "Unique contract identifier from the source transactional system."
    lineage:
      - datalake_ebdb_clean.contract.id_contract
  contract_status:
    description: "Current contract status in the contractual lifecycle."
    lineage:
      - datalake_ebdb_clean.contract.contract_status
    categories:
      ACTIVE: "Contract is currently active."
      CANCELED: "Contract has been canceled."
```

### Metric template

```yaml
database_name: "metric_rent"
table_name: "weekly_contract_kpis"
description: "Weekly KPI table for contract conversion and retention tracking."
domain: "For Rent"
owner: "owner@quintoandar.com.br"
columns:
  week_start_date:
    description: "Start date of the reporting week used as a grouping dimension."
    lineage:
      - dw_public.dim_date.dt_date
    dimension: true
  contracts_signed:
    description: "Count of unique contracts signed during each reporting week."
    metric:
      name: "Weekly Signed Contracts"
      description: "Total number of unique contracts signed per week."
      acronym: "WSC"
      is_additive: false
      business_stage: "Transaction"
      hierarchy: "Executive"
      approved_by: "owner@quintoandar.com.br"
      link_to_metric: "https://quintoandar.sa.looker.com/looks/1234"
```

## Step 6 - Validate in a fix loop

Run validation and iterate until green:

```bash
make validate-metadata-files-content
```

Run `make validate-pii-privacy` only when the diff already includes `privacy` blocks or `governance/pii_*` changes.

If validation fails:
1. read the exact field/type error and file path;
2. fix YAML keys, value formats, or metric/dimension structure;
3. rerun the command.

Recommended follow-up checks:

```bash
make validate-metadata-files-exist
make validate-lineage-consistency
```

## Common failure patterns

- `description too short`: use meaningful descriptions with at least 10 characters.
- `table_name / filename mismatch`: CI fails if `table_name` in YAML does not equal the file stem — rename the file to `{table_name}.yml` or update `table_name` to match the file name.
- `domain` regex mismatch: use an exact allowed domain for that layer (see [governance_metadata.mdc](.cursor/rules/governance_metadata.mdc)).
- `owner` regex mismatch: use a valid email format.
- metric column missing `dimension` or `metric`: add exactly one.
- **missing `lineage` on enrich/dw column**: CI fails; add `lineage: [database.table.column]` for every column.
- enrich/dw lineage inconsistency: align `lineage` entries with SQL selected columns.
- unexpected `personal_data_classification` key: **remove it** (CI rejects it). Do not add `privacy` unless the user requested classification.
- invalid `privacy` in diff: fix only when `privacy` is already present — see Step 4.
