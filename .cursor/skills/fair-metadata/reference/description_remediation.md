# Description remediation (F2-01 table + F2-02 columns) — Gate B

**Purpose:** Descriptions explain **business meaning**. Passing F2 heuristics is a side effect — not the goal.

## Gate B scope

Gate B evaluates **every clean / core / enrich / dw / metric file in the closed inventory** from Step 0 ([`scoping.md`](scoping.md)). **How large that inventory is depends on what the user asked for** — not every audit is domain-wide.

| User request | Inventory | Gate B runs on |
|--------------|-----------|----------------|
| Single table / FQN | All repo layers for `database_name.table_name` | clean+ files **for that table only** |
| Single DAG | `dags/{folder}/{dag}/metadata/**/*.yml` | clean+ files **in that DAG** |
| Owner (± repo folder) | Metadata YAML matching `owner:` | clean+ files **for that owner filter** |
| Repo folder / YAML `domain:` | Full domain inventory | clean+ files **in that domain scope** |
| **PR / branch validation** | Files changed vs `origin/master` | **`make validate-fair-metadata` only** — not `--audit --domain …` |

**Within the inventory**, Gate B does **not** shrink to “only files touched in the current PR” when the user asked for a domain, table, owner, or DAG audit. When the user asked to **validate the PR**, use the last row — PR diff **is** the scope.

```bash
# Domain-wide PLAN / post-EXECUTE audit
make audit-fair-metadata-scope domain=governance
# Gate B section: F2-01/F2-02 failures per file in that folder

# Single table — all layers present in repo, not the whole domain
make audit-fair-metadata-scope fqn=datalake_metabase_clean.metabase_table
```

Re-run after EXECUTE on the **same user scope** (same flags / FQN / owner filter) until Gate B shows 0 failures.

## Forbidden (never use to “pass the test”)

- `Persisted in the governance lake for lineage, documentation metrics, and FAIR assessments.`
- `Business context: attribute of the X entity used for governance analytics…`
- `Surrogate or natural identifier for the id within the X dataset.`
- `Information about …` as the whole table description
- Bulk `sed` / scripts that only lengthen text
- Column name as the whole description (`Dashboard title`, `Status column`)

If the only way to pass F2-01/F2-02 is filler → **stop**, research, or **ask the user**.

## F2 heuristics (TDQ — same as production)

| Rule | Threshold |
|------|-----------|
| Min length | 24 characters (after normalization) |
| Substantive words | ≥ 2 words not in table/column/database name vocabulary |
| Name echo | Avoid descriptions that only repeat identifier tokens |
| Partitions | `year`, `month`, `day` excluded from F2-02 column checks |

## Research before writing (in order)

| Priority | Source | What to extract |
|----------|--------|-----------------|
| 1 | `docs/llm_context/business_entities/*.md` | Entity glossary (`@tars`) |
| 2 | `queries/{layer}/{table}.sql` | Grain, joins, selected fields |
| 3 | `spark_jobs/*.py` | Raw ingest shape |
| 4 | `*_declaration.yml` | Workflow intent |
| 5 | Another layer (substantive only) | Do not copy weak text |
| 6 | Trino samples (`@tars`) | Enums, null rate |

For **Data Ops & Governance** (Superset, Jira, Metabase, …): SQL + product semantics; ask user when unclear.

## What to write

**Table `description`:** grain, source system, consumers.

**Column `description`:** what the value represents, units/timezone, FK relationships, derivation when computed.

## Workflow per table (max ~10 tables per PR in EXECUTE)

1. Scope audit lists failing table (`F2-01`) and column (`F2-02`) entries with `reason_code`.
2. Draft from research — table description first, then one column at a time.
3. Re-run scope audit Gate B on user scope.
4. CI: `make validate-fair-metadata` on branch (PR diff).

## Scope vs PR diff

| Command | When to use | Scope |
|---------|-------------|-------|
| `make audit-fair-metadata-scope …` | PLAN, domain/owner/table/DAG audit, after EXECUTE | **Closed inventory** from scope flags (`--domain`, `--fqn`, `--owner`, `--dag`, `-f`) |
| `make validate-fair-metadata` | User asked to validate **this PR / branch**; Woodpecker CI | **PR diff only** vs `origin/master` |

Do not run `--audit --domain governance` when the user only asked to check their PR. Do not treat a green PR CI as “the whole domain is FAIR” when the user asked for a domain audit and scope audit was never run on that inventory.
