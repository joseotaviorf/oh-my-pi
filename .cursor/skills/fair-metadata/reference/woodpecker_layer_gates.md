# Woodpecker / CI gates vs layer (source of truth)

Schema definitions: `packages/bietlejuice-compiler/scripts/services/metadata_file_schemas/`.

**Two different “scopes”:**

| Scope | Used for | Command |
|-------|----------|---------|
| **User scope** | PLAN audit — Gates A/B/C per [`SKILL.md`](../SKILL.md) | `make audit-fair-metadata-scope domain=…` |
| **PR diff** | Woodpecker CI on changed files only | `make validate-fair-metadata` |

---

## Which Woodpecker steps run when

| Step | Path filter (PR) | What it validates |
|------|------------------|-------------------|
| **`validate-metadata-files-exist`** | `dags/**/*.sql` changed | SQL must have matching metadata YAML |
| **`validate-metadata-files-content`** | `dags/**/*.yml` changed | Yamale: owner email, domain allowlist, min description length, `columns` map shape, metric blocks, etc. |
| **`validate-lineage-consistency`** | metadata or SQL in diff | SQL ↔ YAML column names when both exist |
| **`validate-fair-metadata`** | metadata changed vs `origin/master` | **F2-01** substantive table + **F2-02** substantive column descriptions on **clean / core / enrich / dw / metric** (skips raw) |

**No overlap:** do not re-check in `validate-fair-metadata` what Yamale already enforces (`owner`, `domain`, table/column min length, YAML shape).

---

## Yamale — `metadata/raw/` (`raw_schema.yml`)

| Field | CI (Yamale) |
|-------|-------------|
| `database_name`, `table_name`, `domain` | Required |
| `owner`, `description` (table) | Optional |
| `columns` | Optional — allowed when present |
| Column `tags` | Allowed (legacy); prefer not adding `-pii`/`-confidential` on new raw files |

Many raw tables use **Spark jobs** with no `queries/raw/*.sql` → **lineage-consistency does not run** on raw.

**Remediation preference:** document columns on **clean+**; raw may stay table-level only when not in PR diff.

---

## Yamale — `metadata/clean/` and above

| Field | CI (Yamale) | FAIR (`validate-fair-metadata`) |
|-------|-------------|----------------------------------|
| `description` (table) | Required min 10 chars (clean+) | **F2-01 substantive** (same TDQ heuristics as columns) |
| `columns` | Required map (clean+) | — |
| Each column `description` | Required min 10 chars | **F2-02 substantive** (semantic quality) |
| `lineage` | Required on derived columns (enrich/dw) | — |

**Primary documentation layer:** clean → core → enrich → dw → metric.

---

## Agent workflow

### PLAN — full user scope

1. Resolve inventory ([`scoping.md`](scoping.md)).
2. `make audit-fair-metadata-scope …` — Gate A (owners), Gate B (F2-01 table + F2-02 columns on clean+).
3. Post plan; wait for approval.

### EXECUTE — PR-sized batches

1. Edit up to ~10 tables from scope inventory.
2. Re-run **scope audit** on the same user scope (not only diff).
3. CI on branch:

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
```

4. Prefer rich documentation on **clean+**; touch raw only when in PR diff or Yamale failed on it.

---

## Lake vs PR

Production `enrich_fairness_assessment` reads **clean** exports. Improving lake tier requires clean+ metadata. Optional raw `columns:` does not block CI.
