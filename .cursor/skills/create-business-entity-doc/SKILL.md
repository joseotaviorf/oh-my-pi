---
name: create-business-entity-doc
description: Create a new business entity documentation file in docs/llm_context/business_entities/. Entity docs are routing guides for the data analyst agent (TARS plugin in ai-tools), enabling accurate SQL generation and data discovery. Use when the user asks to document a new entity, add a new business entity, or create context for TARS about a data domain.
---

# Create a Business Entity Doc

Entity docs are **routing guides** — they explain concepts, point to tables, give key filters, and avoid duplicating column-level documentation that already exists in governance metadata YAML files. They are consumed by the TARS data analyst plugin (ai-tools) when answering data exploration questions.

---

## Step 1 — Gather context from the user

**Always ask the user** for the following (use the AskQuestion tool). Only skip items the user already provided explicitly in their request:

1. **Entity name** — the business concept (e.g., `contract`, `visit`, `listing`). File will be `docs/llm_context/business_entities/{entity_name}.md`.
2. **One-line summary** — what the entity represents in the business.
3. **Primary DW tables** — which `dw_*` tables are the main source for analysts. If unknown, proceed to Step 2 to discover them.
4. **Common questions** — what analysts typically ask about this entity. These drive the Golden Queries and Dos/Don'ts sections.
5. **DataHub domain URN** — the `urn:li:domain:{domain}` for this entity (e.g., `urn:li:domain:growth`, `urn:li:domain:fintech`, `urn:li:domain:supply`). This is required for the companion YAML in Step 6. Common values: `urn:li:domain:fintech`, `urn:li:domain:growth`, `urn:li:domain:people`, `urn:li:domain:supply`, `urn:li:domain:rent`, `urn:li:domain:sale`.
6. **Ownership emails** — at least one **Data Owner** (accountable for the business definition, usually a manager/lead) and at least one **Data Steward** (`@quintoandar.com.br`, maintains this document day-to-day; defaults to the requester if not otherwise specified). The two roles may share the same email.

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

### Variant — pipeline / operational health entities

Use this path when the entity documents **pipeline observability** (volume, latency, CDC
gaps, connector health) rather than a Kimball business concept. Example:
`salesforce_sst_pipeline.md` (`datalake_sst_metrics`).

1. **Research sources** — read `dags/{domain}/{dag}/metadata/**/*.yml` and the DAG
   declaration; validate table/column names with Trino via the **`fair-metadata`** skill
   (not only DW SQL under `queries/dw/`).
2. **Tables section** — document observability schemas (e.g. `datalake_sst_metrics.*`);
   state grain (`partition_date` + `partition_hour`), mandatory filters
   (`environment = 'prod'`), and column-name inconsistencies across tables (e.g. `env`
   vs `environment`).
3. **Failure signals** — a missing hourly partition is ambiguous: it may mean pipeline
   down **or** a scheduled daily flow. Document disambiguation columns (e.g.
   `event_type = 'RECOVERY'` in `events_type_volume`) in Overview, Glossary, and
   **Critical rules**.
4. **Domain architecture section** — when ingestion has a distinct operational model,
   add a dedicated `## {Source} Pipeline` section (e.g. Appflow flow mapping, status
   values, recovery flow behavior, Appflow-specific Dos and Don'ts).
5. **Golden Queries** — prioritize incident investigation: broken connectors, latency
   spikes, CDC gaps, schema drift. Cross-check columns against metadata YAML before
   committing SQL blocks.
6. **Catalog caveats** — if a table is in DataHub metadata but not yet queryable in
   Trino, note it under **DataHub catalog** open items; remove stale Trino warnings once
   validated.
7. **Draft files** — write the canonical doc only under
   `docs/llm_context/business_entities/{entity_name}.md`. Do not leave working drafts at
   the repo root.

---

## Step 3 — Write the entity file

Create `docs/llm_context/business_entities/{entity_name}.md` following this structure exactly. **Required** sections: `## Ownership`, `## Overview`, `## Glossary and Synonyms`, `## Tables`, `## Key Metrics`, `## Relationships with other entities`, `## Dos and Don'ts`, `## Golden Queries` (the CI gate blocks a PR missing any of them). **Optional:** `## Related Metric Entities` (and `### Official metrics (metric entities)` when official metrics exist); `## DataHub catalog` is filled in automatically. Keep the file concise and objective, not exhaustive.

### Template

```markdown
# {Entity Name}

## Ownership

**Data Owner:**
- {data_owner_email@quintoandar.com.br}

**Data Steward:**
- {data_steward_email@quintoandar.com.br}

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

{Do NOT include company-wide abbreviations (IQ, PP) — document only domain-specific terms.}

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

**Ownership:**
- First section after the title. Two required bold sub-groups, **Data Owner:** and **Data Steward:**, each with at least one `@quintoandar.com.br` email bullet (they may overlap).
- Ask the user for both in Step 1 if not already provided.
- Not folded into the DataHub Data Product description (see `EXCLUDE_HEADING_PATTERNS` in `generate_and_push_datahub_entities.py`) — it is routing metadata, not narrative content.

**Overview:**
- State what the entity is, not how tables are structured.
- Reference lifecycle stages with their key timestamp columns.
- Mention exceptions (cancellations, opt-outs, fast-track paths).

**Glossary and Synonyms:**
- Always use bullet list format (`- **term** → mapping`), not tables. Bullets are more expressive and allow inline filters and multi-mapping.
- Merge entity synonyms (PT-BR names) with domain jargon into one list.
- For jargon entries: include the definition AND the technical mapping (table, column, or filter).
- Only include terms specific to this domain. Omit company-wide abbreviations (IQ, PP).

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
- **Hard cap: never write more than 10 golden queries**, regardless of how many candidate
  patterns Step 2 surfaces. If more than 10 are warranted, keep the 10 most
  valuable/representative patterns and tell the user which ones were deferred (they are
  candidates for a follow-up doc). This is enforced at generation time — it's a different
  gate from the token-based review in Step 3b, which still runs afterward.
- 2-4 validated query patterns that cover the most common analytical needs.
- All queries must use **Trino SQL dialect** (the consumer is TARS, which generates Trino queries for Superset/DBeaver). No Spark-only constructs like `QUALIFY` or `GROUP BY ALL`.
- Validate that all table and column names exist in governance metadata or DW SQL files discovered in Step 2.
- Start with a base pattern (entity + descriptive attributes).
- Add cross-entity patterns (JOINs with related entities).
- If an OBT exists, include a query using it.
- `SELECT *` is acceptable for brevity; note that production queries should select specific columns.
- For every table used, locate its corresponding .yml metadata file in the metadata folder within the DAG directory, and use it as the source of truth to validate the available columns.

---

## Step 3b — DataHub token-overflow risk check (mandatory)

`## Golden Queries` is converted to DataHub YAML by a single LLM call with a fixed
`max_tokens` ceiling (`LITELLM_MAX_TOKENS`, default 16000, in
`packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py`).
An entity with many and/or very large SQL golden queries can exceed that ceiling and
get a truncated response — CI now hard-fails on a declared-vs-generated mismatch
(see the Cases Perspective incident: 9 golden queries declared, only 2 published),
but catch the risk here, before the PR even exists.

Run the same credential-free counting logic CI uses, against the file you just wrote —
measuring the **Golden Queries section** specifically (not the whole file: prose sections
like Overview/Tables don't feed the same LLM call and would make the signal noisy):

```bash
uv run --directory packages/bietlejuice-compiler python -c "
import sys; sys.path.insert(0, 'scripts/ci_cd')
import generate_and_push_datahub_entities as g
from pathlib import Path
md_path = Path('../../docs/llm_context/business_entities/{entity_name}.md')
lines = md_path.read_text().splitlines()
in_section, section_bytes = False, 0
for line in lines:
    if g._GOLDEN_QUERY_SINGULAR_HEADING_RE.match(line) or g._GOLDEN_QUERY_SECTION_HEADING_RE.match(line):
        in_section = True; continue
    if in_section and line.startswith('## '):
        in_section = False; continue
    if in_section:
        section_bytes += len(line) + 1
print('golden_queries=', g._count_expected_golden_queries(md_path))
print('golden_queries_section_bytes=', section_bytes)
"
```

Don't calibrate against hardcoded byte counts of specific existing docs — they get edited
over time and any number pinned here would go stale. Instead: the entity that actually
truncated, Cases Perspective, was 9 golden queries at ~34KB of Markdown section text at
the time of the incident. If you're unsure whether the current doc is in a comparable risk
band, run the same `section_bytes` snippet above against one or two similarly-scoped
existing docs in `docs/llm_context/business_entities/` for a live comparison point.

Note this check is now a secondary defense, not the primary one: `_inject_golden_query_sqls`
in `generate_and_push_datahub_entities.py` extracts golden-query SQL directly from the
Markdown and injects it into the YAML deterministically after LLM generation — the LLM
only emits a placeholder for `sql:`, not the SQL text itself. This removes most of the
original truncation vector (reproducing large SQL blocks). Residual risk comes from what
the LLM still authors: `name`/`description`/`subjects` per golden query, plus the Glossary
and Tables sections — so `golden_queries_section_bytes` is now a rougher proxy than before,
but still worth checking when a doc has an unusually large Glossary or many golden queries.

Flag the entity as **at risk of LLM truncation** during the `push-datahub-business-context`
Woodpecker step when any of these hold:
- `golden_queries_section_bytes` > ~8,000 (roughly 2,000 tokens) — this is the primary,
  token-based signal and applies regardless of query count
- `golden_queries` > 10 — should never happen when authored through this skill (Step 3
  enforces a hard cap of 10); if you see this on review, the doc was likely hand-edited
  after generation
- any single golden query's ` ```sql ` block is unusually large (roughly 40+ lines)

When at risk, say so explicitly in your final response to the user and recommend one of:
- Raising `LITELLM_MAX_TOKENS` for the CI run that will publish this entity, or
- Splitting the Golden Queries section (fewer queries per PR / a follow-up PR for the rest).

This is a **heads-up, not a hard blocker** — CI already fails hard on an actual
declared-vs-generated mismatch, so don't refuse to finish the doc solely on this signal;
just make sure the user knows before opening the PR.

---

## Step 4 — Update related entity docs

Check if any existing entity docs in `docs/llm_context/business_entities/` reference tables or concepts that overlap with the new entity. If so, add or update a "Relationships" sub-section in those docs pointing to the new entity.

---

## Step 5 — Self-review checklist

Before presenting to the user, verify:

- [ ] `## Ownership` is the first section after the title, with at least one `@quintoandar.com.br` email under **Data Owner** and one under **Data Steward**
- [ ] No column descriptions duplicated from metadata YAML
- [ ] Glossary only contains domain-specific terms (no IQ/PP)
- [ ] Every table in the Tables section has a clear "You need..." trigger
- [ ] Tables section uses concrete `schema.table` names only (no `*` wildcards or `schema.*` globs)
- [ ] Every relationship has an exact JOIN pattern with real column names
- [ ] Every Do/Don't references a specific table, column, or filter
- [ ] Golden Queries are syntactically valid and cover common needs
- [ ] Golden Queries use Trino SQL dialect (no Spark-only constructs like `QUALIFY`, `GROUP BY ALL`)
- [ ] DataHub token-overflow risk check run (Step 3b); user warned if at risk
- [ ] Related entity docs updated with cross-references (if applicable)
- [ ] Critical rules section present when CAST, Dedup, or mandatory filters apply
- [ ] No information that doesn't fill a gap — if something is redundant, remove it
- [ ] (Pipeline entities) Ambiguous failure signals documented with disambiguation columns
- [ ] (Pipeline entities) Architecture / connector section present when ingestion model is non-trivial
- [ ] Canonical file lives under `docs/llm_context/business_entities/` (no repo-root drafts)

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

<!-- LUIGI:SELF-SERVICE:BEGIN -->

## Self-Service Submissions via Zordon (Luigi)

> **This block is the single source Zordon/Luigi reads to guide a self-service submission**,
> so it is written for that consumer and is self-contained. The numbered Steps above — asking the
> user, codebase research, Explore subagents, Trino MCP, the DataHub token-overflow byte check, the
> related-entity back-links — are for an **engineer or Cursor agent editing the repo directly** and
> do **not** apply to a chat submission. This block only restates the *content contract* the finished
> file must satisfy. If it ever disagrees with the sections above, **the sections above win** — keep
> it in lockstep with them.

**How the flow actually works.** A non-technical user uploads a finished business-entity `.md` in
Google Chat. Zordon validates it in the conversation and, if it passes, opens a review PR on
`bi-etl-ejuice`; a human data engineer reviews it, and merging to `master` publishes it to DataHub.
Zordon never researches the codebase or writes the doc for the user — it only checks the uploaded
file against the contract below and tells the user, in plain language, what to fix and re-upload.

**Filename — Zordon derives it, the user does not choose it.** It comes from the official entity
name: lowercased, accents stripped, then every run of non-alphanumeric characters collapsed to a
single `_` (e.g. `Broker XP` → `broker_xp.md`), landing under `docs/llm_context/business_entities/`.
A name that collides with an already-published entity is surfaced by Zordon's own
duplicate/existing-entity check (below), not asked about up front.

**Language.** The prose (headings + body) must be predominantly **English**. Portuguese is expected
and must NOT be flagged in: `## Glossary and Synonyms` entries, short parenthetical glosses of a
local term (e.g. "eviction (despejo)"), and any code, SQL, identifiers, emails, or URLs.

**No template leftovers.** Reject any unfilled placeholder (text wrapped in `{...}`), any `TBD`, and any leftover `WRITING GUIDE` comment block.

### Required sections — the automated gates block the PR if any is missing or empty

Both the CI check (in `bi-etl-ejuice`) and Zordon's pre-check block the PR when a required section is **missing or empty**. Machine-checkable specifics include Ownership emails, concrete `` `schema.table` `` routing, **Key Metrics**, **Relationships**, and at least one Trino ``sql`` Golden Query block (no Spark-only constructs). Reject empty optional headings — omit optional sections entirely when they do not apply.

Both a **Do** and a **Don't** under **Dos and don'ts** describe what a **good** section looks like: CI may surface them as **non-blocking warnings**; the reviewer confirms them in PR review. The six labeled Overview bullets are recommended (see Step 3) — CI blocks only a missing or empty **Overview** section, not bullet labels.

| Section | What it must contain |
| :------ | :------------------- |
| `# {Entity Name}` | The H1 title: the entity's full official name, spelled out. |
| `## Ownership` | **Data Owner:** at least one `@quintoandar.com.br`/`@quintoandar.com` email, **and** **Data Steward:** at least one such email. The two roles may be the same person. |
| `## Overview` | Labeled bullets (Objective, lifecycle, actions, common metrics, source systems, related entities) — recommended; CI blocks only a missing or empty section. |
| `## Glossary and Synonyms` | Term / Meaning / Notes table (or equivalent bullets) mapping PT-BR aliases to technical concepts. |
| `## Tables` | At least one **concrete** `` `schema.table` `` reference — never a wildcard (`schema.*`, `table_*`); DataHub cannot link pattern URNs. |
| `## Key Metrics` | Separates official metric-entity links from component/exploratory metrics computable on this entity's tables. |
| `## Relationships with other entities` | Cardinality and join keys (`↔` for bidirectional joins). |
| `## Dos and don'ts` | Entity-specific table/grain/filter traps (both **Do** and **Don't** recommended). |
| `## Golden Queries` | At least one Trino SQL block (a triple-backtick `sql` fence). No Spark-only constructs: `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-argument `DATEDIFF`, or `col:key` variant access. |

> Shared sections (Ownership, Overview, Glossary, Dos and don'ts, Golden Queries) match the metric template; type-specific sections for a business entity are **Tables**, **Key Metrics**, and **Relationships** (a metric doc uses Related Business Entities / Scope / Calculation / Catalog instead).

### Optional sections — include only when they apply

- `## Related Metric Entities` — official metric-entity docs built on this domain's tables; omit when none exist (and omit `### Official metrics (metric entities)` under Key Metrics when none exist).
- `## DataHub catalog` — added automatically by CI after publish; never fill it in by hand.

### What Zordon must NOT ask the user

- **The owner's / steward's email** — when `## Ownership` is present, Zordon reads it straight from
  the uploaded file instead of asking again.
- **Anything that needs repo access** (which tables exist, whether a slug is already taken, whether
  this duplicates an existing entity) — Zordon checks that itself against `bi-etl-ejuice` and only
  speaks up when it actually finds a conflict or a likely duplicate.

<!-- LUIGI:SELF-SERVICE:END -->
