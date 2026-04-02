# dw_devlake — DevLake Engineering Metrics (Kimball DW)

## Overview

Kimball dimensional model built on DevLake **clean** data. Provides engineering velocity and quality metrics for all engineering lines and squads.

Schema: **`dw_devlake`** on Databricks.

## Lineage

Interactive lineage diagram: [`lineage_diagram.html`](lineage_diagram.html).

Regenerate with `tools/generate_lineage_diagram.py` (requires `pyyaml`; optionally `playwright` for PNG export).

## Upstream

- **`datalake_devlake_clean`** — produced by the `devlake` DAG (daily, 04:00 UTC)
- This DAG runs at **06:00 UTC** (2-hour offset ensures clean layer is ready)

## Tables

### Dimensions

| Table | Grain | Description |
|-------|-------|-------------|
| `dim_repo` | 1 row per GitHub repo | Repository metadata (name, URL, language) |
| `dim_team` | 1 row per team | Team hierarchy with parent LINE flattened |
| `dim_user` | 1 row per engineer | Engineer identity (name, email, GitHub username) |

### Bridge

| Table | Grain | Description |
|-------|-------|-------------|
| `bridge_pr_team` | 1 row per PR–team assignment | Many-to-many relationship (PRs can belong to multiple teams) |

### Facts

| Table | Grain | Description |
|-------|-------|-------------|
| `fact_pull_requests` | 1 row per PR | PR lifecycle, code review metrics, DORA lead time, cycle time breakdown |

### Conformed dimensions (shared)

- **`dw_public.dim_date`** — calendar dimension, joined via `sk_*_date` keys (format `YYYYMMDD`)

## fact_pull_requests — Cycle Time Breakdown

The fact table decomposes PR lifecycle into measurable phases:

```
  first_commit ──── coding_time ────► PR created ──── review_wait ────► first_comment
                                          │                                   │
                                          └──── first_approval_seconds ──────►│ first_approval
                                                                              │
                                          PR merged ◄── merge_after_approval ─┘
```

| Measure | Formula | Business question |
|---------|---------|-------------------|
| `coding_time_seconds` | `ts_created − first_commit_ts` | How long was code written before opening the PR? |
| `review_wait_seconds` | `first_comment_ts − ts_created` | How long did the PR wait for first review? |
| `first_approval_seconds` | `first_approval_ts − ts_created` | How long until first approval? |
| `merge_after_approval_seconds` | `ts_merged − first_approval_ts` | How long did approved PRs wait to merge? |
| `commit_count` | count of linked commits | Is the team doing single-commit or incremental? |
| `comment_count` | total comments | How much discussion does each PR generate? |
| `diff_comment_count` | inline code review comments | How thorough are code reviews? |
| `approval_count` | APPROVED review count | Are PRs getting approved or self-merged? |
| `changes_requested_count` | CHANGES_REQUESTED count | How much rework before approval? |
| `dismissed_review_count` | DISMISSED review events | How much rework/review churn? (17% of PRs have these; 2x longer cycle) |
| `reviewer_count` | distinct REVIEW/DIFF commenters | Is there single-reviewer risk? |
| `human_diff_comment_count` | human inline code review comments | How engaged are human reviewers? |
| `suggestion_count` | GitHub `suggestion` blocks | How many concrete code patches are proposed? |
| `actionable_comment_count` | suggestions + verbal improvements + bug flags + nits | What % of review feedback is actionable? |
| `question_comment_count` | short DIFF comments with `?` | Are reviewers seeking context or improving code? |
| `pr_size_category` | XS/S/M/L/XL from additions+deletions | How does PR size affect review quality? |

## Comment classification: precision notes

The comment quality columns (`suggestion_count`, `actionable_comment_count`, `question_comment_count`) are derived from keyword heuristics on `pull_request_comments.body`. They are **directional signals**, not exact counts. Below is an honest accuracy assessment validated against real production comments.

| Column | Precision | Real example ✅ | Known false positive ⚠️ |
|---|---|---|---|
| `suggestion_count` | **High** | `"Same idea as the other method.\n\n` ``` suggestion\n    HouseTransactStateDTO fetch...` ``` `"` — unambiguous marker | Minimal — ` ```suggestion` is specific |
| `question_comment_count` | **Good** | `"It looks like the top padding has changed. Is that intended?"` | Short quips with `?` like `"Java? 👀"` — probably acceptable |
| `human_diff_comment_count` | **High** | Counts DIFF-type comments from non-bot accounts | Depends on bot list completeness (see `bot_accounts` CTE) |
| `nit` (within actionable) | **High** | `"nit: remove extra line"`, `"Nit: The createdUntil filter is only tested via its negative path..."` | Very few — `nit:` prefix is explicit |
| `verbal_suggestion` (within actionable) | **Medium** | `"do you need this? ...available_options, by default aren't they Yes or No?"` | Catches `"are you suggesting that we should not..."` — borderline question vs suggestion |
| `bug_flag` (within actionable) | **Medium-Low** | `"this follows domi 1.5 guide on error handling"` (hits `error`) | **`"Fixed."` / `"fixed"` are author reply confirmations**, not reviewer bug flags — overcounts |
| `actionable_comment_count` (total) | **Medium** | Best used for coarse team-level trends | **Do not use for individual PR or engineer-level judgement** |

**Rule of thumb for consumers:**
- `suggestion_count` → use for precise code-improvement tracking
- `actionable_comment_count` → use for **team trends** and relative comparisons, not absolute counts
- `question_comment_count` → reliable for "how much context-seeking vs code-improving" split
- Always compare teams to *each other* rather than asserting absolute values

## Key Queries

### PR volume by team (uses bridge)

```sql
SELECT t.team_name, t.line_name, COUNT(DISTINCT f.id_pr) AS pr_count
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.bridge_pr_team AS b ON f.id_pr = b.id_pr
JOIN dw_devlake.dim_team AS t ON b.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED'
GROUP BY 1, 2;
```

### Lead time by team

```sql
SELECT t.team_name,
       ROUND(AVG(f.pr_release_time_seconds) / 3600, 1) AS avg_lead_time_hours
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.dim_team AS t ON f.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED' AND f.pr_release_time_seconds IS NOT NULL
GROUP BY 1
ORDER BY 2;
```

### Coding time vs review wait by team (new!)

```sql
SELECT t.team_name,
       ROUND(AVG(f.coding_time_seconds) / 3600, 1) AS avg_coding_hours,
       ROUND(AVG(f.review_wait_seconds) / 3600, 1) AS avg_review_wait_hours,
       ROUND(AVG(f.first_approval_seconds) / 3600, 1) AS avg_approval_hours,
       ROUND(AVG(f.merge_after_approval_seconds) / 3600, 1) AS avg_merge_lag_hours
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.dim_team AS t ON f.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED' AND f.dt_merged >= DATE_ADD(CURRENT_DATE(), -180)
GROUP BY 1
ORDER BY 4 DESC;
```

### Self-merge rate and reviewer count by team (new!)

```sql
SELECT t.team_name,
       COUNT(*) AS merged_prs,
       SUM(CASE WHEN f.approval_count = 0 THEN 1 ELSE 0 END) AS self_merged,
       ROUND(100.0 * SUM(CASE WHEN f.approval_count = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS self_merge_pct,
       ROUND(AVG(f.reviewer_count), 1) AS avg_reviewers,
       ROUND(AVG(f.diff_comment_count), 1) AS avg_inline_comments
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.dim_team AS t ON f.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED' AND f.dt_merged >= DATE_ADD(CURRENT_DATE(), -180)
GROUP BY 1
ORDER BY 4 DESC;
```

### Review quality by PR size (new!)

```sql
SELECT f.pr_size_category,
       COUNT(*) AS prs,
       ROUND(AVG(f.human_diff_comment_count), 2) AS avg_human_diffs,
       ROUND(AVG(f.suggestion_count), 3) AS avg_suggestions,
       ROUND(AVG(f.actionable_comment_count), 2) AS avg_actionable,
       ROUND(AVG(f.question_comment_count), 2) AS avg_questions,
       ROUND(100.0 * SUM(f.actionable_comment_count)
             / NULLIF(SUM(f.human_diff_comment_count), 0), 1) AS actionable_pct,
       ROUND(AVG(f.human_first_approval_seconds) / 3600, 1) AS avg_human_approval_hours
FROM dw_devlake.fact_pull_requests AS f
WHERE f.pr_status = 'MERGED' AND f.dt_merged >= DATE_ADD(CURRENT_DATE(), -180)
GROUP BY 1
ORDER BY CASE f.pr_size_category
  WHEN 'XS' THEN 1 WHEN 'S' THEN 2 WHEN 'M' THEN 3 WHEN 'L' THEN 4 ELSE 5 END;
```

### Rubber stamp detection by team (new!)

```sql
SELECT t.team_name,
       COUNT(*) AS merged_prs,
       SUM(CASE WHEN f.human_approval_count > 0 AND f.human_diff_comment_count = 0 THEN 1 ELSE 0 END) AS rubber_stamps,
       ROUND(100.0 * SUM(CASE WHEN f.human_approval_count > 0 AND f.human_diff_comment_count = 0 THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS rubber_stamp_pct
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.dim_team AS t ON f.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED' AND f.dt_merged >= DATE_ADD(CURRENT_DATE(), -180)
GROUP BY 1
ORDER BY 4 DESC;
```

### Rework rate and dismissed reviews by team (new!)

```sql
SELECT t.team_name,
       COUNT(*) AS merged_prs,
       SUM(CASE WHEN f.dismissed_review_count > 0 THEN 1 ELSE 0 END) AS prs_with_rework,
       ROUND(100.0 * SUM(CASE WHEN f.dismissed_review_count > 0 THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS rework_pct,
       ROUND(AVG(CASE WHEN f.dismissed_review_count > 0
                      THEN f.human_first_approval_seconds / 3600.0 END), 1) AS avg_rework_approval_hours,
       ROUND(AVG(CASE WHEN f.dismissed_review_count = 0
                      THEN f.human_first_approval_seconds / 3600.0 END), 1) AS avg_clean_approval_hours
FROM dw_devlake.fact_pull_requests AS f
JOIN dw_devlake.dim_team AS t ON f.sk_team = t.sk_team
WHERE f.pr_status = 'MERGED' AND f.dt_merged >= DATE_ADD(CURRENT_DATE(), -180)
GROUP BY 1
ORDER BY 4 DESC;
```

## Future: `pull_request_reviewers` ingestion

The DevLake `pull_request_reviewers` table (264K rows) tracks **requested reviewers** per PR — distinct from who actually submitted a review. This enables:

- **"Requested but never reviewed" rate** — prod data shows **31.7%** of review requests go unanswered
- **Reviewer assignment patterns** — who gets requested most, reviewer load distribution
- **Response rate by reviewer** — individual reviewer engagement

Ingestion requires Kafka Connect + S3 Sink + Airflow DAG declaration changes (same pattern as `pull_request_commits` and `pull_request_comments`).

## Bus Matrix (future)

| Fact | dim_repo | dim_team | dim_user | dim_date |
|------|----------|----------|----------|----------|
| fact_pull_requests | X | X | X | X |
| fact_deployments (planned) | X | X | X | X |
| fact_issues (planned) | | X | X | X |
| fact_incidents (planned) | X | X | | X |
