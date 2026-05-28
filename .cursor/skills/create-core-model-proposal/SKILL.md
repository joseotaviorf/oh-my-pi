---
name: create-core-model-proposal
description: Interactively discover and plan a new Core Data Model — from entity scoping and eligibility check through source recommendation, pipeline design, and redundancy mapping. Produces a detailed proposal for the user to review before any implementation begins. Use when the user mentions "core model" alongside discovery, sources, new entity, proposal, or planning intent — e.g. "I want to create a core model for X", "should we have a core model for X?", "help me discover sources for a new core model", "what would a core model for X look like", "core model proposal", "identify entity for core model", "core model sources", or "evaluate if X needs a core model". Also use when the user asks to plan or design a new core layer entity without yet being ready to implement.
---

# Core Model Proposal

## When to use

When a user has an entity concept (e.g. "I think we need a core model for Payment") and wants
to evaluate feasibility, identify the right sources, design the pipeline structure, and
understand what becomes redundant — without writing any code yet. The skill produces a proposal only; the user decides what to do with it.

---

## Step 0 — Prior knowledge check

Before asking anything else, use `AskQuestion` with a single free-text prompt:

> "Before we begin, share any prior knowledge that could help the discovery — for example:
> - Candidate source tables you already have in mind (e.g. `datalake_ebdb_clean.{table}`)
> - A relationship to an existing core model you've noticed (e.g. "I think this belongs in `core_contract`")
> - A grain definition you're leaning toward (e.g. "one row per contract end event")
> - A duplication pattern or pain point you've already mapped
>
> If you're starting from scratch, just say so and we'll discover everything together."

Use the answer to seed the rest of the flow:

| User says | How it changes downstream steps |
|-----------|----------------------------------|
| Names specific source tables | Use them directly as seeds in Step 3 subagents; skip or narrow the blind source scan |
| Points to an existing core model | Use that as the starting hypothesis in Step 2 eligibility gate (validate rather than discover) |
| Describes the grain | Pre-fill the natural key proposal in Step 4 and suggest options if applicable|
| Describes a duplication pattern | Prioritise those DAGs in Subagent A and Step 5 redundancy scan |
| "Nothing to declare" / "starting from zero" | Proceed with the full natural flow — no changes to Steps 1–6 |

---

## Step 1 — Collect entity context

Use `AskQuestion` to gather the three inputs below before doing any analysis:

- **Entity name/concept** — the business object being considered (e.g. "termination", "payment", "agent")
- **Business domain** — e.g. For Rent, For Sale, Fintech, Platform
- **Motivation** — why this entity needs a core model now (pain point, duplication signal, new use case)

If the user already provided some of this context in their message, pre-fill and confirm rather than re-asking.

---

## Step 2 — Run the eligibility gate

Present the five criteria from the Core Data Models framework as structured questions via `AskQuestion`:

| Pillar | Question |
|--------|----------|
| Sources | Can this entity be generated using only product sources or a foundational core model? |
| Sources | Are there multiple independent sources for this same entity, making it hard to identify the canonical one? |
| Reusability | Is this entity consumed by more than one business line or domain? |
| Maturity | Is this entity stable enough for a durable surrogate key and schema over the next few years? |
| Purpose | Will the core model feed only other pipelines — not BI reports or ad-hoc queries directly? |

Also assess whether the entity is **inherently dependent on an existing core entity**. A sub-entity or lifecycle state of an existing model belongs inside that model, not in a new one. Cross-reference the current core models:

Scan the current set of core models by enumerating all entities with a corresponding folder under `dags/core/`. Use this up-to-date list to cross-reference whether the proposed entity already exists or should be handled as an extension to an existing model.

Based on the gate answers, issue **one of three recommendations**:

| Outcome | Condition | Action |
|---------|-----------|--------|
| **Proceed — new core model** | All five criteria met; entity is independent | Recommend a standalone `core_{entity}` |
| **Proceed — extend existing model** | Entity is a sub-entity or tightly coupled to an existing core entity | Recommend adding a table or columns to `core_{parent}` |
| **Do not create** | Entity is too context-specific, domain-scoped, or better served by an enrich/dw table | Recommend against a core model; name the appropriate alternative layer |

State the reasoning explicitly. Then ask: _"Do you want to continue with the original proposal, adjust scope, or accept this recommendation?"_

**User sovereignty**: if the user insists on proceeding despite a negative or redirect recommendation, continue without further objection. State the disagreement once, then move forward.

---

## Step 3 — Launch discovery subagents

Run discovery in **two sequential waves**. Within each wave, launch the subagents in parallel using the `Task` tool with `subagent_type: explore`. Wave 2 cannot start until Wave 1 returns, because Subagents C and D need the canonical list of candidate clean source tables produced by Wave 1.

### Wave 1 — Discover the source landscape (parallel: A + B)

Seed both with the entity name, any candidate source tables from Step 0, and the business domain from Steps 1–2.

**Subagent A — Repeated logic scan** (`subagent_type: explore`):

Search for references to the candidate source tables, restricting to the three layers allowed as core model sources:

| Layer | Table pattern | Search locations |
|-------|--------------|-----------------|
| CLEAN | `datalake_{source}_clean.{table}` | `.sql` files under `dags/` |
| TRANSACTIONAL | `datalake_{domain}_transact_clean.{table}` or `datalake_{product}_transactional.{table}` | `.sql` files under `dags/` |
| CORE | `core_{context}.{table}` | `.sql` files under `dags/` |

Also scan existing conf files (`dags/core/*/spark_jobs/*_conf.yml`) to find how sibling core models reference the same source tables.

Return contract:
- File path, line number, and 2 lines of surrounding context for every SQL match, grouped by layer
- DAG name (parent folder of the SQL file) for each match
- Duplication signal: whether the same join/enrichment logic for this entity appears in multiple independent DAGs (list the DAG names)
- Any manual surrogate key generation patterns (`SHA2(CONCAT(...), 256)`) applied to the entity's natural key — include file path and line number
- Conf file entries from sibling core models that reference the same source tables (shows established precedent)

**Subagent B — Lineage trace** (`subagent_type: explore`):

Locate existing materializations of the entity (e.g. `dw_*.dim_{entity}`, `enrich_*_{entity}`). Combine two evidence sources:

1. **Governance metadata** — read `dags/*/metadata/{layer}/*.yml` files for the entity. The `lineage:` field on each column already encodes structured upstream references (`{database}.{table}.{column}`). Prefer this over re-parsing SQL when the metadata exists.
2. **SQL files** — for tables without complete metadata, parse `.sql` files in `dags/*/queries/{layer}/` to extract `FROM`/`JOIN` references.

Trace backwards through layers: DW → Enrich → Clean → Raw. For each layer return:
- DAG name and SQL file path
- Metadata YAML path (if found) and the column-level `lineage:` entries
- Natural primary key used at that layer (`id_*` column)
- Any manual surrogate key generation (file path + line number)
- Filtering, deduplication, or enrichment logic that is repeated across consumers

### Synthesis between waves

After Wave 1 returns, consolidate the **canonical candidate clean source tables** by merging:
- Tables provided by the user in Step 0 (if any)
- Tables found by Subagent A in CLEAN/TRANSACTIONAL searches
- Clean-layer tables surfaced by Subagent B's lineage trace (from both metadata and SQL)

**If Wave 1 returns an empty consolidated list**, do not proceed to Wave 2 blindly. Pause and report back to the user: either (a) the entity has no existing materialization in the repo (treat as a true greenfield model — ask the user to provide candidate source tables before proceeding), or (b) the search patterns missed it (review the entity name and domain, then optionally re-run Wave 1 with broader patterns).

This consolidated list is the input for Wave 2.

### Wave 2 — Audit the candidate sources (parallel: C + D)

Both subagents receive the canonical list from the synthesis step.

**Subagent C — Source table audit** (`subagent_type: explore`):

For each candidate clean source table, check whether a natural audit timestamp column exists (`ts_updated`, `ts_database_transaction`, or equivalent). Sources of truth, in priority order:
1. The clean table's metadata YAML (`dags/*/metadata/clean/{table}.yml`) — column list with descriptions
2. The SQL that materializes the clean table (`dags/*/queries/clean/{table}.sql`)

Return contract:
- Table name
- Audit timestamp column (if found) — include the metadata YAML path and column block
- Absence flag if no audit timestamp exists
- Verdict: `incremental` or `full` extraction appropriate, with a one-line justification

**Subagent D — Consumer pre-scan** (`subagent_type: explore`):

Find all DAGs that read from the candidate clean source tables. Combine two evidence sources:

1. **`dags/dependencies.yaml`** — auto-generated canonical dependency graph. Look up DAG-level dependencies on the source tables' producing DAGs. This is the fastest and most authoritative consumer list.
2. **SQL scan** — supplement with `.sql` file references in `dags/*/queries/` to catch consumer DAGs that may not yet appear in the dependency graph (e.g. very recent additions).

Return contract:
- DAG name and SQL file path for each consumer
- Layer of the consumer DAG (enrich / dw / metric)
- What each consumer does with the entity data (simple pass-through, aggregation, enrichment) — one-line description per consumer

---

## Step 4 — Propose data sources and pipeline design

Synthesize subagent results and present the following to the user for confirmation. Ask the user to approve or adjust before continuing to Step 5.

**Proposed data sources** (one row per source table):

| Key in conf | Layer | Table | Role |
|-------------|-------|-------|------|
| `{ENTITY}_TABLE` | CLEAN / CORE / TRANSACTIONAL | `datalake_*.{table}` | primary |
| `{OTHER}_TABLE` | … | … | enrichment / lookup |

Only reference tables from allowed conf layers: `CLEAN` (`datalake_{source}_clean.{table}`), `CORE` (`core_{context}.{table}`), or `TRANSACTIONAL` (`datalake_{domain}_transact_clean.{table}` or `datalake_{product}_transactional.{table}`). Never point at enrich, dw, metric, or raw layers.

**Proposed pipeline design:**

| Field | Value |
|-------|-------|
| Entity type string | `{ENTITY}` (UPPERCASE) |
| Metastore schema | `core_{entity}` |
| Natural primary key | `id_{entity}` (source: `{table}.{column}`) |
| Surrogate key | `sk_core_{entity}` via `SurrogateKeysHelper` |
| Extraction type | `incremental` / `full` — justified by Subagent C |
| Merge condition | `source.ts_updated > target.ts_updated` (incremental only) |
| Partitions | `year`, `month`, `day` |
| Change Data Feed | `delta.enableChangeDataFeed: true` |
| History table needed | Yes / No — flag if CDC source exists |

**Suggested column list** (ordered per naming conventions):

| Column | Type | Source | Notes |
|--------|------|--------|-------|
| `sk_core_{entity}` | string | generated | surrogate key — always first |
| `id_{entity}` | bigint / string | `{source}.{column}` | natural PK |
| … | … | … | business characteristics |
| `ts_load` | timestamp | `current_timestamp()` | no lineage entry needed |
| `year` | int | `ts_updated` | partition |
| `month` | int | `ts_updated` | partition |
| `day` | int | `ts_updated` | partition — always last |

**Declaration skeleton** (for reference, not for creation):

```yaml
workflow:
  type: core_model
  layer: core
  default_extraction_type: incremental   # or full
  load_spark_job: load_core_{entity}
  execution_timeout_hours: 1
  tables_customization:
    {entity}:
      partitions: [year, month, day]
      z_order_by: [id_{entity}]
      table_properties:
        "delta.enableChangeDataFeed": "true"

cluster:
  type: databricks_16_4_rfleet_instance_cluster
  databricks_conn_id: databricks_new
```

---

## Step 5 — Map redundancies

Using Subagent D results, plus targeted follow-up explore subagents if the consumer list is large, produce a redundancy report with the following sections:

Layer priorities for this analysis:

| Layer | Primary action | Secondary action |
|-------|---------------|-----------------|
| **enrich** | Removal — fully redundant enrich tables are the main target | Migration — enrich tables that add domain-specific logic on top may survive but must switch source |
| **clean** | Removal — intermediate clean tables or derived columns that become unnecessary | — |
| **dw** | Migration only — DW tables are domain-specific and will not be deleted, only re-pointed | — |

**Enrich layer — removal candidates** _(primary focus)_:

| DAG | Table | Overlap with core model |
|-----|-------|------------------------|
| `{dag_name}` | `enrich_*.{table}` | Description of overlap |

**Enrich layer — migration candidates** _(tables that survive but must switch upstream source)_:

| DAG | Table | Current source | Change needed |
|-----|-------|---------------|---------------|
| `{dag_name}` | `enrich_*.{table}` | `datalake_*_clean.{table}` | Replace with `core_{entity}.{entity}` |

**Clean layer — removal candidates**:

| DAG | Table / column | Overlap or derived logic that becomes redundant |
|-----|---------------|------------------------------------------------|
| `{dag_name}` | `datalake_*_clean.{table}` | Description |

**Redundant columns** _(enrich and clean layers — derived fields the core model will centralise)_:

| Layer | DAG | SQL file | Column(s) | Current derivation |
|-------|-----|----------|-----------|-------------------|
| enrich | … | … | … | e.g. `SHA2(CONCAT(id_house, ...), 256) AS sk_house` |
| clean | … | … | … | … |

**DW layer — source migrations only** _(tables are not removed; they switch upstream source)_:

| DAG | Current source | Change needed |
|-----|---------------|---------------|
| `{dag_name}` | `enrich_*.{table}` | Replace with `core_{entity}.{entity}` |

**Migration checklist** (following the Core Data Models framework):

- [ ] Identification & Mapping — confirm all impacted assets are listed above
- [ ] Ideation — draft RFC describing the entity, sources, final tables, and migration deadline
- [ ] Review — schedule Data Design Review session to align with impacted teams
- [ ] Development & Validation — implement core model, validate results, set replacement deadline
- [ ] Communication — announce go-live and deprecation deadline to downstream owners

**Verification commands** the user can run independently:

```bash
# Find all SQL files referencing the candidate source table
rg "{source_table}" dags/ -g "*.sql" -l

# Find manual surrogate key generation for this entity
rg "SHA2.*id_{entity}" dags/ -g "*.sql" -l

# Find all metadata lineage entries pointing to the source table
rg "{source_table}" dags/ -g "*.yml" -l
```

---

## Step 6 — Present the final proposal

Present the complete proposal directly in the chat as a well-structured Markdown document — using clear section headings, tables for tabular data (sources, columns, redundancy), and code blocks for SQL or YAML snippets. Tailor the content to the recommendation from Step 2:

**If "Proceed — new core model":**
1. Entity definition and eligibility verdict (all five criteria, pass/flag status)
2. Proposed data sources table
3. Pipeline design (declaration skeleton, conf keys, column list)
4. Redundancy report (redundant tables, columns, DAGs to migrate)
5. Migration checklist and verification commands
6. Next steps → use `core_models_generation.mdc` (auto-loads in `dags/core/`) for implementation scaffolding, then the `create-dag` skill to generate files

**If "Proceed — extend existing model":**
1. Entity definition and rationale for extension over a new model
2. Which existing model to extend (`core_{parent}`) and how — new auxiliary table vs. new columns on the main table
3. Proposed additions with column types, ordering, and lineage
4. Impact on existing downstream consumers of `core_{parent}.{parent}`
5. Next steps → open `dags/core/core_{parent}/` and apply changes following `core_models_generation.mdc`

**If "Do not create" (or user overrode the recommendation):**
1. Entity definition and the specific reasons the skill flagged it (criterion that failed, or context-specificity concern)
2. Recommended alternative layer and a concrete suggestion (e.g. `enrich_{domain}_{entity}` or `dw_{domain}.dim_{entity}`)
3. If the user overrode: include the full "Proceed — new core model" proposal above, prefaced with a brief note that the skill's assessment differed and the user chose to proceed

Close every proposal with: _"This is a proposal only. No files have been created or modified."_

---

## Notes

- This skill produces a proposal only — no files are created, no assets are deprecated.
- The skill may recommend against creating a new core model. This is a first-class outcome, not an error state.
- The skill may recommend extending an existing model instead. Current models to cross-reference are in `dags/core/`.
- **User sovereignty**: if the user overrides any recommendation, continue without further objection. State the disagreement once, clearly, then proceed.
- For implementation after the proposal is accepted, use `core_models_generation.mdc` (auto-loads in `dags/core/`) together with the `create-dag` skill.
- For ongoing downstream tracking after implementation, use the `impact-analysis` skill.
- The repo has over 770 DAGs. Always use parallel subagents for discovery — sequential search is too slow.
