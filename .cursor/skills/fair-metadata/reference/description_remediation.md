# Description remediation (F2-01 table + F2-02 columns) — Gate B

**Purpose:** Descriptions explain **business meaning**. Passing F2 heuristics is a side effect — not the goal. **This file is the one an agent must actually read and apply — not skim — before writing or leaving any description untouched.**

## The heuristic is a floor, not a target (read this before running anything)

`make audit-fair-metadata-scope` / `validate-fair-metadata` only implement **F2 as a mechanical check**: minimum length, ≥2 words outside the table/column/database name, no pure name-echo. That check cannot tell business content from filler — a sentence can be 40 characters, use unrelated words, and still say nothing about the table. **A script PASS is not evidence the description is done.**

Two failure modes this causes, both **forbidden**:

1. **Writing new filler that clears the bar.** Generating a templated sentence (e.g. `"Business attribute from $table $layer."` with only the identifiers swapped in) satisfies length + word-count but carries zero business meaning. This is functionally the same anti-pattern as copy-pasted lake filler — it just originates from the agent instead of from a prior bad edit. If the same sentence shape appears for a second column with only the name changed, **stop and rewrite** before continuing to the next column.
2. **Skipping descriptions that already pass.** The scope audit only *lists failures*. An existing description that already clears F2-01/F2-02 will never appear in that failure list — so an agent that treats "not in the failure list" as "don't touch it" will leave low-quality, pre-existing descriptions unimproved forever. **Do not do this.** Gate B is not satisfied by "0 script failures" alone — see the mandatory review step below.

## Mandatory: review every description in scope, not only F2 failures

For **every table and column description in the closed scope inventory** (Step 0, [`scoping.md`](scoping.md)) — including ones the audit script does **not** flag — apply the **swap test**:

> Could you take this exact sentence, swap in a different table/column name from a different domain, and have it still read as true and natural? If yes, it fails — the sentence doesn't depend on knowing *this* business object, so it isn't describing it.

- Script-flagged failures (F2-01/F2-02) → rewrite, always.
- Script-passing but swap-test-failing descriptions → rewrite too, and call this out explicitly in the plan (see "Proposed changes" reason column in [`remediation_plan.md`](remediation_plan.md)) as *quality improvement*, distinct from *gate failure*, so the user can see both kinds of edits.
- Only genuinely substantive existing descriptions may be left as-is.

## Gate B scope

Gate B evaluates **every clean / core / enrich / dw / metric file in the closed inventory** from Step 0 ([`scoping.md`](scoping.md)) — same inventory table as [`SKILL.md`](../SKILL.md) and [`scoping.md`](scoping.md); do not re-derive it here. PR-diff-only scope is the exception, not the default — see "Scope vs PR diff" below.

```bash
# Domain-wide PLAN / post-EXECUTE audit
make audit-fair-metadata-scope domain=governance
# Gate B section: F2-01/F2-02 failures per file in that folder

# Single table — all layers present in repo, not the whole domain
make audit-fair-metadata-scope fqn=datalake_metabase_clean.metabase_table
```

Re-run after EXECUTE on the **same user scope** (same flags / FQN / owner filter) until the script shows 0 F2-01/F2-02 failures. **A green script run confirms the mechanical floor only** — Gate B itself is not closed until every edited (and every reviewed-but-left-as-is) description in the batch has also passed the swap test above; do not report Gate B done from the script output alone.

## Forbidden (never use to “pass the test”)

- `Business attribute from $table $layer.` / `Business attribute from {table} {layer}` / any templated sentence where only the table/layer/column name changes between files — this is the single most common failure mode: it reads as content but is a mail-merge, not a description.
- `Persisted in the governance lake for lineage, documentation metrics, and FAIR assessments.`
- `Business context: attribute of the X entity used for governance analytics…`
- `Surrogate or natural identifier for the id within the X dataset.`
- `Information about …` as the whole table description
- `Column from the X table.` / `Field in the X dataset.` / `Attribute of the X layer.`
- Bulk `sed` / scripts that only lengthen text
- Column name as the whole description (`Dashboard title`, `Status column`)

All of the above pass the F2 length/word-count heuristic. That is exactly why they are dangerous — nothing downstream of the audit script will catch them. The swap test above is the only thing that catches them.

If the only way to pass F2-01/F2-02 is filler → **stop**, research, or **ask the user**.

### Worked example — passes F2, still forbidden

```yaml
# Bad — 51 chars, 2+ substantive words, clears F2-01/F2-02, fails the swap test
description: "Business attribute from sync_runs_trino clean layer."
```

```yaml
# Good — ties to this table's actual business role
description: >
  Timestamp (UTC) marking when a Hightouch sync run finished writing rows to
  the destination warehouse. Consumed by the data-ops on-call dashboard to
  detect stalled syncs and to compute the sync SLA breach alert.
```

The bad version would read identically if you swapped in any other table name. The good version would be false for any other table — that is the signal it's real.

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
| 1 | `docs/llm_context/business_entities/*.md` | Entity glossary |
| 2 | `queries/{layer}/{table}.sql` | Grain, joins, selected fields |
| 3 | `spark_jobs/*.py` | Raw ingest shape |
| 4 | `*_declaration.yml` | Workflow intent |
| 5 | Another layer (substantive only) | Do not copy weak text |
| 6 | Trino samples (`trino/SKILL.md`) | Enums, null rate |

For **Data Ops & Governance** (Superset, Jira, Metabase, …): SQL + product semantics; ask user when unclear.

## What to write

**Table `description`:** must answer, in prose (not a checklist dump): what business event or entity this table represents, the source system it comes from, the grain (one row = ?), and who/what consumes it downstream (a dashboard, a model, another domain's pipeline). A description that could be true of any table in the domain is not done.

**Column `description`:** what the value represents **in business terms** (not "the X field"), unit/format/timezone when relevant, whether it's a business/foreign key and to what entity, and — when computed — the derivation logic in plain language (not just "derived column"). Prefer naming the *decision or process* the column feeds (e.g. "used to flag churn risk") over restating the column name.

Run the swap test on your own draft before moving to the next file: if you can't point to a word in the sentence that would be wrong for a sibling table/column, rewrite it.

## YAML shape (required for CI)

`validate-fair-metadata` parses each changed metadata file **before** F2-01/F2-02. Invalid YAML fails with scanner errors (`could not find expected ':'`, `expected <block end>`).

When editing table or column `description` (Gate B or Gate C append):

1. Keep all prose **inside** the `description` scalar — use `description: |` (see `dags/growth/hightouch_logs/metadata/clean/sync_runs_trino.yml`) or an indented block under `description:`.
2. **Never** add continuation lines at column 1 (e.g. partition text after the first `description:` line).
3. Quote values that start with `[` or contain unescaped `'` / `:` mid-string, or use `|`.

After EXECUTE edits, run `make validate-metadata-files-content` then `make validate-fair-metadata` on the branch.

## Workflow per table (max ~10 tables per PR in EXECUTE)

1. Scope audit lists failing table (`F2-01`) and column (`F2-02`) entries with `reason_code` — this is the mandatory floor, **not the full worklist**.
2. Read every **existing** table + column description already in the file, even the ones not listed as failing, and run the swap test on each. Add any that fail it to your worklist as *quality improvements*.
3. Draft from research — table description first, then one column at a time. After each draft, run the swap test before writing the next one; if two consecutive drafts share the same sentence shape with only the name changed, stop and rewrite both.
4. Re-run scope audit Gate B on user scope (confirms the mechanical floor — it will not confirm business substance; that's step 2/3).
5. CI: `make validate-metadata-files-content` then `make validate-fair-metadata` on branch (PR diff).

## Scope vs PR diff

| Command | When to use | Scope |
|---------|-------------|-------|
| `make audit-fair-metadata-scope …` | PLAN, domain/owner/table/DAG audit, after EXECUTE | **Closed inventory** from scope flags (`--domain`, `--fqn`, `--owner`, `--dag`, `-f`) |
| `make validate-fair-metadata` | User asked to validate **this PR / branch**; Woodpecker CI | **PR diff only** vs `origin/master` |

Do not run `--audit --domain governance` when the user only asked to check their PR. Do not treat a green PR CI as “the whole domain is FAIR” when the user asked for a domain audit and scope audit was never run on that inventory.
