# DevLake Ingestion

## Overview

Daily ingestion of core DevLake tables from the production MySQL RDS into Databricks (raw + clean layers). DevLake is QuintoAndar's engineering metrics platform, collecting data from GitHub and Jira.

## Data Sources

| Source | Type | Host |
|--------|------|------|
| DevLake MySQL | RDS MySQL 8.0 | devlake-prod.ciuoqxapzjot.us-east-1.rds.amazonaws.com |

## Tables Ingested

| Raw Table | Clean Table | Description |
|-----------|-------------|-------------|
| `pull_requests` | `pull_requests` | GitHub pull requests with enrichment (type, release time) |
| `pr_custom_metrics` | `pr_custom_metrics` | PR release and deploy time metrics |
| `pull_request_team` | `pull_request_team` | PR-to-team bridge (factless, many-to-many) |
| `repos` | `repos` | GitHub repositories in DevLake scope |
| `teams` | `teams` | Org hierarchy synced from Backstage (LINE/TEAM hierarchy) |
| `pull_request_commits` | `pull_request_commits` | Commits linked to PRs (author, date) |
| `pull_request_comments` | `pull_request_comments` | PR comments and reviews (timestamps, type) |
| `users` | `users` | Catalog users synced from Backstage (includes `chapter` in clean layer when present upstream) |

## Downstream

- **dw_devlake** — Kimball dimensional model (fact_pull_requests, dim_repo, dim_team, dim_user, bridge_pr_team)

## Credentials

Databricks secret key: `DEVLAKE_DB`. Contact the Tech Platform Engineering Productivity team to provision access.

## Schedule

Daily at 04:00 UTC.

## Adding a new table — checklist

When registering a new table in `devlake_declaration.yml` you **must** also create the following files or CI will fail:

| File | Path | Purpose |
|------|------|---------|
| Clean SQL query | `queries/clean/<table>.sql` | Rename raw columns to QuintoAndar conventions (`id_` prefix, `ts_` for timestamps, `is_` for booleans) and select only business-relevant columns from `datalake_devlake_raw.<table>` |
| Clean metadata | `metadata/clean/<table>.yml` | Describes every output column — `database_name`, `table_name`, `domain`, `owner`, `description`, per-column `description` + `lineage`. Validated by `make validate-metadata-files-content` |

**Validate locally before opening the PR:**
```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-exist
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
make dependencies-file   # regenerates dags/dependencies.yaml — commit the result
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-dependency-file-correctness
```

See `.cursor/skills/create-metadata-files/SKILL.md` for the full metadata authoring guide.
