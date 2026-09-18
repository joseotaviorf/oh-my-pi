# `base_app_ai_tools_usage` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.base_app_ai_tools_usage` |
| **Business owner** | AI Governance |
| **POC** | Victor Fonseca (`victor.fonseca@quintoandar.com.br`) |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **Consumer** | [AI Adoption Portal](https://5a-ai-adoption-portal.base44.app/) |
| **One-line summary** | Monthly per-user AI Tools Usage snapshot combining Claude spend, engagement, budget status, and organizational attributes for the AI Adoption Portal. |
| **Delivery channel** | S3 object **`s3://5a-base44-office/ai_tools_usage/ai_tools_usage.csv`** (prod). Canned ACL `bucket-owner-full-control` on write. Forno redirects to `people_bucket` under `reverse_s3_test/ai_tools_usage/ai_tools_usage.csv`. |
| **Grain** | One row per normalized user email and reference month in the latest export snapshot. |

## Source and attribution

- `dw_ai_usage.fact_ai_spend_daily` supplies monthly `consumption_usd` from
  `sum_discounted_cost_amount`, resolved to email through
  `dw_ai_usage.dim_ai_user` for the Claude tool.
- `dw_ai_usage.fact_ai_engagement_daily` supplies monthly chat, Claude Code,
  Cowork, and active-day measures, also resolved through `dim_ai_user`.
- Spend months use `dt_started`; engagement months use `dt_last_activity`.
  These source-native dates can place related spend and activity in adjacent
  months at a calendar boundary.
- Spend and engagement are combined with a `FULL OUTER JOIN` on normalized
  `(email, month)`. A user present on only one side remains in the export and
  metrics missing from the other side remain `NULL`.
- **Months before 2026-09** stay on that activity grain. Budget history in
  `dw_ai_usage.dim_ai_budget` starts in September, so unused seats are not
  invented for earlier months.
- **Months from 2026-09 onward** also include emails with a monthly USD budget
  version in force that month, even when spend and engagement are both `NULL`.
  A seated user with no activity still contributes to People and Total Limit.
  Members without a budget and without activity are not exported.
- Email keys are canonicalized upstream in the AI usage and Claude
  group-membership sources. People email values are consumed as stored. This
  export does not repeat casing or whitespace normalization.
- Current name and leadership attributes come from `dw_people.dim_employee`,
  joined to `dw_people.dim_management_hierarchy` by `person_number`. These
  current-state values are intentionally reused for every reference month, so
  historical rows may regroup after an organizational change. Because
  `dim_employee` contains current active employees, users absent from that
  dimension retain `NULL` name and leadership attributes.
  The export relies on `dim_management_hierarchy` enforcing one current row
  per person; current-version resolution belongs to that DW dimension.
- `group` comes from the latest available Claude group-membership snapshot, with
  all current group names sorted and joined with ` | `. Group membership is
  therefore current-state attribution for historical months; the source does
  not provide a versioned group history.
- Monthly USD limits for **months before 2026-09** still come from
  `dim_ai_budget` rows where `is_current = TRUE`, summed at the email grain and
  reused on those activity-only rows.
- From **2026-09 onward**, the limit is the SCD2 version in force on the last
  day of that month. Using month-end (not `{load_start_date}`) keeps seats
  whose current version was first observed later in the month. Most current
  `spend_limits` rows have a null `dt_started`, so `dt_valid_from` is coalesced
  to 2026-09-01 (the start of budget SCD2 coverage). Deleted actors are
  excluded. Multiple Claude seats that share an email are summed at the
  email/month grain.

## Output contract

Columns are emitted in the order consumed by the AI Adoption Portal:

`month`, `email`, `name`, `group`, `l1_email`, `l2_email`,
`total_limit_usd`, `consumption_usd`, `forecast_usd`, `percent_used`, `status`,
`chat_conversations`, `chat_messages`, `code_commits`, `code_prs`,
`code_lines_added`, `code_lines_removed`, `cowork_messages`, `cowork_actions`,
`cowork_dispatch_turns`, `active_days`, `ts_load`.

- `month` is a `YYYY-MM` string.
- `email` is required for export and is lowercased and trimmed upstream.
- `name`, `l1_email`, and `l2_email` are nullable. `-1` and empty leadership
  values are normalized to `NULL`; the portal can fall back to email for name.
- Numeric fields contain plain numeric values without currency symbols or
  thousands separators.
- Metrics absent from activity or budget remain `NULL`; consumers may
  coalesce them to zero for aggregate calculations. Budget-only rows from
  2026-09 onward have `NULL` consumption, forecast, and engagement measures.
- `ts_load` versions the snapshot using `CURRENT_TIMESTAMP()` from the final
  projection; it is the same value for all rows produced by one query execution.

## Derived values

- `percent_used` is
  `ROUND(COALESCE(consumption_usd, 0) / total_limit_usd * 100, 1)` when the
  limit is greater than zero, otherwise `0`. A missing cost-side row is treated
  as zero only for this derived field; the source metric remains `NULL`.
- `forecast_usd` is a documented approximation: current-month consumption is
  extrapolated from the elapsed day at `{load_start_date}` through the end of the month;
  closed-month forecast equals observed consumption. It is not a vendor
  forecast field.
- `status` uses the exact portal labels and evaluates the current-month
  elapsed percentage against `{load_start_date}`:
  - `No limit` when the limit is `NULL` or `0`;
  - `Exceeded` when `percent_used > 100`;
  - `Warning` when `percent_used` is greater than 110% of the elapsed-month
    percentage;
  - `On track` otherwise.
  Closed months are treated as 100% elapsed. Current-month rows must be
  refreshed whenever the underlying facts refresh.

## Refresh and data quality

The generic `reverse_s3` DAG rewrites the complete latest snapshot on each
scheduled run. This is safe for history and ensures current-month status and
forecast values are recalculated against `{load_start_date}`. The AI Adoption
Portal should use `ts_load` when it receives multiple snapshots.

Required invariants:

- `email` is non-null and is lowercased and trimmed upstream.
- `(email, month)` is unique within a snapshot.
- Rows are monthly aggregates; no daily rows or pre-aggregated leadership
  rollups are exported.
- L1/L2 nulls represent no leadership and are valid.

## Consumer constraint and open dependency

The current source population is approximately 1,500 users, and the available
history spans multiple months. The resulting full timeline is expected to
exceed the AI Adoption Portal's stated approximately 5,000-row total-read limit,
even though a single month is below the approximately 2,000-row limit. The
portal must add pagination or define a bounded history window before launch; otherwise
timeline data may be silently truncated. This export intentionally preserves
the complete user-month history for drill-down use.
