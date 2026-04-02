# Engineering Line Report — Prompt Template

> **How to use:** Copy everything inside the `---` fences below, paste it as a new chat message (with your Trino MCP active), and replace `<YOUR_LINE_NAME>` with your line name (e.g. `Fintech`, `BSG`, `For Rent`, `Conversational XP`).  
> The AI will query DevLake, generate the full analysis, and render an interactive HTML dashboard.

---

## Data background

The schema lives in Trino at `delta.datalake_devlake_clean` with six tables:

| Table | Description |
|---|---|
| `pull_requests` | One row per PR — status, author, dates, size (additions/deletions), type label |
| `pull_request_team` | Bridge: PR ↔ team (M:M) |
| `teams` | Org hierarchy — `team_type = 'LINE'` or `'TEAM'`, `id_parent_team` links teams to their LINE |
| `repos` | Repository metadata |
| `users` | Engineer identity |
| `pr_custom_metrics` | Per-PR release time (`pr_release_time_seconds`) and deploy time (`pr_deploy_time_seconds`) |

Key joins: `pull_requests ⟵ pull_request_team ⟶ teams` via `(id_repo, pr_key)`.  
Release/deploy metrics: `pr_custom_metrics.id_pr = pull_requests.id_pr`.

A note on `dw_devlake` (Databricks DW layer): the clean tables above are the source of truth for ad-hoc analysis via Trino. The `dw_devlake` Kimball model (`fact_pull_requests`, `dim_team`, `bridge_pr_team`) is available on Databricks for BI tools but may not be accessible here.

---

## The prompt

```
Use the Trino MCP to run a deep-dive engineering report for the **<YOUR_LINE_NAME>** line.
The analysis covers the last 6 months (October 2025 → March 2026).

All data lives in `delta.datalake_devlake_clean`. The tables are:
- pull_requests (id_pr, id_repo, pr_key, pr_title, pr_status, pr_base_branch, id_author_user,
  author_name, id_merged_by_user, merged_by_name, is_merged, is_draft, pr_additions,
  pr_deletions, pr_type, ts_created, ts_merged)
- pull_request_team (id_repo, pr_key, id_team)
- teams (id_team, team_name, team_alias, team_type, id_parent_team)
- pr_custom_metrics (id_pr, repo_name, ts_released, pr_release_time_seconds,
  pr_deploy_time_seconds, ts_created)

Join PRs to teams via: pull_requests.id_repo = pull_request_team.id_repo
                    AND pull_requests.pr_key  = pull_request_team.pr_key
                    AND pull_request_team.id_team = teams.id_team

---

### Step 1 — Discover the line's teams

Find all teams that belong to the <YOUR_LINE_NAME> line. The line itself has team_type = 'LINE'.
Its child teams have id_parent_team = (the LINE's id_team).
Also check if there are any teams whose name or alias contains the line name.
Print the full team list with their aliases before proceeding.

---

### Step 2 — Run these queries (in parallel where possible)

Use the team_name list from Step 1 to filter all queries below with:
  WHERE t.team_name IN ('<team1>', '<team2>', ...)
  AND   pr.ts_created >= TIMESTAMP '2025-10-01 00:00:00 UTC'

**A — Throughput + merge rate**
  Per team: total PRs opened, merged PRs, merge rate %, distinct contributors,
  PRs per contributor. Sort by total_prs DESC.

**B — Cycle time (open → merge)**
  Per team (merged PRs, ts_merged IS NOT NULL): avg, P50, P75, P90 of
  date_diff('hour', ts_created, ts_merged). Only teams with ≥ 10 merged PRs.
  Sort by P50 ASC.

**C — PR size (merged PRs only)**
  Per team: avg and APPROX_PERCENTILE(additions+deletions, 0.5) as median_size,
  avg additions, avg deletions. Only teams with ≥ 10 merged PRs. Sort by avg_size ASC.

**D — Delivery speed (release + deploy)**
  Join pr_custom_metrics on id_pr. Filter pr_release_time_seconds > 0.
  Per team: avg release time (hours), P50 release, P90 release,
  avg deploy time, P50 deploy. Only teams with ≥ 5 observations. Sort by P50 ASC.

**E — Monthly PR volume trend**
  DATE_FORMAT(DATE_TRUNC('month', ts_created), '%Y-%m') as month, team_alias, COUNT(*) as prs.
  All TEAM-type teams in the line. Group by month + team. Order by month, prs DESC.

**F — PR type label hygiene**
  Per team: total PRs, labeled PRs (pr_type IS NOT NULL), coverage %,
  and breakdown by pr_type (feat/fix/chore/refactor/test/perf/docs/null).
  Sort by coverage % DESC.

**G — Top contributors**
  Per team: author_name, PR count, avg cycle time (hours). Min 3 PRs per author.
  Sort by team then PR count DESC. Limit to top 5 per team.

**H — Review quality**
  Per team (merged PRs): avg human_diff_comment_count, avg suggestion_count,
  avg actionable_comment_count, avg question_comment_count,
  actionable_pct (actionable / human_diff * 100),
  rubber_stamp_pct (PRs with human_approval > 0 AND human_diff = 0 / total * 100).
  Sort by actionable_pct DESC.

**I — Review quality by PR size**
  Per pr_size_category: avg human_diff_comment_count, avg suggestion_count,
  actionable_pct, avg human_first_approval_seconds / 3600 as avg_approval_hours.
  Filter by the line's teams. Sort by size bucket.

**J — Rework rate (dismissed reviews)**
  Per team (merged PRs): total PRs, PRs with dismissed_review_count > 0, rework_pct,
  avg cycle hours for rework PRs vs clean PRs. Sort by rework_pct DESC.

---

### Step 3 — Identify signals

After running the queries, look for and explicitly flag:

1. **New/growing teams**: any team with 0–few PRs in Oct–Nov then ramping sharply?
2. **Team transitions**: any engineer appearing across multiple teams (same person in 2+ team
   datasets)? This may indicate a reorg.
3. **Cycle time outliers**: teams or individuals with P90 > 168h (1 week) — flag as review debt.
4. **PR size anomaly**: teams where avg >> 3× median — likely auto-generated or migration PRs.
5. **Broken delivery**: teams with P50 release > 24h — not on a CD pipeline.
6. **Zero hygiene**: teams with < 10% PR label coverage — change intent invisible.
7. **Contributor ghost accounts**: engineers with 1 PR and no activity before/after — likely
   cross-team one-offs; do not count them as team members.
8. **Rubber stamp reviews**: teams where > 50% of approved PRs have 0 inline comments —
   reviews may not be effective.
9. **Rework-heavy teams**: teams where > 25% of PRs have dismissed reviews — indicates
   either CI/CD instability or significant rework cycles.
10. **Review quality gap**: teams where actionable_pct < 20% — reviewers may be approving
    without meaningful engagement (questions or suggestions).

---

### Step 4 — Build an interactive HTML canvas dashboard

Create a rich, dark-theme HTML dashboard with Chart.js (cdn.jsdelivr.net/npm/chart.js@4.4.0)
and Google Fonts. Save it to the canvas folder and open it in the browser.

The dashboard must include:

**Header**: line name, date range, total PRs, merge rate, number of active teams
as headline KPIs.

**Tab 1 — Overview**: horizontal bar chart of PRs by team (colored by team),
plus a small table of PRs/dev by team.

**Tab 2 — Monthly Trends**: line chart (BSG-style) with one line per team, Oct–Mar.
Use distinct colors per team, interactive legend toggles, tooltip with index mode.

**Tab 3 — Cycle Time**: grouped horizontal bar with P50/P75/P90 per team.
Color-coded: P50 green, P75 blue, P90 red. Full table alongside.

**Tab 4 — PR Size**: side-by-side bar (avg vs median) per team.
Highlight teams where avg > 3× median with an orange label.

**Tab 5 — Delivery**: horizontal bar of P50 release time. Flag teams > 24h in red.
Second chart: avg release vs avg deploy side-by-side.

**Tab 6 — PR Hygiene**: horizontal bar of label coverage % per team.
Color threshold: green > 60%, yellow 30–60%, red < 30%.
Stacked bar of type mix (feat/fix/chore/refactor/test) for well-labeled teams.

**Tab 7 — People**: shared engineers table (person appears in 2+ teams),
top contributors table per team with PR count + avg cycle time.

**Tab 8 — Review Quality**: stacked bar of avg actionable / question / other per team.
Second chart: rubber stamp % by team (horizontal bar, red > 50%).
Small table: suggestion_count, actionable_pct, question_pct per team.

**Tab 9 — Rework**: horizontal bar of rework_pct (% PRs with dismissed reviews) per team.
Side-by-side: avg cycle hours for rework PRs vs clean PRs per team.
Highlight teams where rework PRs take > 2× longer than clean PRs.

**Tab 10 — Review by Size**: grouped bar of avg human DIFF comments by pr_size_category.
Line overlay of actionable_pct by size bucket (expect decline for XL).

**Tab 11 — ⚡ Signals**: summary of all flagged issues and highlights from Step 3,
grouped as ✅ Strengths / ⚠️ Risks / 🚨 Critical / 💡 Structural signals.
Use color-coded callout cards.

Design guidelines:
- Dark background (#060a0f or similar), high contrast accent colors
- Font: pair a geometric/display font (Unbounded, Syne, Space Grotesk) with a
  mono font (DM Mono, JetBrains Mono) for data
- No generic purple-on-white. Use a cohesive accent palette (e.g. green + blue + orange)
- Animated tab transitions, staggered card reveals
- Each tab renders its charts lazily (only when first visited)
- Canvas must be fully self-contained (all data embedded in JS constants)

---

### Step 5 — Write the markdown summary

After the canvas, write a structured markdown analysis covering:

## <LINE> Engineering Report — Oct 2025 → Mar 2026

### Headline numbers
(total PRs, merge rate, teams, top throughput team, fastest cycle time team)

### Throughput
(table + 2–3 sentence narrative)

### Cycle Time
(table + narrative highlighting best/worst + individual outliers)

### PR Size
(table + note on avg vs median anomalies)

### Delivery Pipeline
(table + call out any teams not on CD)

### PR Hygiene
(coverage table + note on what good looks like)

### Review Quality
(actionable %, suggestion count, rubber stamp rate per team — flag teams with low engagement)

### Rework Rate
(dismissed review %, cycle time impact of rework — teams where rework > 25% need attention)

### People
(shared engineers, reorg signals, top contributors)

### Key Recommendations
(3–5 numbered, actionable recommendations with specific team names)
```

---

## Tips for line leads

- **Filter to your line only**: the prompt auto-discovers your teams from the `teams` table, but double-check the printed list in Step 1 before trusting the metrics.
- **Exclude auto-generated PRs**: if you see avg PR size >> 3× median for a team, ask the AI to re-run PR size excluding PRs where `pr_additions > 2000` to get the human-authored baseline.
- **Historical comparison**: change the `ts_created >= TIMESTAMP '2025-10-01 00:00:00 UTC'` filter to a different period to compare quarters.
- **Drill into a team**: after running the full line report, say _"Now zoom into \<team name\> — show me the contributor breakdown, monthly trend, and the 10 slowest-to-merge PRs."_
- **Reorg detection**: if several engineers appear across teams or teams have unusual ramps, ask _"Does the contributor overlap and timing suggest a team reorganization? Summarize what you see."_
