# BI ETL Ejuice

Analytical ETL and dimensional modeling with Airflow DAGs.

**Stack:** Python · Apache Airflow · PostgreSQL · Kimball dimensional modeling

## Modeling Rules (Kimball)

- Explicit grain, clear dimension/fact separation, business-semantic metrics
- Dimensions: singular `dim_*`, facts: plural `fact_*`, DW keys: `sk_*`
- **SCD Type 2:** define and validate `dt_valid_from`, `dt_valid_to`, `is_current`, and non-overlapping validity logic
- Treat metadata and quality checks as part of the deliverable (not optional)

## Key Files

- DAGs: `dags/`
- Package: `bietlejuice/`

Full rules: `.cursor/rules/` (if present) and `../misc/.cursor/` ETL analytics rules.

## Adding a new ingested table — mandatory file checklist

When you register a table in `*_declaration.yml` you **must** also create (or CI will fail):

1. **`queries/<layer>/<table>.sql`** — the transformation SQL for that layer
2. **`metadata/<layer>/<table>.yml`** — schema metadata with `database_name`, `table_name`, `domain`, `owner`, `description`, and per-column `description` + `lineage`

Validate before opening the PR:
```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-exist
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
make dependencies-file && git add dags/dependencies.yaml  # always regenerate and commit
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-dependency-file-correctness
```

Metadata authoring guide: `.cursor/skills/create-metadata-files/SKILL.md`
