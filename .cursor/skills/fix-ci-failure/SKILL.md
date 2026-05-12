---
name: fix-ci-failure
description: Diagnose and fix a Woodpecker CI failure. Given a failing step name or error message, reproduces the failure locally, identifies the root cause, and applies the fix. Use when the user shares a CI error, a Woodpecker step that failed, or says "CI is failing" / "my PR is red".
---

# Fix CI Failure

## When to use

- User shares a Woodpecker step name that failed (e.g. `validate-metadata-files-content`)
- User pastes a CI error message or log snippet
- User says "CI is failing on my PR" without specifying which step

---

## Step 1 — Identify the failing step

Ask the user (or infer from context) which Woodpecker step failed. The full list of CI steps from `.woodpecker/validations.yml`:

| Woodpecker step name | Local `make` equivalent | Category |
|----------------------|------------------------|----------|
| `validate-dag-declaration-files` | `make validate-dag-declaration-files level=debug` | Declaration |
| `validate-dags-up-to-standard` | `make validate-dags-up-to-standard` | Declaration |
| `validate-dags-dependencies-forno` | `ENVIRONMENT=forno make validate-dags-dependencies` | Dependencies |
| `validate-dags-dependencies-prod` | `ENVIRONMENT=prod make validate-dags-dependencies` | Dependencies |
| `validate-dependency-file-correctness` | `make validate-dependency-file-correctness` | Dependencies |
| `validate-metadata-files-content` | `make validate-metadata-files-content` | Metadata |
| `validate-metadata-files-exist` | `make validate-metadata-files-exist` | Metadata |
| `validate-lineage-consistency` | `make validate-lineage-consistency` | Metadata |
| `validate-core-model-schemas` | `make validate-core-model-schemas` | Core model |
| `validate-core-model-schema-content` | `make validate-core-model-schema-content` | Core model |
| `validate-cross-layer-joins` | `make validate-cross-layer-joins` | Governance |

If the user doesn't know the step name, ask them to share the error message — the text often reveals the category (e.g. "metadata file missing" → `validate-metadata-files-exist`).

---

## Step 2 — Reproduce locally

Run the local equivalent of the failing step. Use a shell subagent (Task tool with `subagent_type: shell`) so the output is captured fully.

```bash
cd /path/to/bi-etl-ejuice

uv sync --directory packages/bietlejuice-compiler

make {failing_make_target}
```

Ask the subagent to return: exit code, full stdout, and all lines containing `ERROR`, `FAIL`, `Warning`, or file paths.

**Important**: The CI scripts compare against `origin/master` via `git fetch`. Make sure the local repo has fetched the remote before running:
```bash
git fetch --no-tags origin +refs/heads/master
```

---

## Step 3 — Diagnose by error pattern

### Declaration failures (`validate-dag-declaration-files`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `missing required field: ...` | A required YAML key is absent in `*_declaration.yml` | Add the key per the `dag_build` rule |
| `invalid value for field: ...` | A value does not match the allowed enum or type | Correct the value (check the `dag_build` rule for allowed values) |
| `dag_name does not match folder name` | Mismatch between `dag.name` in YAML and the containing folder | Align the `dag.name` with the folder name |
| `unknown field: ...` | A key that does not exist in the declaration schema | Remove the unknown key |

### Metadata failures (`validate-metadata-files-exist`, `validate-metadata-files-content`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `metadata file missing for queries/...` | A `.sql` file has no matching `.yml` in `metadata/` | Create `metadata/{layer}/{table_name}.yml` with the required fields |
| `description too short` | `description:` field < 10 characters | Expand the description |
| `owner does not match email regex` | `owner:` is not a valid email | Set `owner: user@quintoandar.com.br` |
| `invalid domain` | `domain:` is not in the allowed list | Use a valid domain (see governance_metadata rule for the full list) |
| `missing required field: lineage` | Enrich/DW column has no `lineage:` | Add `lineage: [database.table.column]` for each column |
| `metric column missing dimension or metric block` | Metric-layer column has no `dimension: true` or `metric:` block | Add the appropriate block per the governance_metadata rule |
| `mapping values are not allowed here` / `mapping values are not allowed in this context` (with `yaml.scanner.ScannerError` and line/column) | An unquoted colon (`:`) in the middle of a YAML string (e.g. in a `description:` line) is interpreted as a key-value separator | At the reported line/column, rephrase to remove the colon (e.g. use em dash "—"), or quote the string; e.g. "TODO in view: confirm" → "TODO in view — confirm" or `"TODO in view: confirm"` |

### Lineage failures (`validate-lineage-consistency`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `column in SQL not found in metadata` | A column selected in the SQL has no entry in the metadata YAML | Add the column to the metadata YAML with `lineage:` |
| `lineage source not referenced in SQL` | Metadata `lineage:` points to a source table not in the SQL | Fix the lineage to match the actual SQL `FROM`/`JOIN` sources |
| `table in SQL not in lineage` | SQL references a table not listed in any lineage entry | Add the correct `lineage:` entries for all source columns |

### Dependency failures (`validate-dags-dependencies`, `validate-dependency-file-correctness`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `DAG not found in dependencies.yaml` | A new DAG was added but `dependencies.yaml` was not regenerated | Run `make dependencies-file` and commit the updated file |
| `dependency cycle detected` | A circular dependency was introduced | Review the dependency chain and break the cycle |
| `dependency file out of sync` | `dependencies.yaml` does not match what the generator would produce | Run `make dependencies-file` to regenerate and commit |

### Standard failures (`validate-dags-up-to-standard`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `DAG not using DAG Builder` | A DAG Python file was written manually instead of via the declaration YAML | Migrate the DAG to a `*_declaration.yml` + `make create-dag-files` |
| `DAG not using CDC for ...` | A raw ingestion DAG is using a deprecated workflow type | Migrate to `type: cdc` per the `create-dag` skill |

### Cross-layer join warnings (`validate-cross-layer-joins`)

This step **always exits 0** (warning only — it never blocks CI). If it reports violations:
- Review the SQL file flagged
- Either fix the query to avoid raw-layer references in DW queries
- Or add the path to `packages/bietlejuice-compiler/scripts/governance_metadata_validation/skip_list.yml` under `cross_layer_joins_dw_raw` with a justification comment

### Core model failures (`validate-core-model-schemas`, `validate-core-model-schema-content`)

| Error message pattern | Root cause | Fix |
|----------------------|-----------|-----|
| `schema file missing for core model table` | A core model table has no schema file | Create the schema file under the expected path |
| `schema file has incorrect structure` | Schema file content does not match the expected format | Fix the schema file per the validation script's error details |

---

## Step 4 — Apply the fix

Based on the diagnosis, make the targeted edits:

- For metadata issues: edit the `.yml` file in `metadata/{layer}/`
- For declaration issues: edit the `*_declaration.yml` file
- For lineage issues: align the SQL `SELECT` columns with the metadata `columns:` block
- For dependency issues: run `make dependencies-file` and commit the result

After applying fixes, re-run **only the originally failing check** to confirm it passes:

```bash
make {failing_make_target}
```

---

## Step 5 — Confirm all checks pass

If the user is close to merging, run all validations in parallel to confirm nothing else is broken. Use three shell subagents simultaneously:

**Subagent A:**
```bash
make validate-dag-declaration-files level=debug && make validate-dags-up-to-standard
```

**Subagent B:**
```bash
make validate-metadata-files-exist && make validate-metadata-files-content && make validate-lineage-consistency
```

**Subagent C:**
```bash
make validate-dependency-file-correctness && make check-style
```

All three must exit with code 0 before the PR is ready. If any still fail, return to Step 3.

---

## Common "catch-all" scenarios

### "I added a new table but CI is failing"

Most likely sequence of failures:
1. `validate-metadata-files-exist` — metadata YAML missing → create it
2. `validate-metadata-files-content` — metadata YAML has short description or missing fields → fix it
3. `validate-lineage-consistency` — metadata columns don't match SQL columns → align them
4. `validate-dag-declaration-files` — new table not in `tables_customization` → add it

### "I regenerated the dependencies file but CI still fails"

Check that you committed the updated `dependencies.yaml`. The CI runs on the pushed commit, not your local state.

### "The step passes locally but fails in CI"

The most common reason: CI compares against `origin/master` but locally you haven't fetched the latest master. Run:
```bash
git fetch --no-tags origin +refs/heads/master
make {failing_make_target}
```
