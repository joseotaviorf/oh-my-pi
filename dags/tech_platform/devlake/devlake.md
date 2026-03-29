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
| `users` | `users` | Engineers synced from Backstage |

## Downstream

- **dw_devlake** — Kimball dimensional model (fact_pull_requests, dim_repo, dim_team, dim_user, bridge_pr_team)

## Credentials

Databricks secret key: `DEVLAKE_DB`. Contact the Tech Platform Engineering Productivity team to provision access.

## Schedule

Daily at 04:00 UTC.
