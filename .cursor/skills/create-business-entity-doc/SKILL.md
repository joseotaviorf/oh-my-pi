---
name: create-business-entity-doc
description: Create a new business entity documentation file in docs/llm_context/business_entities/. Entity docs are routing guides for the Data Analyst (TARS) subagent, enabling accurate SQL generation and data discovery. Use when the user asks to document a new entity, add a new business entity, or create context for TARS about a data domain.
---

# Create a Business Entity Doc

Entity docs are **routing guides** — they explain concepts, point to tables, give key filters, and avoid duplicating column-level documentation that already exists in governance metadata YAML files. They are consumed by the Data Analyst (TARS) subagent when answering data exploration questions.

---

## Step 1 — Gather context from the user

**Always ask the user** for the following (use the AskQuestion tool). Only skip items the user already provided explicitly in their request:

1. **Entity name** — the business concept (e.g., `contract`, `visit`, `listing`). File will be `docs/llm_context/business_entities/{entity_name}.md`.
2. **One-line summary** — what the entity represents in the business.
3. **Primary DW tables** — which `dw_*` tables are the main source for analysts. If unknown, proceed to Step 2 to discover them.
4. **Common questions** — what analysts typically ask about this entity. These drive the Golden Queries and Dos/Don'ts sections.
5. **DataHub domain URN** — the `urn:li:domain:{domain}` for this entity (e.g., `urn:li:domain:growth`, `urn:li:domain:fintech`, `urn:li:domain:supply`). This is required for the companion YAML in Step 6. Common values: `urn:li:domain:fintech`, `urn:li:domain:growth`, `urn:li:domain:people`, `urn:li:domain:supply`, `urn:li:domain:rent`, `urn:li:domain:sale`.

Do NOT infer these from context — misalignment here propagates through the entire document.

---

## Step 2 — Research the codebase

Before writing, explore the actual data model. Launch parallel explore subagents to:

1. **Find DW SQL files** — search `dags/*/dw_*/queries/dw/` for tables related to the entity. Read the SQL to understand columns, JOINs, and CTEs.
2. **Find enrich SQL files** — search `dags/*/enrich_*/queries/enrich/` for upstream enrichment tables.
3. **Read governance metadata** — check `metadata/dw/*.yml` for the tables found above. Column descriptions and lineage already live there — do NOT duplicate them.
4. **Identify relationships** — look for FK columns (`sk_*`, `id_*`) that link to other entities. Note cardinalities (1:1, 1:N, N:1).
5. **Check for OBT (One Big Table)** — some domains have a pre-joined wide table (like `obt_offboarding`). If one exists, it should be prominently featured.
6. **Look for gotchas** — type mismatches requiring CAST, dedup needs (ROW_NUMBER), mandatory filters (status exclusions), or grain changes on JOINs.
7. **Validate columns via database MCP** (if available) — use `describe_table` to confirm column names and types for the main DW tables. This catches renames or additions not yet reflected in SQL files.

---

## Step 3 — Write the entity file

Create `docs/llm_context/business_entities/{entity_name}.md` following this structure exactly. Every section is required. Keep the file concise and objective, not exhaustive.

### Template

```markdown
# {Entity Name}

## Overview

{2-4 sentences: what the entity is, why it matters, who cares about it.}

{Numbered lifecycle stages if applicable. Each stage should reference the key timestamp or flag column, e.g.:}
1. **Stage name** — description (`table.column`)

{One sentence about exceptions: "Not all X follow every step. Some are..."}

## Glossary and Synonyms

- **{PT-BR term}** ({other aliases}) → {technical mapping or filter}
{Repeat for each domain-specific term. Include:}
{- Entity synonyms (PT-BR names → technical entity)}
{- Domain jargon that analysts use but column names don't reflect}
{- Key filter values that map to business concepts}

{Do NOT include company-wide terms like IQ/PP — those live in intro.md.}

## Tables

| You need... | Use this table |
|-------------|----------------|
| {Analytical need} | `{schema.table}` (`{alias}`) — {one-line description with key filters or patterns} |

**Critical rules:**
- {Mandatory filters, type caveats, dedup requirements — only include if they exist}
- **DataHub CI:** list concrete `schema.table` names only — never wildcards (`statement_*`, `schema.*`, `table_*`) in the Tables section; DataHub cannot link pattern URNs.

## Key Metrics

- {Metric name} (`column` or formula)
{List 5-10 most common KPIs. Reference the table and column.}

## Relationships with Other Entities

### {Related Entity} ({cardinality})

- {JOIN pattern with actual column names}
- {Any caveats (CAST, dedup, filter)}

## Dos and Don'ts

**Do:**
- {Actionable guidance with specific table/column/filter references}

**Don't:**
- {Common mistake with explanation of what goes wrong}

## Golden Queries

### Query 1 — {Pattern name}

{One sentence describing what this query answers.}

```sql
{Validated SQL pattern — use SELECT * for brevity in base patterns}
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
```

### Section-by-section guidance

**Overview:**
- State what the entity is, not how tables are structured.
- Reference lifecycle stages with their key timestamp columns.
- Mention exceptions (cancellations, opt-outs, fast-track paths).

**Glossary and Synonyms:**
- Always use bullet list format (`- **term** → mapping`), not tables. Bullets are more expressive and allow inline filters and multi-mapping.
- Merge entity synonyms (PT-BR names) with domain jargon into one list.
- For jargon entries: include the definition AND the technical mapping (table, column, or filter).
- Only include terms specific to this domain. Company-wide terms (IQ, PP) belong in `intro.md`.

**Tables:**
- Use the "You need... / Use this table" format. Each row answers an analytical question.
- Prefer DW tables. Include enrich/clean only when DW doesn't have the data.
- For OBT tables: emphasize that they're pre-joined and list what's included.
- For relisting/rerental-type patterns: include the key filter inline (e.g., `sk_next_contract <> -1`).
- Do NOT list every column — metadata YAML already covers that.

**Key Metrics:**
- Use bullet list format (`- Metric name (column or formula)`), not tables.
- List 5-10 KPIs that analysts commonly ask about.
- Reference the table and column for each.
- These should map to common questions from Step 1.

**Relationships:**
- One subsection per related entity with cardinality in the heading.
- Include the exact JOIN pattern with real column names.
- Note CAST requirements, dedup rules, or mandatory filters.

**Dos and Don'ts:**
- Every "Do" and "Don't" should reference a specific table, column, or filter.
- Capture gotchas discovered in Step 2 (type mismatches, grain changes, ambiguous dates).
- This section is checked before every SQL generation — make it count.

**Golden Queries:**
- 2-4 validated query patterns that cover the most common analytical needs.
- All queries must use **Trino SQL dialect** (the consumer is TARS, which generates Trino queries for Superset/DBeaver). No Spark-only constructs like `QUALIFY` or `GROUP BY ALL`.
- Validate that all table and column names exist in governance metadata or DW SQL files discovered in Step 2.
- Start with a base pattern (entity + descriptive attributes).
- Add cross-entity patterns (JOINs with related entities).
- If an OBT exists, include a query using it.
- `SELECT *` is acceptable for brevity; note that production queries should select specific columns.
- For every table used, locate its corresponding .yml metadata file in the metadata folder within the DAG directory, and use it as the source of truth to validate the available columns.

---

## Step 4 — Register the entity in intro.md

Add the new entity to the "Available entities" list in `docs/llm_context/intro.md`:

```markdown
- `business_entities/{entity_name}.md` — {Short description} ({PT-BR synonym})
```

---

## Step 4b — Update related entity docs

Check if any existing entity docs in `docs/llm_context/business_entities/` reference tables or concepts that overlap with the new entity. If so, add or update a "Relationships" sub-section in those docs pointing to the new entity.

---

## Step 5 — Self-review checklist

Before presenting to the user, verify:

- [ ] No column descriptions duplicated from metadata YAML
- [ ] Glossary only contains domain-specific terms (no IQ/PP)
- [ ] Every table in the Tables section has a clear "You need..." trigger
- [ ] Tables section uses concrete `schema.table` names only (no `*` wildcards or `schema.*` globs)
- [ ] Every relationship has an exact JOIN pattern with real column names
- [ ] Every Do/Don't references a specific table, column, or filter
- [ ] Golden Queries are syntactically valid and cover common needs
- [ ] Golden Queries use Trino SQL dialect (no Spark-only constructs like `QUALIFY`, `GROUP BY ALL`)
- [ ] Entity is registered in `intro.md`
- [ ] Related entity docs updated with cross-references (if applicable)
- [ ] Critical rules section present when CAST, Dedup, or mandatory filters apply
- [ ] No information that doesn't fill a gap — if something is redundant, remove it

---

## Step 6 — DataHub publication (automatic)

CI generates ephemeral YAML from this Markdown and pushes to DataHub on merge
(`.woodpecker/datahub.yml` → `generate-and-push-datahub`). No companion YAML is committed.

The `md-to-datahub-yaml` skill defines the generated schema. Key mappings:
- `data_product_id`: kebab-case from filename (`broker_xp.md` → `broker-xp`)
- `golden_query.stable_urn`: deterministic `uuid5(entity_slug)` assigned by CI
- `product_description`, `glossary_terms`, `datasets`: derived from Overview, Glossary, and Tables sections

---

## Step 7 — Manual push (optional, local testing)

Prerequisites: `OPENAI_API_KEY`, `DATAHUB_GRAPHQL_URL`, `DATAHUB_TOKEN`.

```bash
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \\
  docs/llm_context/business_entities/{entity_slug}.md

python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose
```
