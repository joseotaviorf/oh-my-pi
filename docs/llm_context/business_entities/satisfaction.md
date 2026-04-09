# Satisfaction (CSAT)

## Overview

Satisfaction represents the **Customer Satisfaction (CSAT)** measurement across all contact channels in the Support & Services domain. CSAT data is collected from four independent sources and unified into a single table for cross-channel analysis.

The four CSAT sources are:

| Source | Channel | How it's collected |
|--------|---------|-------------------|
| **Zendesk** | Email, ticket-based | CSAT JSON embedded in ticket data |
| **Survicate** | In-app, email | Post-interaction surveys (inspections, repairs, lockbox, scheduling, keys, photo, Salesforce, Zendesk email) |
| **BigFone** | Call (IVR) | CSAT steps collected during/after calls (3 branches with different score semantics) |
| **Chat FUP** | Chat | Post-chat follow-up ratings and survey answers |

Additionally, manual CSAT data is collected from Google Sheets for inspection and onboarding surveys.

All sources are normalized to a common scale and unified in the enrich layer, then promoted to the DW layer as fact and dimension tables.

## Synonyms

- **CSAT**, **satisfação**, **nota de satisfação** → `satisfaction` / `csat`
- **Pesquisa de satisfação** → satisfaction survey
- **DSAT** → dissatisfaction rate (proportion of bad CSAT ratings)
- **Avaliação** → rating/evaluation

## Tables

| You need... | Use this table |
|-------------|----------------|
| All satisfaction answers from all channels (single source of truth) | `dw_satisfaction_rating.fact_answer` |
| Unified ticket-level CSAT score (first and last) | `dw_satisfaction_rating.fact_ticket_csat` |
| Single-station analyst survey answers | `dw_satisfaction_rating.fact_analyst_answers` |
| Survey dimension (definitions, metadata) | `dw_satisfaction_rating.dim_survey` |
| Answer dimension (classification attributes) | `dw_satisfaction_rating.dim_answer` |
| Pre-aggregated DSAT metric | `metric_ss__tickets.dsat` |

### Key columns in `fact_answer`

| Column | Description |
|--------|-------------|
| `sk_answer` | Surrogate key |
| `sk_survey` | Survey the answer belongs to |
| `sk_contract`, `sk_ticket`, `sk_case` | Linked to business entities |
| `sk_user`, `sk_account`, `sk_origin` | User, account, and origin identifiers |
| `satisfaction_score` | Primary satisfaction score |
| `secondary_satisfaction_score` | Secondary score (when applicable) |
| `ts_submitted` | When the answer was submitted |

### Key columns in `fact_ticket_csat`

| Column | Description |
|--------|-------------|
| `id_ticket` | Ticket identifier (note: equal to `sk_ticket`) |
| `first_csat_score` | First CSAT score for the ticket |
| `last_csat_score` | Last/most recent CSAT score |
| `first_csat_comment`, `last_csat_comment` | Comments associated with scores |
| `is_answered`, `is_solved` | Flags |
| `ts_first_response`, `ts_last_response` | Response timestamps |

### Key columns in `fact_analyst_answers`

| Column | Description |
|--------|-------------|
| `sk_answer`, `sk_analyst`, `sk_survey` | Surrogate keys |
| `facility_satisfaction` | Analyst satisfaction rating regarding the ease of performing tasks on the Single Station platform |
| `time_satisfaction` | Analyst's satisfaction score of the time spent performing tasks on the Single Station platform |
| `support_satisfaction` | Analyst satisfaction rating regarding support and documentation for performing tasks on the Single Station platform |
| `improvements_suggestions` | Free-text suggestions |
| `ts_submitted` | When answer was submitted |
| `week_month` | Week/month reference |

### Key columns in `dim_survey`

| Column | Description |
|--------|-------------|
| `sk_survey` | Surrogate key |
| `service_type`, `service_context` | Service classification |
| `source_name` | Data source name |
| `survey_name` | Human-readable survey name |

### Key columns in `dim_answer`

| Column | Description |
|--------|-------------|
| `sk_answer` | Surrogate key |
| `respondent_type` | Type of respondent |
| `improvement_tags` | Tags for improvement areas |
| `respondent_comments` | Free-text comments |
| `score_description` | Description of the primary score |
| `secondary_score_description` | Description of secondary score |

### Per-channel survey tables (enrich layer)

These pre-union tables exist in `datalake_satisfaction_rating`, one per source channel:

| Table | Source |
|-------|--------|
| `zendesk_surveys` | Zendesk satisfaction_ratings + tickets_current |
| `survicate_surveys` | All Survicate survey types |
| `bigfone_surveys` | BigFone call CSAT events (3 branches) |
| `chat_fup_surveys` | Chat FUP ratings and survey answers |
| `gsheets_surveys` | Manual inspection/onboarding CSAT from Google Sheets |

### How `datalake_customer_support.csat` is built

Unified ticket-level CSAT from all channels:
- Merges four CSAT sources (Zendesk, Survicate, BigFone, Chat FUP)
- Normalizes good/bad → 1/5 score
- Keeps first and last score per ticket with comments
- One row per ticket

### How `datalake_satisfaction_rating.satisfaction_answers` is built

Master union of all per-channel survey tables:
- Stacks all per-channel tables (`zendesk_surveys`, `survicate_surveys`, `bigfone_surveys`, `chat_fup_surveys`, `gsheets_surveys`)
- Enriches `id_respondent` and email from the user registry by email or ID match

## Key Metrics

- **CSAT score** — satisfaction score per ticket or per survey answer
- **DSAT (Dissatisfaction Rate)** — proportion of bad CSAT ratings. Pre-aggregated in `metric_ss__tickets.dsat`
- **CSAT by channel** — satisfaction broken down by contact channel
- **CSAT by journey/department** — satisfaction by operational journey
- **Analyst CSAT** — per-analyst satisfaction from `fact_analyst_answers` (covers facility, time, and support dimensions)

## Relationships with Other Entities

### Ticket (N:1 — many satisfaction answers may link to one ticket)

`fact_ticket_csat` provides a 1:1 ticket-to-CSAT mapping. JOIN via `id_ticket` (equal as `sk_ticket`) to `dw_customer_support.fact_tickets.sk_ticket`.

### Analyst (N:1 — satisfaction linked to the handling analyst)

`fact_analyst_answers` provides analyst-level satisfaction. JOIN via `sk_analyst` to `dim_analyst`.

### Contract (N:1 — satisfaction may be linked to a contract)

`fact_answer` has a `sk_contract` surrogate key for contract context.

### Survey (N:1 — many answers to one survey definition)

JOIN via `sk_survey` to `dim_survey` for survey metadata and classification.

## Dos and Don'ts

**Do:**
- Use `dw_satisfaction_rating.fact_answer` for cross-channel satisfaction analysis (single source of truth)
- Use `dw_satisfaction_rating.fact_ticket_csat` when you need ticket-level CSAT — join on `id_ticket` (or `sk_ticket`)
- Use `metric_ss__tickets.dsat` for the pre-aggregated DSAT metric
- Remember that BigFone has 3 different branches with different score semantics — the enrich layer normalizes them
- Use `fact_tickets.csat_score` when you only need CSAT as a ticket attribute without joining `fact_ticket_csat`

**Don't:**
- Don't query individual per-channel survey tables (`zendesk_surveys`, `bigfone_surveys`, etc.) when unified analysis is needed — use `satisfaction_answers` or `fact_answer`
- Don't compare raw scores across channels without normalization — each source uses different scales
- Don't confuse CSAT (per-ticket/per-interaction satisfaction) with NPS (overall brand loyalty measured via Tracksale) — they are separate entities in separate DW schemas
- Don't confuse `id_ticket` (in `fact_ticket_csat`) with `sk_ticket` (in `fact_tickets`) — they refer to the same ticket but have different column names

## Golden Queries

### Query 1 — Ticket-level CSAT with department context

CSAT per ticket with department and journey context. 

```sql
SELECT
    ft.sk_ticket,
    ft.sk_contract,
    dd.department,
    dd.journey_step,
    csat.first_csat_score,
    csat.last_csat_score,
    csat.last_csat_comment,
    ft.ts_created,
    ft.ts_closed
FROM dw_customer_support.fact_tickets AS ft
INNER JOIN dw_satisfaction_rating.fact_ticket_csat AS csat
    ON ft.sk_ticket = csat.sk_ticket
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
WHERE ft.ts_created >= DATE '2025-01-01'
```

### Query 2 — CSAT distribution by survey source

Satisfaction distribution across all survey sources from the unified answer table.

```sql
SELECT
    ds.source_name,
    ds.survey_name,
    COUNT(*) AS total_answers,
    AVG(fa.satisfaction_score) AS avg_score,
    SUM(CASE WHEN fa.satisfaction_score <= 2 THEN 1 ELSE 0 END) AS bad_ratings,
    CAST(SUM(CASE WHEN fa.satisfaction_score <= 2 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS dsat_rate
FROM dw_satisfaction_rating.fact_answer AS fa
LEFT JOIN dw_satisfaction_rating.dim_survey AS ds
    ON fa.sk_survey = ds.sk_survey
WHERE fa.ts_submitted >= DATE '2025-01-01'
GROUP BY 1, 2
ORDER BY total_answers DESC
```

### Query 3 — Analyst satisfaction survey results

Per-analyst satisfaction scores across facility, time, and support dimensions in Single Station.

```sql
SELECT
    da.email,
    da.agent_organization,
    COUNT(*) AS total_surveys,
    AVG(faa.facility_satisfaction) AS avg_facility,
    AVG(faa.time_satisfaction) AS avg_time,
    AVG(faa.support_satisfaction) AS avg_support
FROM dw_satisfaction_rating.fact_analyst_answers AS faa
LEFT JOIN dw_customer_support.dim_analyst AS da
    ON faa.sk_analyst = da.sk_analyst
WHERE faa.ts_submitted >= DATE '2025-01-01'
GROUP BY 1, 2
ORDER BY total_surveys DESC
```
