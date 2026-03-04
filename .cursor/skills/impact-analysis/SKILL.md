---
name: impact-analysis
description: Trace the full downstream impact of renaming, removing, or changing a table or column across ~772 DAGs. Launches parallel explore subagents to find all SQL consumers, metadata lineage entries, and declaration dependencies. Use when the user asks about impact of a change, wants to rename a table or column, or needs to understand what would break.
---

# Change Impact Analysis

## When to use

Before renaming or removing a table/column, when a source schema changes (e.g. CDC source adds/drops a column), or when you need to know which DAGs depend on a specific identifier.

## Step 1 — Parse the target identifier

Determine the scope from user input:

| Input format | Scope |
|-------------|-------|
| `database.table` | All references to this table |
| `database.table.column` | References to this specific column |
| `dag_name` | All downstream DAGs depending on this DAG |

Examples: `datalake_ebdb_clean.contract`, `dw_rent.dim_contract.country_code`, `enrich_ebdb_proposal`

## Step 2 — Launch three explore subagents in parallel

Use the Task tool with `subagent_type: explore` for all three simultaneously.

**Subagent A — SQL consumers:**

Search all `.sql` files under `dags/` for any reference to the table or column name. Ask the subagent to return:
- File paths of every matching SQL file
- The line number and surrounding context (2 lines before/after)
- The DAG name (parent folder of the SQL file)

**Subagent B — Metadata lineage entries:**

Search all `.yml` files under `dags/*/metadata/` for `lineage:` entries matching the identifier. Ask the subagent to return:
- File paths of every matching metadata YAML
- The column name whose lineage points to the identifier
- The layer (enrich, dw, metric, etc.)

**Subagent C — Declaration dependencies:**

Search all `*_declaration.yml` files for `inner_dependencies`, `tables_customization`, or `custom_schema` values matching the table/DAG name. Ask the subagent to return:
- File paths of matching declarations
- The specific field and value that references the identifier

## Step 3 — Synthesize the impact report

Structure the output as:

### Direct SQL consumers
DAGs whose SQL queries read from `{identifier}` directly — these need SQL changes if the table/column is renamed or removed.

### Metadata lineage entries to update
Metadata YAML files that list `{identifier}` in a `lineage:` field — these need updating for governance consistency (CI will fail if lineage is stale).

### Declaration dependencies
Declarations that reference the DAG or table via `inner_dependencies` or `tables_customization` — these may need schedule or dependency graph updates.

### Summary
> X SQL files across Y DAGs consume this table/column.  
> Z metadata files have lineage pointing to it.  
> W declarations list it as a dependency.

## Step 4 — Provide a change plan

If the user is performing a rename, generate the concrete steps:
1. Update the source (rename in CDC/raw declaration or SQL)
2. List each SQL file that needs a `FROM`/`JOIN` clause updated
3. List each metadata YAML that needs `lineage:` entries updated
4. List each declaration that needs `inner_dependencies` updated
5. Run `make validate-lineage-consistency` after changes

## Notes

- The repo has ~772 DAGs across 21 domain folders. Always use parallel subagents — sequential search takes too long.
- `dags/dependencies.yaml` (auto-generated) is the canonical dependency graph; cross-reference it for DAG-level dependencies.
- Column renames in clean/enrich tables cascade to all downstream dw/metric SQL and metadata.
