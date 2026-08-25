# Jira Bugs — Data & AI Incidents

## Ownership

**Data Owner:**
- luisa.frodrigues@quintoandar.com.br

**Data Steward:**
- luisa.frodrigues@quintoandar.com.br

---

## Overview

A **bug** here is a Jira Service Management issue opened against the QuintoAndar **Bugs** project (`project.id = 10400`) to report a data or platform problem. This domain is the analytical backbone for **data incident management** — tracking who reported a bug, which product line/squad owns it, whether it was handled by the **Data & AI team**, how long it took to respond and resolve, and whether SLAs were met.

Each issue is created through a Jira **request type** (a form). The one that matters for Data & AI analysis is:

- **`id_request_type = 9228`** — the **"Form S&S Dados"** (Data Support & Services form). This is the intake form through which data-related bugs/incidents are reported. Virtually every Data & AI incident query filters on this request type.

An issue carries:
- **A product line** (`id_line` / `line_name`, from custom field `customfield_12221` / `customfield_25331`) — the business line the bug is attributed to (e.g. "For Rent", "For Sale", "Fintech").
- **A squad** (`squad_name`, `initial_squad_name`) — the team currently and originally responsible. The Data & AI team's squad label is `"Data"`.
- **SLA clocks** — first-response and resolution SLAs sourced from Jira SLA custom fields.
- **Form answers** — module, problem type, impacted DAG, integration type, etc. (the `form_response_*` / alias columns).
- **Comments and attachments** — concatenated per issue.

### Lifecycle / status

`status` reflects the current Jira workflow state. Key states and their derived flags:

| Status (`status`) | Derived flag |
|---|---|
| `Open` | `status = 'Open'` → open bug |
| `Triage` | `is_in_triage` |
| `NEED MORE INFO` | `is_need_more_info` |
| `Under investigation` | `is_under_investigation` |
| `Invalid` | `is_invalid_bug` |
| `Close - Resolved` | `is_resolved`, `is_closed` |
| `Close - Not Resolved` | `is_closed` (not resolved) |

## Glossary and Synonyms

- **Bug**, **incidente**, **incidente de dados**, **chamado de dados** → an issue in `datalake_jira_bugs.bug_issues`
- **Form S&S Dados**, **formulário de dados**, **form Data & AI** → request type `9228` (`id_request_type = 9228`)
- **Line / linha / linha de negócio** → `line_name` (custom field), mapped to an owning data team via `incident_responsible`
- **Squad / time** → `squad_name` (current), `initial_squad_name` (original). Data & AI = `"Data"`
- **Redirecionado / redirect** → bug that started in the Data & AI squad but was reassigned elsewhere (`is_data_ai_team_redirected`)
- **SLA de primeira resposta** → `sla_first_response_status`
- **SLA de resolução** → `sla_resolution_status`
- **SLA cumprido / estourado** → SLA met / breached (Portuguese status labels, see below)
- **Bug inválido** → `is_invalid_bug` (status `Invalid`)

## Tables

| You need... | Use this table |
|-------------|----------------|
| The central enriched bug/issue entity (context + SLA + comments/attachments; **may hold >1 snapshot per issue** — see grain note) | `datalake_jira_bugs.bug_issues` (`b`) |
| Raw Jira issue snapshots (JSON `fields`) — source for `bug_issues` | `datalake_jira_clean.issues` (`i`) |
| Per-comment detail for an issue | `datalake_jira_bugs.comments` |
| Per-attachment detail for an issue | `datalake_jira_bugs.attachments` |
| Jira user account lookup (author display name) | `datalake_jira_bugs.user_account` |

`bug_issues` is built by the `enrich_jira_bugs` DAG. It reads `datalake_jira_clean.issues`, keeps only `project.id = 10400`, and dedups **within each load** (`QUALIFY ROW_NUMBER() OVER (PARTITION BY key ORDER BY MAKE_DATE(year,month,day) DESC) = 1`, in Databricks SQL). Owner: `luisa.frodrigues@quintoandar.com.br`.

> ⚠️ **Grain caveat — validated against production.** The served table is **not** strictly one row per issue: it accumulates snapshots across `ts_load`. A test over request type 9228 returned **265 rows for 233 distinct `id_issue`** (29 issues had 2–3 snapshots). **Always dedup to the latest snapshot per `id_issue` in your query** before counting or aggregating:
>
> ```sql
> -- Trino has NO QUALIFY — use a ROW_NUMBER subquery + WHERE rn = 1
> SELECT * FROM (
>     SELECT *,
>         ROW_NUMBER() OVER (PARTITION BY id_issue ORDER BY ts_load DESC, ts_updated DESC) AS rn_snap
>     FROM datalake_jira_bugs.bug_issues
>     WHERE id_request_type = 9228
> ) WHERE rn_snap = 1
> ```

### Key columns in `bug_issues`

| Column | Description |
|--------|-------------|
| `id_issue` | Jira issue key (identifier) |
| `id_line`, `line_name` | Product line id and name (custom fields) |
| `id_request_type`, `request_type_name` | JSM request type — **`9228` = Form S&S Dados** |
| `squad_name`, `initial_squad_name` | Current and original squad; `"Data"` = Data & AI team |
| `assignee_name`, `creator_name`, `reporter_name` | People on the issue |
| `status`, `status_category`, `previous_status` | Workflow status |
| `priority` | Issue priority |
| `total_comments`, `total_attachments` | Counts in the latest snapshot |
| `sla_first_response_status`, `sla_resolution_status` | Portuguese SLA status labels (see below) |
| `first_response_hours`, `sla_resolution_hours` | Elapsed hours to first response / resolution |
| `first_response_delay_hours`, `resolution_delay_hours` | Hours over the SLA goal (0 when met) |
| `is_sla_first_response_agreed`, `is_sla_resolution_agreed` | SLA met flags |
| `is_data_ai_team_bug` | `id_request_type = 9228 AND squad_name = 'Data'` — bug currently owned by Data & AI |
| `is_data_ai_team_redirected` | Started in `"Data"` (`initial_squad_name` contains `Data`) but current squad ≠ `"Data"` |
| `is_invalid_bug`, `is_in_triage`, `is_need_more_info`, `is_under_investigation`, `is_resolved`, `is_closed` | Status-derived booleans |
| `ts_created`, `ts_resolved`, `ts_updated` | Creation / resolution / last-update timestamps |
| `ts_sla_resolution_completed` | SLA-resolution completion timestamp (preferred resolution ts, see Dos & Don'ts) |
| `dag`, `problem_type`, `problem_description`, `integration_type`, `data_model_issue` | Form-answer fields describing the reported problem |

### SLA status labels (Portuguese, from the source SQL)

Both `sla_first_response_status` and `sla_resolution_status` take one of:

- `SLA cumprido` — completed and **not** breached
- `SLA estourado` — completed but breached
- `Em andamento - dentro do SLA` — not completed, within SLA
- `Em andamento - SLA estourado` — not completed, already breached
- `Sem SLA` — no SLA clock

## Key Concepts

### Data & AI ownership: bug vs redirected vs created-by-form

Three related but distinct flags exist to answer "was this a Data & AI issue?":

| Flag | Meaning |
|---|---|
| `is_data_ai_team_bug` | Request type 9228 **and** currently owned by squad `"Data"` |
| `is_data_ai_team_redirected` | Originated in squad `"Data"` (initial squad) but has since moved to another squad |
| **created-by-data-ai-form** (derived) | `is_data_ai_team_bug OR is_data_ai_team_redirected` — i.e. anything the Data & AI team owned at any point. Use this to count all bugs that entered through the Data & AI flow. |

The `created-by-data-ai-form` flag is **not** a physical column — derive it in the query:
```sql
CASE WHEN b.is_data_ai_team_bug = TRUE OR b.is_data_ai_team_redirected = TRUE
     THEN TRUE ELSE FALSE END AS is_created_by_data_ai_form
```

### Line name → owning data team (`incident_responsible`)

`line_name` is a free-ish custom field and needs two treatments before it is analysis-ready:

1. **Deduplication.** The same `id_line` can carry slightly different `line_name` strings across snapshots. Resolve to the **most frequent** name per `id_line` (tie-break by earliest `ts_updated`) using a `ROW_NUMBER()` CTE — see Golden Query 1.
2. **Mapping to a responsible data team** (`incident_responsible`). This label groups bugs by the data product team accountable for the line. It is used to filter the summary dashboard, so **the output column must keep the name `incident_responsible`** across datasets.

| `line_name` | `incident_responsible` |
|---|---|
| Partners (3P) | Data 3P Partners |
| Partners (Agents) | Data Agents |
| Single Station | Data SS |
| Support & Services | Data SS |
| Conversational XP | Data Conversational XP |
| For Rent | Data For Rent |
| For Sale | Data For Sale |
| Primitives | Data Primitives |
| Tech Platform | Tech Platform Dev Foundation |
| Fintech | Data Fintech |
| BSG | Data Growth |
| Data & AI - Core Teams | Data Core |
| *(NULL / blank line_name)* | Data Core |
| QCX, Cross Resources, For Living, Classifieds | *(NULL — not yet mapped)* |
| anything else | NULL |

## Relationships with Other Entities

- **Zendesk `ticket`** — Jira bugs are a **separate** incident channel from Zendesk support tickets. Do not confuse `datalake_jira_bugs.bug_issues` with `dw_customer_support.fact_tickets`; they have no shared surrogate key. Jira bugs track data-platform incidents; Zendesk tickets track customer support requests.
- **Product lines / squads** — `line_name` and `squad_name` are attributes on the issue, not FKs to a dimension. Group/filter on them directly.

## Dos and Don'ts

**Do:**
- Filter `id_request_type = 9228` for Data & AI incident analysis — it is the Data Support & Services intake form.
- **Dedup `bug_issues` to the latest snapshot per `id_issue`** (`ROW_NUMBER() OVER (PARTITION BY id_issue ORDER BY ts_load DESC, ts_updated DESC) = 1`) before any count/aggregation — the served table holds multiple snapshots for some issues (see grain caveat).
- Deduplicate `line_name` per `id_line` (most frequent, earliest tie-break) before mapping to `incident_responsible`.
- Use `COALESCE(b.ts_sla_resolution_completed, b.ts_resolved)` as the resolution timestamp — the SLA completion ts is preferred, with `ts_resolved` as fallback.
- Keep the derived team column named **`incident_responsible`** so it aligns across summary datasets.
- Derive `is_created_by_data_ai_form` as `is_data_ai_team_bug OR is_data_ai_team_redirected` when you need "all bugs the Data & AI team ever owned".
- Use `status = 'Open'` for open-bug counts; use `is_resolved` / `is_closed` for closed-bug analysis.

**Don't:**
- Don't confuse the three ownership flags: `is_data_ai_team_bug` (currently owned) ≠ `is_data_ai_team_redirected` (moved away) ≠ created-by-form (either).
- Don't assume `line_name` is clean — the same line can appear under variant strings; dedup first.
- Don't map lines outside the table above — QCX, Cross Resources, For Living, and Classifieds currently resolve to NULL `incident_responsible` (BSG → Data Growth, Data & AI - Core Teams and blank line_name → Data Core are now mapped).
- Don't mix Jira bugs with Zendesk tickets — different systems, different grains, no join key.
- Don't read raw `datalake_jira_clean.issues` for analysis — it is JSON snapshots (multiple rows per issue); use the enriched `bug_issues` instead.
- Don't assume `bug_issues` is already one row per issue — it is not; dedup by `id_issue` yourself (validated: 265 rows for 233 issues on request type 9228).
- Don't use `QUALIFY` — it is Databricks/Spark syntax and **fails on Trino** (`SYNTAX_ERROR`). Use a `ROW_NUMBER()` subquery with `WHERE rn = 1` instead.
- Don't set `--user quinto-agent` (the script default) when running via `execute_trino.py` — your SSO identity cannot impersonate it; pass your own `--user <email>`.
- Don't count breached SLAs by string-guessing — use `is_sla_resolution_agreed` / `is_sla_first_response_agreed`, or the exact Portuguese labels above.

## Golden Queries

### Query 1 — Data & AI bugs with responsible team and dedup'd line name

Mirrors the canonical incident-summary query: dedup `bug_issues` to the latest snapshot per issue, dedup `line_name` per `id_line`, backfill line via name when id is missing, and map to `incident_responsible`. **Validated against production** (returns 233 rows = 233 distinct issues, no fan-out).

```sql
WITH bugs AS (
    -- Dedup bug_issues to the latest snapshot per issue. The served table holds
    -- more than one row for some issues (across ts_load); skipping this inflates
    -- every downstream count. Trino has no QUALIFY, so use a ROW_NUMBER subquery.
    SELECT * FROM (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY id_issue ORDER BY ts_load DESC, ts_updated DESC) AS rn_snap
        FROM datalake_jira_bugs.bug_issues
        WHERE id_request_type = 9228
    ) WHERE rn_snap = 1
),
line_freq AS (
    -- frequency of each (id_line, line_name) pair among Data & AI bugs.
    -- Source is the deduped `bugs` CTE — do NOT join datalake_jira_clean.issues
    -- here: that raw table keeps many snapshots per issue and would inflate counts.
    SELECT
        id_line,
        line_name,
        COUNT(*) AS qtd,
        MIN(ts_updated) AS first_seen
    FROM bugs
    WHERE id_line IS NOT NULL
        AND line_name IS NOT NULL
    GROUP BY id_line, line_name
),
line_name AS (
    -- canonical name per id_line (used to backfill line_name when b.line_name is NULL)
    SELECT id_line, line_name
    FROM (
        SELECT
            id_line,
            line_name,
            ROW_NUMBER() OVER (PARTITION BY id_line ORDER BY qtd DESC, first_seen ASC) AS rn
        FROM line_freq
    )
    WHERE rn = 1
),
line_id AS (
    -- canonical id_line per name: exactly ONE row per line_name, so the backfill join
    -- below cannot fan out even when several id_lines share the same name.
    SELECT line_name, id_line
    FROM (
        SELECT
            line_name,
            id_line,
            ROW_NUMBER() OVER (PARTITION BY line_name ORDER BY qtd DESC, first_seen ASC) AS rn
        FROM line_freq
    )
    WHERE rn = 1
)
SELECT
    COALESCE(b.id_line, ln2.id_line)      AS id_line,
    b.id_issue,
    COALESCE(b.line_name, ln.line_name)   AS line_name,
    CASE
        WHEN COALESCE(b.line_name, ln.line_name) = 'Partners (3P)'                        THEN 'Data 3P Partners'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Partners (Agents)'                    THEN 'Data Agents'
        WHEN COALESCE(b.line_name, ln.line_name) IN ('Single Station', 'Support & Services') THEN 'Data SS'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Conversational XP'                    THEN 'Data Conversational XP'
        WHEN COALESCE(b.line_name, ln.line_name) = 'For Rent'                             THEN 'Data For Rent'
        WHEN COALESCE(b.line_name, ln.line_name) = 'For Sale'                             THEN 'Data For Sale'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Primitives'                           THEN 'Data Primitives'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Tech Platform'                        THEN 'Tech Platform Dev Foundation'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Fintech'                              THEN 'Data Fintech'
        WHEN COALESCE(b.line_name, ln.line_name) = 'BSG'                                  THEN 'Data Growth'
        WHEN COALESCE(b.line_name, ln.line_name) = 'Data & AI - Core Teams'               THEN 'Data Core'
        WHEN COALESCE(b.line_name, ln.line_name) IS NULL                                  THEN 'Data Core'
        ELSE NULL
    END AS incident_responsible, -- keep this exact name across summary datasets
    b.assignee_name,
    b.creator_name,
    b.total_comments,
    b.total_attachments,
    b.sla_first_response_status,
    b.sla_resolution_status,
    b.is_data_ai_team_bug,
    b.is_data_ai_team_redirected,
    (b.is_data_ai_team_bug OR b.is_data_ai_team_redirected) AS is_created_by_data_ai_form,
    b.is_invalid_bug,
    b.status = 'Open' AS is_open_bug,
    b.is_resolved,
    b.is_closed,
    b.ts_created,
    COALESCE(b.ts_sla_resolution_completed, b.ts_resolved) AS ts_resolved,
    b.ts_updated
FROM bugs AS b
LEFT JOIN line_name AS ln  ON ln.id_line = b.id_line      -- backfill name from id_line
LEFT JOIN line_id   AS ln2 ON ln2.line_name = b.line_name -- backfill id_line from name (1:1, no fan-out)
```