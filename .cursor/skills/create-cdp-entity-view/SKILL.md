---
name: create-cdp-entity-view
description: Creates a new CDP entity (also called "object" / "objeto") view in enrich_entities_views (bi-etl-ejuice) and enables the corresponding business type in Datazord (backend-services) so the new entity is visible in consumable endpoints. Operates on two repositories; entities come from the data lake via CDF (business-objects topic), not from a stream processor. Collects entity name, business context, personas, properties, and fast_lane prerequisites; generates SQL, metadata, entities.sql, manual_modifications, entities.yml, and Datazord enum/OpenAPI/label-rules/tests. Use when adding a new entity/object to the CDP entities model or enrich_entities_views.
---

# Create CDP Entity View (enrich_entities_views)

This skill makes changes in **two repositories**: **bi-etl-ejuice** and **backend-services** (Datazord). **Both must be open in the same Cursor workspace.**

- **bi-etl-ejuice:** entity view SQL, governance metadata, `entities.sql` wiring, `manual_modifications.yaml`, `entities.yml`.
- **backend-services (Datazord):** BusinessType enum, OpenAPI filter, label rules, tests. Datazord is the **reverse-ETL** that exposes entities via **consumable endpoints** (MCP tools, agents, chatbots).

The DAG **enrich_entities_views** creates **materialized views**, not physical tables. Each view is evaluated on demand when `enrich_transactional_entities` runs.

**Interaction:** Run the information-gathering phase **like a bot**: ask **one question at a time** (or at most two when closely related), wait for the answer, then move to the next.

**Language consistency:** Always speak to the user in the **same language they are using** (e.g. if they write in Portuguese, respond entirely in Portuguese). Technical terms like `fast_lane`, `business_context`, column names, etc. stay in their original form (code), but all surrounding text — questions, confirmations, summaries — must be in one consistent language. **Never mix** (e.g. don't say "SALE only — entity column será FS_DILIGENCE").

## When to use

- User asks to add a new **entity** or **object** to the CDP, to enrich_entities_views, or to the entities model.
- User wants a new table/view in the DAG `enrich_entities_views` (e.g. offer, inspection_booking).
- **Terminology:** "entity" and "object" (or "entidade" / "objeto" in Portuguese) refer to the same concept in this context. Treat both as synonyms throughout the flow.

## Step 0 — Two-repo scope and entity context

**First, tell the user (mandatory):**

> This flow creates/updates files in **two repos**: **bi-etl-ejuice** (entity view, metadata, entities table, dependency exceptions) and **backend-services** (Datazord — enables the new business type in APIs).

> Entity data comes from the **data lake via CDF** into the business-objects topic; **no stream processor** is needed. Both repos must be open in your Cursor workspace (multi-root).

**Then, give a short context on what an "entity" is** (use your own words):

> The **entities table** provides a unified view of customer interactions and transactions. It is updated every 30 minutes and feeds **AI initiatives** (chatbots, Conv XP) with a standardized customer-journey format.

> **What IS an entity:** A concrete transactional touchpoint in the user journey — visit, offer, CCV, inspection, contract, termination, reservation, photo session, house draft, listing, etc.

> **What is NOT an entity:** User attributes, segments, scores, or computed profiles (e.g. "PP multi", "IQ high ticket", number of contracts). Entities are things that **happen or exist in the product**, not derived user features.

After this context, say you'll guide them step by step and move to Step 1.

## Step 1 — Gather information (conversational)

**Interaction style:** Ask **one question at a time**. Wait for the answer before moving to the next.

**Order** — follow this sequence:

| # | Topic | What to do |
|---|--------|------------|
| 1 | **Entity name** | Ask: "What is the entity name?" Accept free text in any language or format. **You** normalize it: translate to English if needed, convert to `snake_case`, strip `FS_`/`FR_` prefixes. Examples: "FS_Diligence" → `diligence`; "photo session" → `photo_session`. **Multiple entities:** if the user provides more than one name (e.g. "collections e evictions"), treat each as a **separate entity**. Tell the user you will run the full flow (Steps 1–7) for one entity at a time, then loop back for the next. Start with the first one. After normalization, **confirm** the final name with the user and **check if it already exists** (see 1.1). If it exists, **skip and move to the next**. |
| 2 | **Business context** | Ask whether this entity is only for RENT, only for SALE, for both, or not defined yet. RENT-only → `FR_` prefix; SALE-only → `FS_` prefix; both/unknown → no prefix. See [reference.md — Entity name and business_context](reference.md#entity-name-column-entity-and-business_context). |
| 3 | **30-min and fast_lane** | Provide short context explaining that entity views run every 30 min and source tables ideally should be updated at the same cadence by a `fast_lane` or equivalent DAG. Then ask whether such a pipeline already exists for the source tables. See 1.3 for decision tree. |
| 4 | **Source table** | Ask if the user knows which source table (and DAG) to use. Validate the answer per 1.4. |
| 5 | **Personas** | Ask which personas this entity has (give examples: OWNER, TENANT_PROSPECT, AGENT_BROKER). Tell the user they can answer in any language — you translate to canonical UPPERCASE. See [reference.md — Personas](reference.md#personas-canonical-list-and-rules) for canonical list. |
| 6 | **Properties (JSON)** | Explain that properties are used as labels for agents (chatbots) and should be aligned with product + Conv XP. Ask which fields to include (e.g. status, when, what). If they include status, note that label-rules mapping will be handled in Datazord step (3.6). |

**Rules:** Do not assume. If ambiguous, ask one clarifying question.

---

### 1.1 Entity name: normalization and existence check

- **Normalize:** translate to English if needed, convert to `snake_case`, strip any `FS_` / `FR_` prefix. The base name must be pure English snake_case (e.g. "FS_diligence" → `diligence`; "collections e evictions" → `collections_and_evictions`; "photo session" → `photo_session`). Prefix is derived from business context, never from user input.
- **Check if already exists:** look for `dags/growth/enrich_entities_views/queries/enrich/<entity_name>.sql`, `metadata/enrich/<entity_name>.yml`, or a CTE named `<entity_name>` in `entities.sql`. If found → tell the user and **stop**.

### 1.2 Business context

- RENT-only → `FR_` prefix, `business_context = 'RENT'`. SALE-only → `FS_` prefix, `business_context = 'SALE'`. Both/unknown → no prefix, source column or NULL. See [reference.md — Entity name and business_context](reference.md#entity-name-column-entity-and-business_context).

### 1.3 30-min cadence and fast_lane

- If **no fast_lane exists** and user **does not ask to create one**: get explicit confirmation they are aware the entity won't update every 30 min. Then proceed with source selection. Add a cadence comment at the top of the generated SQL (see 3.1).
- If **no fast_lane exists** and user **asks to create one**: explain that this must be a **separate PR first** (upstream pipeline), merged and validated on Forno before the entity-view PR. Do not bundle both in the same PR — the entity view would reference a pipeline/table that does not yet exist in runtime. Use the `create-dag` skill for the upstream pipeline, then resume this skill after.

### 1.4 Source table

- **If user knows the source:** validate before using:
  - Views should read from **core** or **clean** (not enrich). If enrich, ask for the underlying core/clean.
  - Check cadence: if the DAG runs only once/day and user said there is a fast_lane, flag the mismatch. If no fast_lane, remind them and get confirmation.
- **If user does not know:** search (core_ first, then clean), propose candidates, confirm.

## Step 2 — Immutable output schema

Every entity view must output exactly **11 columns** in order. See [reference.md — Immutable column schema](reference.md#immutable-column-schema-output-of-each-view) for the full table with types.

Key rules:
- **Unique key:** `(id_entity, id_user, persona)`. One entity → N rows (one per persona).
- **SALE entities:** `id_contract` must be **NULL** — do not join/derive it.
- `sk_entity` and `ts_inactive` do **not** exist in the view — they are generated in `entities.sql`. The view only outputs the 11 columns. However, both **require lineage updates** in entities.yml (see 3.5).

## Step 3 — Generate files

**Execution order (mandatory):** `3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6`. Do not skip sub-steps.

**Note:** `enrich_entities_views` discovers tasks dynamically from files under `queries/enrich/` and `metadata/enrich/`, so there is no need to regenerate `_dag.py` during this step. DAG file generation is handled later during local testing (Step 5).

### 3.1 SQL query

- Path: `dags/growth/enrich_entities_views/queries/enrich/<entity_name>.sql`.
- Pattern: CTE(s) building a **base** with all source columns; then `SELECT ... id_user, entity, persona, ...` per persona with `UNION ALL`. The final output must have exactly the 11 columns in order.
- Follow SQL conventions (UPPERCASE keywords, snake_case, no `SELECT *`, partition/date filters when applicable). Prefer core_ over clean when a core model exists.
- **SALE entities:** `id_contract` = NULL; do not join/derive.
- **Source not fast_lane/core:** add comment at top: `-- Source: not fast_lane/core; entity is not updated every 30 mins. Revisit if 30-min cadence is needed.`

**Do not assume what you don't know.** Use inline TODO comments for unknowns:

- **is_active:** if unclear which statuses mean "in progress", add `-- TODO: define is_active; confirm which values mean active vs finished` and use `NULL AS is_active` or a placeholder CASE.
- **id_user / persona:** if the source has no explicit id per persona, add `-- TODO: id_owner not in source; consider joining to house/contract` and inform the user.

### 3.2 Governance metadata

- Path: `dags/growth/enrich_entities_views/metadata/enrich/<entity_name>.yml`.
- Required: `database_name: datalake_entities_views`, `table_name: <entity_name>`, `description` (≥10 chars), `domain: Growth`, `owner: your.email@quintoandar.com.br` (placeholder). Each column needs `description` and `lineage`. Follow existing examples (e.g. `photo_session.yml`, `listing.yml`).

### 3.3 Wire into entities.sql

- File: `dags/growth/enrich_transactional_entities/queries/enrich/entities.sql`.
- Add a CTE selecting from `datalake_entities_views.<entity_name>` with the 11 view columns. Add `WHERE id_user IS NOT NULL` if appropriate.
- Add a `UNION ALL` block in the `base` CTE. Copy the same pattern as existing entities — the `{sk_entity}` template param is auto-generated by the DAG at runtime; just replicate it as-is from an existing block.
- SALE-only: `id_contract` remains NULL in this path too.

### 3.4 Dependency exceptions (manual_modifications.yaml)

- File: `dags/dependency_exceptions/manual_modifications.yaml`.
- See [reference.md — Source tables → dependency entries](reference.md#source-tables--dependency-entries-manual_modificationsyaml) for the full pattern (core vs clean, task ID format, examples).
- **A)** Under `bietlejuice.enrich_entities_views:` → `remove:`, add one entry per source table used in the view (no duplicates).
- **B)** Under `bietlejuice.enrich_transactional_entities:` → `remove:`, add `bietlejuice.enrich_entities_views:load-enrich-<entity_name>:first-run-of-day`. Views must **never** be a dependency of enrich_transactional_entities.

### 3.5 Entities table metadata (entities.yml)

- File: `dags/growth/enrich_transactional_entities/metadata/enrich/entities.yml`.
- **Lineage:** add `datalake_entities_views.<entity_name>.<column>` to the relevant columns.
  - **`ts_inactive`:** derived in `entities.sql` as `CASE WHEN is_active = FALSE THEN ts_updated ELSE NULL END`. Its lineage should reference `datalake_entities_views.<entity_name>.ts_updated`.
  - **`sk_entity`:** composed from the columns that identify the row. Add the source columns that feed `entity`, `id_entity`, `id_user` (or similar - id_buyer, id_owner, one per persona), and `persona` — e.g. `datalake_entities_views.<entity_name>.id_entity`, `.id_user`, `.entity`, `.persona`, plus the underlying source columns like `core_<source>.<table>.id_<persona>`.
- **entity.categories:** add new entry (e.g. `FS_CCV: ...`).
- **is_active description:** add one line if the new entity has specific active/inactive rules.
- **YAML safety:** do not put an unquoted colon+space in the middle of a description line. Rephrase or quote.
- Follow existing format (same indentation as house_draft / photo_session).

### 3.6 Enable the new entity in Datazord (backend-services)

After bi-etl-ejuice files are done, enable the new business type in Datazord. See [reference.md — Datazord enable](reference.md#datazord-enable-backend-services) for file paths, naming rules, and examples.

**Naming:** entity column value = Datazord enum name; lowercase = value string.
- RENT: `FR_OFFER` / `fr_offer`. SALE: `FS_CCV` / `fs_ccv`. No prefix: `VISIT` / `visit`, `PHOTO_SESSION` / `photo_session`.

**Files to update** (all in backend-services):

1. **BusinessType.kt** — add enum entry (alphabetical within groups).
2. **openapi.yaml** — append to `BusinessFilter.businessTypes` enum.
3. **Label rules** — this is a **deferred gathering step**: the agent must ask the user about status→label mapping here, because this depends on what was generated in the SQL. See the decision tree below.
4. **UserContextMapperTest.kt** — add to `allBusinessTypes` + `expectedStrings`.
5. **Verification (optional):** `./gradlew :app:containers:api:test --tests '*UserContextMapperTest*'`

**Label rules decision tree:**
- **If view has status in properties:** ask the user: "For label rules, I need status values → label mappings. Do you have them? If not, I can search the repo or add a placeholder."
  - User provides → add full mappings.
  - User defers → try to discover in bi-etl-ejuice (DW/enrich metadata with `categories` for the same source column). If found, add inferred mappings and tell user. If not found, add placeholder and tell user what to fill.
- **If view has no status:** do not add label rules; state that in output.

## Step 4 — Checklist before finishing

- [ ] Duplicate check done first; entity does not already exist.
- [ ] Entity name is normalized (no double prefix like `FS_FS_`).
- [ ] Query outputs exactly the 11 columns in order; unique key `(id_entity, id_user, persona)`.
- [ ] SALE-only entities: `id_contract` is NULL in the view and in entities.sql.
- [ ] Metadata: lineage for all columns; description ≥10 chars; owner placeholder set.
- [ ] entities.sql: new CTE + UNION ALL in `base`. `{sk_entity}` replicated from existing pattern.
- [ ] entities.yml: lineage from `datalake_entities_views.<entity_name>` added; `sk_entity` lineage includes composing columns (entity, id_entity, id_user, persona + source); `ts_inactive` lineage references `ts_updated`; new entity category added.
- [ ] manual_modifications.yaml: (A) every source table has entry under `enrich_entities_views.remove`; (B) new view task under `enrich_transactional_entities.remove`.
- [ ] User reminded about properties alignment + fast_lane prerequisite.
- [ ] **Datazord:** BusinessType, openapi, label rules (full/placeholder/not applicable), UserContextMapperTest updated.
- [ ] Any `-- TODO` / placeholder listed in wrap-up as pending action.

## Step 5 — Local testing (bi-etl-ejuice)

After all files are generated, offer to guide the user through local testing. If the user declines, skip to Step 6.

**Delegate generic steps to the `run-dag-locally` skill.** This skill only documents what is **specific** to the entity creation flow. For session activation, environment checks, AWS credentials, uploading, selective sync, Astro restart, triggering, and monitoring, follow `run-dag-locally` Steps 0–8.

### Entity-specific details for `run-dag-locally`

**Step 1 (Generate DAG files):** generate for **both** DAGs:

```bash
make create-dag-files dag_name=enrich_entities_views
make create-dag-files dag_name=enrich_transactional_entities
```

**Step 2 (Upload):** only SQL queries changed → `make upload-local-queries`.

**Step 3 (Selective sync):** copy **both** DAGs in a single sync — `dags/growth/enrich_entities_views/` **and** `dags/growth/enrich_transactional_entities/`. One restart covers both.

**Step 4 (Verify):** confirm both DAGs have `has_import_errors: false`. For `enrich_entities_views`, list tasks and confirm `create-query-view-enrich-<entity_name>` appears (not `load-enrich-`; `query_view` workflow uses the `create-query-view-` prefix).

**Step 5 (Trigger) — execution order matters:**
1. Trigger `bietlejuice.enrich_entities_views` **first**. Wait until `state` = `success`.
2. Only then trigger `bietlejuice.enrich_transactional_entities`. The entities DAG reads from the view — if it runs before the view exists, it fails.

**Validation query** — after both DAGs succeed, verify the new entity in Databricks Forno:

```sql
SELECT
    id_entity,
    id_user,
    persona,
    entity,
    business_context,
    properties,
    is_active
FROM
    datalake_transactional_entities.entities
WHERE
    entity = '<ENTITY_COLUMN_VALUE>'
LIMIT 10
```

Replace `<ENTITY_COLUMN_VALUE>` with the entity column value (e.g. `FS_DILIGENCE`). If rows appear with the expected data, local testing is complete.

## Step 6 — Production deploy and Datazord testing

### 6.1 bi-etl-ejuice: first production deploy

After merge, manually trigger **enrich_entities_views** once so the view exists. If `enrich_transactional_entities` runs before that, it will **fail** (view not found).

### 6.2 backend-services (Datazord) — local testing

Offer to test locally. If the user declines, skip to Step 7.

**Check Java 17:** run `java -version` automatically. If not available, guide `sdk install java 17.0.12-tem` or check `.sdkmanrc` in the datazord directory.

**Run targeted tests** from `backend-services/applications/datazord`:

```bash
unset CI && ./gradlew :app:containers:api:test --tests '*UserContextMapperTest*'
```

If label rules were added in Step 3.6, also run:

```bash
unset CI && ./gradlew :app:core:test --tests '*BusinessObjectLabelService*'
```

No Docker or server startup needed — these are pure unit tests.

If tests pass, Datazord is validated locally. **Staging (after merge):** merging triggers automatic staging deploy. Validate the new business type in user-context/business-objects APIs.

## Step 7 — Wrap-up with the user

**After file generation and local testing (or skip), present a structured summary with the following sections.** Use the user's language consistently.

### 7.1 Files generated

List all created/modified files grouped by repo, with a one-line description of what was done in each.

### 7.2 Pending items (TODOs)

List every `-- TODO` left in the SQL, every placeholder (e.g. email in metadata), and any decision deferred during information gathering. Be explicit about what the user needs to resolve before merging.

### 7.3 Local testing result

If Step 5 was executed, summarize the outcome: which DAGs succeeded, whether the entity appeared in the validation query, and any issues encountered. If Step 5 was skipped, note that local testing was not performed.

### 7.4 Next steps

Present as a numbered checklist:

1. **Resolve TODOs** — fill in `is_active` logic, label-rules mappings, owner email, etc.
2. **Review generated code** — all generated code may contain placeholders, assumptions, or errors. The user must review and validate before merging.
3. **Local testing (if not done)** — if Step 5 was skipped, recommend running it before merging. Use the `run-dag-locally` skill for guidance.
4. **bi-etl-ejuice: first production deploy** — after merge, manually trigger `enrich_entities_views` once so the view exists before `enrich_transactional_entities` runs (otherwise it will fail with "view not found").
5. **backend-services (Datazord):** run unit tests locally (`./gradlew :app:containers:api:test --tests '*UserContextMapperTest*'`). After merge, staging deploy is automatic — validate the new business type in user-context/business-objects APIs.
6. **If fast_lane/core needs to be created:** remind the user of the **two-PR strategy** — upstream pipeline PR merged and validated on Forno first; entity-view PR comes after. Bundling can break entities runtime.

## Reference

- Full column schema, naming rules, persona list, dependency patterns, Datazord naming/paths, testing commands: [reference.md](reference.md).
- Example view and metadata: `dags/growth/enrich_entities_views/queries/enrich/photo_session.sql`, `metadata/enrich/photo_session.yml`.
