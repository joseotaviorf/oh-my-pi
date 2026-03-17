# Create Entity View — Reference

## Immutable column schema (output of each view)

| # | Column           | Type     | Description |
|---|------------------|----------|-------------|
| 1 | id_entity        | any      | Primary identifier of the entity (e.g. id_offer, id_visit, id from source table). |
| 2 | id_house         | BIGINT   | House ID if the entity is linked to a property; NULL otherwise. |
| 3 | id_contract      | BIGINT   | Contract ID if the entity is linked to a contract; NULL otherwise. For SALE entities (business_context = 'SALE'), always NULL. |
| 4 | id_user          | BIGINT   | User ID for this row; one row per (id_entity, id_user, persona). |
| 5 | entity           | STRING   | Entity type name: with prefix if context-specific (see naming table below). |
| 6 | persona          | STRING   | Role of id_user: OWNER, TENANT_PROSPECT, BUYER_PROSPECT, AGENT_BROKER, AGENT_PHOTOGRAPHER, etc. |
| 7 | business_context | STRING   | 'RENT', 'SALE', or NULL. |
| 8 | properties       | STRING   | JSON: TO_JSON(STRUCT(...)) with labels (what, when, where, status, etc.). |
| 9 | is_active        | BOOLEAN  | TRUE if the entity is still "in progress" for the user; FALSE/NULL otherwise. |
| 10| ts_created       | TIMESTAMP| Creation timestamp. |
| 11| ts_updated       | TIMESTAMP| Last update timestamp. |

Unique key: **(id_entity, id_user, persona)**. The same id_entity can appear in N rows (one per persona).

**id_contract and SALE:** Entities in the SALE context are not linked to an EBDB contract in this model; the view must output `NULL AS id_contract` for SALE entities. Do not join to core_contract or other sources to populate id_contract when business_context is SALE.

**Columns that exist only in entities.sql (not in the view):**

- `sk_entity` — auto-generated template param (`{sk_entity}`) resolved by the DAG at runtime. When adding a UNION block in entities.sql, replicate the `{sk_entity} AS sk_entity` pattern from an existing block. However, `sk_entity` **does need lineage** in entities.yml: it is a surrogate key composed from `entity`, `id_entity`, `id_user`, and `persona`. Add the source columns that feed those (see entities.yml section below).
- `ts_inactive` — derived in the final SELECT of entities.sql: `CASE WHEN is_active = FALSE THEN ts_updated ELSE NULL END AS ts_inactive`. Not a view column; the view provides `is_active` and `ts_updated`, and entities.sql derives `ts_inactive` from them. Its lineage should reference `datalake_entities_views.<entity_name>.ts_updated`.

---

## Entity name (column `entity`) and business_context

| Business context | Column `entity` value | Example |
|------------------|------------------------|---------|
| SALE only        | `FS_<NAME>`            | FS_CCV, FS_OFFER |
| RENT only        | `FR_<NAME>`            | FR_OFFER, FR_ONBOARDING, FR_RESERVATION |
| Both RENT/SALE   | `<NAME>` (no prefix)   | VISIT, LISTING |
| Unknown / NULL   | `<NAME>` (no prefix)   | HOUSE_DRAFT, PHOTO_SESSION |

**Entity name normalization:** The user provides only the **base name** in snake_case (e.g. `diligence`, `photo_session`). If they accidentally include a prefix (`FS_diligence`, `FR_offer`), strip it — the prefix is derived from business context. This avoids double-prefix errors like `FS_FS_DILIGENCE` or cross-prefix errors like `FS_FR_DILIGENCE`.

---

## Personas (canonical list and rules)

- **Persona** = the role the user assumes on the platform in that context. It is **not** an attribute or segment (e.g. "PP Multi" is an attribute of the OWNER persona).
- **Translate** user input to canonical UPPERCASE, applying lifecycle rules to pick the correct variant. E.g. "proprietário" → OWNER; "inquilino" → TENANT_PROSPECT (pre-contract) or TENANT (post-contract) based on entity lifecycle; "comprador" → BUYER_PROSPECT (pre-CCV) or BUYER (post-CCV) based on entity lifecycle; "corretor de visitas" → AGENT_BROKER.
- **Do not duplicate**: synonyms or subsets map to the canonical value (e.g. "proprietário multi" → OWNER).

**Canonical list:**

| Persona             | Description | Lifecycle boundary |
|---------------------|-------------|--------------------|
| OWNER               | Property owner (PP = proprietário) | Throughout the funnel — owner role does not change with lifecycle stage. |
| TENANT_PROSPECT     | User in the **renting** process **before** contract signing. | RENT entities before contract: visit, offer, credit analysis. |
| TENANT              | User who has already **signed a rental contract**. | RENT entities from contract signing onwards: active contract, termination. |
| BUYER_PROSPECT      | User in the **buying** process **before** CCV completion. | SALE entities before CCV conclusion: offer, diligence, CCV in progress. |
| BUYER               | User who has already **completed CCV** (deal closed). | SALE entities from CCV conclusion onwards. |
| PARTNER_CIQ         | CIQ partner. | — |
| AGENT_BROKER        | Broker (e.g. visitas). | — |
| AGENT_INSPECTOR     | Inspector. | — |
| AGENT_PHOTOGRAPHER  | Photographer. | — |

Other personas may exist in the codebase; check `entities.sql` and existing views for consistency.

**Lifecycle validation rule — PROSPECT vs non-PROSPECT:**

The distinction between `_PROSPECT` and non-`_PROSPECT` depends on **where the entity sits in the product funnel**, not on the word the user uses:

| Business context | Milestone | Before milestone | After milestone |
|------------------|-----------|------------------|-----------------|
| RENT | Contract signing | TENANT_PROSPECT | TENANT |
| SALE | CCV completion | BUYER_PROSPECT | BUYER |

**Examples:**

- **RENT funnel (before contract):** visit, offer, credit analysis → use **TENANT_PROSPECT**.
- **RENT funnel (after contract):** contract, termination → use **TENANT**.
- **SALE funnel (before CCV):** offer, diligence, CCV in progress → use **BUYER_PROSPECT**.
- **SALE funnel (after CCV):** CCV concluded → use **BUYER**.

The agent **must** determine the entity's position in the funnel and select the correct variant. If the user says "buyer" for a pre-CCV entity (e.g. diligence), automatically correct to BUYER_PROSPECT and explain why. Same for "tenant"/"inquilino" on pre-contract entities.

For each persona, map the corresponding id in the source (id_owner → OWNER, id_buyer → BUYER_PROSPECT, etc.) and output one row per (id_entity, id_user, persona) via UNION ALL. If the source does not expose that id directly, derive it from related entities (contract, house) via joins, and document with a `-- TODO` comment in the query.

---

## Query generation: avoid assuming unknowns

- **is_active:** Often based on a `status` column; if the source has no clear status or the mapping is unclear, add a `-- TODO` comment and a placeholder (e.g. `NULL AS is_active` or a `CASE` with a comment).
- **id_user / persona:** If the source has no explicit column per persona, add a `-- TODO` comment and suggest deriving from contract/house.
- **Source without 30-min cadence:** When cadence detection (see 1.4) determines the source DAG does not run every 30 minutes, add a comment at the top of the query: `-- Source: <dag_name> runs at <schedule>; entity is not updated every 30 mins. Revisit if 30-min cadence is needed.`

---

## Properties (JSON)

- Used as labels for agents (what, when, where).
- Align with product team + Conv XP; CDP mapping spreadsheet: [link](https://drive.google.com/a/quintoandar.com.br/open?id=1VYonx8lRprEFwz0DheIIW12tLw83K-CVQX7XxbEwh9M).
- Build with `TO_JSON(STRUCT(key1 AS key1, key2 AS key2, ...))`. Common keys: `status`, `when` (timestamp).

---

## Source table prioritization (layer-based)

Entity views should read from **core** or **clean** sources (never enrich). Prioritize by the `layer` field in the source DAG's declaration YAML — not by the table schema name or a regex on the table path.

| `layer` value in declaration | What it means | Schema pattern | Priority |
|------------------------------|---------------|----------------|----------|
| `core` | Core model DAG — canonical, deduplicated entity model | `core_<dag_schema>.<table>` | **1st** (preferred) |
| `raw` | Raw/clean ingestion DAG — mirrors source DB | `datalake_<source>_clean.<table>` | **2nd** (fallback) |

**How to determine the layer:**

1. Identify the DAG that loads the desired source table (search `dags/` for the table name in `*_declaration.yml` files or under `tables_customization`).
2. Read the `workflow.layer` field in that declaration YAML.
3. If `layer: core` → the table lives in a `core_*` schema. Preferred because core models are canonical and deduplicated.
4. If `layer: raw` → the DAG produces both raw and clean tables. The view should use the clean table (`datalake_<source>_clean.<table>`).

**When searching for candidates (user doesn't know the source):**
1. First look for `layer: core` DAGs under `dags/core/` that model the entity (e.g. `core_contract`, `core_house`, `core_visit`).
2. If no core DAG exists, look for `layer: raw` DAGs that produce clean tables for the relevant source database.
3. Present candidates with their `layer` and `schedule_interval` so the user can make an informed choice.

---

## Cadence detection (automatic)

Entity views run every 30 minutes. Source tables ideally should be updated at the same cadence. Instead of asking the user whether a `fast_lane` exists, **detect cadence automatically** from the source DAG's declaration YAML.

**Algorithm:**

1. **`layer: raw` DAGs:** read `schedule_interval` from the declaration. A 30-min cadence means the cron expression produces at least two runs per hour (e.g. `0,30 * * * *`). DAGs with `fast_lane` in their name are the convention, but the check is the schedule — not the name.
2. **`layer: core` DAGs:**
   - (a) If the DAG has a `schedule_interval`: check for 30-min pattern (same as raw).
   - (b) If no `schedule_interval` (typical for core): core DAGs use Dataset-based scheduling. Look up `dags/dependencies.yaml` for `bietlejuice.<dag_name>:` → extract upstream DAG names (format: `bietlejuice.<upstream_dag>:<task_id>`) → read each upstream DAG's declaration → check `schedule_interval`. If **all** upstream DAGs run at 30-min cadence, the core DAG inherits that cadence.

**Outcomes:**

| Result | Action |
|--------|--------|
| 30-min cadence confirmed | Inform user; no cadence comment in SQL |
| Not 30-min | Warn user with specific schedule details; get explicit acknowledgment; add cadence comment in SQL (see "Query generation" section) |
| User asks to create a fast_lane/core pipeline | Explain **separate PR first** strategy — upstream pipeline must be merged and validated on Forno before the entity-view PR |

**Common 30-min patterns (cron):**
- `0,30 * * * *` — every 30 min, 24h (standard)
- `0,30 7-22 * * *` — every 30 min, business hours only
- `30 7-22 * * *` — once per hour (does **not** qualify as 30-min)

---

## Source tables → dependency entries (manual_modifications.yaml)

**Context:** enrich_entities_views produces **materialized views**. Views are read on demand when the entities query runs; they are not pipeline tasks. Therefore enrich_entities_views tasks must never be added as dependencies of enrich_transactional_entities — they must always be in the **remove** list.

**Two places to update:**

### 1. enrich_entities_views (upstream of the new view)

List **every** table the new view reads (all FROM + JOIN). For each: check if already in `bietlejuice.enrich_entities_views:` → `remove:`; if not, add the entry. Do not duplicate.

**Core tables:**

- Schema pattern: `core_<dag_schema>.<table>` (e.g. `core_contract.contract`).
- DAG name: `core_<name>` (e.g. `core_contract`).
- Task id: `load-core-<table>` (**kebab-case**, e.g. `load-core-contract`).
- Entry: `bietlejuice.core_<name>:load-core-<table>:first-run-of-day`.

Example: `core_contract.contract` → `bietlejuice.core_contract:load-core-contract:first-run-of-day`

**Clean tables:**

- Schema pattern: `datalake_<source>_clean.<table>` (e.g. `datalake_ebdb_clean.photographer_job`).
- DAG: usually a **fast_lane** or main source DAG (e.g. `ebdb_photo_job_fast_lane`, `bob`).
- Task id: `load-clean-<table>` (**kebab-case**, e.g. `load-clean-photographer-job`, `load-clean-house-draft`).
- Entry: `bietlejuice.<dag>:load-clean-<table>:first-run-of-day`.

Examples:

- `datalake_ebdb_clean.photographer_job` → `bietlejuice.ebdb_photo_job_fast_lane:load-clean-photographer-job:first-run-of-day`
- `datalake_bob_clean.house_draft` → `bietlejuice.bob:load-clean-house-draft:first-run-of-day`
- `datalake_ebdb_clean.listing_business_context` → `bietlejuice.ebdb_listing_fast_lane:load-clean-listing-business-context:first-run-of-day`

To find the DAG that loads a clean table, search the repo for the table name in declaration YAMLs or in `dags/`.

### 2. enrich_transactional_entities (new view must not be a dependency)

Under `bietlejuice.enrich_transactional_entities:` → `remove:`, add: `bietlejuice.enrich_entities_views:load-enrich-<entity_name>:first-run-of-day` (e.g. `load-enrich-photo-session`, `load-enrich-house-draft`). Views must never be dependencies of this DAG.

---

## entities.sql integration

- **CTE:** `<entity_name> AS ( SELECT id_entity, id_house, id_contract, id_user, entity, persona, business_context, properties, is_active, ts_created, ts_updated FROM datalake_entities_views.<entity_name> [WHERE id_user IS NOT NULL] )`.
- **Union in `base`:** replicate the existing pattern:
  ```
  UNION ALL
  SELECT
      {sk_entity} AS sk_entity,
      id_entity, id_house, id_contract, id_user,
      entity, persona, business_context, properties,
      is_active, ts_created, ts_updated
  FROM <entity_name>
  ```
  `{sk_entity}` is a template param resolved by the DAG at runtime — just copy it from any existing UNION block.

---

## entities.yml (entities table metadata)

When adding a new entity to `entities.sql`, update `dags/growth/enrich_transactional_entities/metadata/enrich/entities.yml`:

- **Lineage:** add `datalake_entities_views.<entity_name>.<column>` to the lineage of columns that derive from a source column: typically `id_entity`, `id_house`, `id_contract`, `id_user`, `properties`, `ts_created`, `ts_updated`. Follow `governance_metadata.mdc` for the general rule on when lineage is required vs not required (e.g. hardcoded literal columns do not need lineage).
  - **`ts_inactive`:** derived in entities.sql as `CASE WHEN is_active = FALSE THEN ts_updated ELSE NULL END`. Its lineage should reference `datalake_entities_views.<entity_name>.ts_updated`.
  - **`sk_entity`:** a surrogate key composed from columns that identify the row. Add the source columns that feed into it: `entity`, `id_entity`, `id_user` (one per persona), and `persona` — e.g. `datalake_entities_views.<entity_name>.id_entity`, `.id_user`, `.entity`, `.persona`, plus the underlying source columns (e.g. `core_<source>.<table>.id_<persona>`).
- **entity.categories:** add new entry (e.g. `FS_CCV: Short description.`).
- **is_active:** add one line to description if the entity has specific active/inactive rules.
- **YAML safety:** do not use unquoted colon+space in description text. Rephrase or quote.
- Follow format of existing entries (house_draft, photo_session).

---

## Datazord enable (backend-services)

**Why:** Entities feed AI initiatives. Datazord exposes them via consumable endpoints (MCP tools, agents). Enabling the business type is what makes the entity visible in APIs.

**Data flow:** data lake → CDF → business-objects topic. No stream processor needed. Reference example: **fr_contract** (batch-only, lake origin).

**Naming:**

| Business context | Enum name | Value string | Example |
|------------------|-----------|-------------|---------|
| SALE only        | `FS_<NAME>` | `fs_<name>` | `FS_CCV("fs_ccv")` |
| RENT only        | `FR_<NAME>` | `fr_<name>` | `FR_OFFER("fr_offer")` |
| Both / unknown   | `<NAME>`    | `<name>`    | `VISIT("visit")`, `PHOTO_SESSION("photo_session")` |

**Files to update (backend-services):**

| File | Purpose |
|------|---------|
| `applications/datazord/app/core/src/main/kotlin/br/com/quintoandar/datazord/core/usercontext/domain/BusinessType.kt` | Add enum entry. Keep alphabetical within groups (FR_*, FS_*, no-prefix). |
| `applications/datazord/app/containers/api/src/main/resources/openapi.yaml` | Append to `BusinessFilter.businessTypes` enum (UPPER_SNAKE_CASE). |
| `applications/datazord/app/core/src/main/resources/business-object-label-rules.yaml` | Add label rules when view has status in properties (see below). |
| `applications/datazord/app/containers/api/src/test/kotlin/br/com/quintoandar/datazord/api/mappers/UserContextMapperTest.kt` | Add to `allBusinessTypes` + `expectedStrings`. |

**Label rules:** When the entity has a status (or similar) field in `properties`:
1. If the user provides status values and labels → add full `statusField` + `mappings`.
2. If the user does not know → search bi-etl-ejuice for DW/enrich metadata with `categories` for the same source column; infer mappings and tell user they were inferred.
3. If discovery fails → add placeholder and tell user explicitly what to fill.
4. **Never** skip label rules silently when the view has status.

When the entity has **no status** in properties → do not add label rules; state that in the output.

**Testing commands:**
- `./gradlew :app:containers:api:test --tests '*UserContextMapperTest*'`
- If label rules added: `./gradlew :app:containers:api:test --tests '*BusinessObjectLabelService*'`
- Optional local API: `./gradlew :app:containers:api:bootRun --args='--spring.profiles.active=forno'`
