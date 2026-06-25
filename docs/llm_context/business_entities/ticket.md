# Ticket

## Overview

A ticket is a customer support request tracked in Zendesk. It is the **central entity** of the Support & Services domain — virtually every S&S metric, dashboard, and operational workflow is anchored to a ticket.

Tickets are created through multiple channels:
- **Email** — customer sends an email; Zendesk creates the ticket directly
- **Call** — after a phone interaction (IVR / BigFone → Twilio), BigFone generates a Zendesk ticket
- **Chat (in-app or WhatsApp)** — after a chat interaction, QuintoMessenger generates a Zendesk ticket
- **Internal / API** — some tickets are created programmatically by internal systems

Each ticket has:
- **One or more analyst** — even if the service was transferred between agents, the ticket ID remains the same
- **One or more department/queue** — the team responsible for handling the ticket
- **Tags** — labels stamped on the ticket to classify routing, process, and SLA
- **Taxonomy** — a manually filled topic hierarchy (macro → micro) filled by the analyst

Tickets are split into two operational categories:
- **Front Office** — real-time interactions (calls and chats handled via Twilio). At the end of every Front Office interaction, a ticket is generated in Zendesk.
- **Back Office** — demands requiring longer analysis time (repairs, payments, operational processes). Handled asynchronously via Zendesk tickets.

## Related Metric Entities

- Journey PC

## Synonyms

- **Chamado**, **solicitação**, **demanda** → `ticket`
- **Ticket de suporte**, **ticket Zendesk** → `ticket`
- **Back-ticket** → a follow-up ticket linked to a previously resolved one, indicating unresolved issues or escalations
- **Taxonomia**, **classificação**, **tipificação** → `taxonomy`
- **Macro**, **macrotema** → taxonomy theme (top-level classification, column `theme` in `dim_taxonomy`)
- **Micro**, **microtema** → taxonomy theme detail (detailed classification, column `theme_detail` in `dim_taxonomy`)
- **Ticket rate**, **taxa do ticket** → weight assigned based on taxonomy and channel

## Tables

| You need... | Use this table |
|-------------|----------------|
| The central unified ticket entity for S&S analytics (links all channels, SLA, department, journey) | `dw_customer_support.fact_tickets` (`ft`) + `dim_ticket` (`dt`) |
| Raw ticket event log (every state change) | `dw_customer_support.fact_ticket_events` |
| Daily backlog snapshot per open ticket with SLA breach flag | `dw_customer_support.fact_tickets_backlog` |
| Enriched unified ticket (enrich layer — source for DW) | `datalake_customer_support.tickets` |
| Enriched Zendesk ticket with business context from custom fields | `datalake_zendesk.tickets_current` |
| Ticket SLA metrics (business and calendar minutes) | `datalake_zendesk.ticket_metrics` |
| Email-channel tickets with SLA and back-ticket linking | `datalake_customer_support.email` |
| Daily backlog age and SLA breach (enrich) | `datalake_customer_support.tickets_backlog` |
| Taxonomy dimension (theme/theme_detail classification, ticket rate) | `dw_customer_support.dim_taxonomy` (`dtx`) |
| SLA targets by taxonomy theme (with date ranges) | `datalake_customer_support.sla_theme` / `sla_theme_detail` (enrich) |
| SLA targets by journey | `datalake_customer_support.sla_journey` (enrich) |
| Taxonomy SLA targets from GSheets | `gsheets_clean.taxonomy_sla` |
| Tag-based SLA targets | `gsheets_clean.tag_sla_target` |

### Chatbot sessions and messages (enrich)

For **bot** behavior, session grain, and **messages** when the flow **starts** with a chatbot interaction, use the chatbot enrich schema — not the deprecated DW fact:

| Table | Role |
|-------|------|
| `datalake_chatbot.sessions` | All bot sessions; includes **all contacts that involve bot interaction** |
| `datalake_chatbot.messages` | All messages for sessions that **begin** with a chatbot interaction |

**Deprecated:** `dw_customer_support.fact_sessions_chatbot` — **do not use** for new analysis or dashboards. Join tickets to `datalake_chatbot.sessions` (and optionally `datalake_chatbot.messages`) on the appropriate session/ticket keys defined in those tables.

### Key columns in `fact_tickets`

| Column | Description |
|--------|-------------|
| `sk_ticket` | Surrogate key for the ticket |
| `sk_contract`, `sk_house` | Linked contract and house |
| `sk_first_analyst`, `sk_last_analyst` | First and last analyst who handled the ticket |
| `sk_first_department`, `sk_main_department` | First and main department the ticket was routed to |
| `sk_taxonomy` | Taxonomy classification |
| `sk_user` | Client id user who was attendent by the ticket |
| `channel` | Communication channel |
| `status` | Current ticket status |
| `front_or_back` | Whether the ticket is Front Office or Back Office |
| `csat_score`, `first_csat_score` | CSAT scores (last and first) |
| `ticket_rate_weight` | Ticket rate weight based on taxonomy/channel |
| `is_ticket_rate` | Whether this ticket counts for ticket rate |
| `ts_created`, `ts_closed` | Ticket creation and closure timestamps |
| `ts_sla_started` | When SLA clock started |
| `ts_load` | ETL load timestamp |

### Key columns in `dim_ticket`

| Column | Description |
|--------|-------------|
| `sk_ticket` | Surrogate key |
| `channel` | Channel (email, chat, call, whatsapp, etc.) |
| `status` | Status (new, open, pending, hold, solved, closed) |
| `priority` | Priority level |
| `tags` | Tags for routing and SLA classification |
| `subject`, `description` | Ticket subject and description |
| `group_name` | Zendesk group name |
| `ticket_via` | How the ticket was submitted |
| `score`, `reason`, `comment` | CSAT score, reason, and comment |

### Key columns in `dim_taxonomy`

| Column | Description |
|--------|-------------|
| `sk_taxonomy` | Surrogate key |
| `theme` | Theme (top-level topic, often called "macro") |
| `theme_detail` | Theme detail (specific sub-topic, often called "micro") |
| `journey` | Journey the taxonomy belongs to |
| `sub_journey` | Sub-journey |
| `request_type` | Request type classification |
| `motivation` | Motivation/reason classification |
| `customer_type` | Customer type |
| `step_tag`, `customer_type_tag` | Tag-based classifications |
| `line_owner` | Line owner |

### Grain and joins

- **`fact_tickets`**: 1 row per ticket
- **`fact_ticket_events`**: 1 row per ticket event
- **`fact_tickets_backlog`**: 1 row per ticket per day (while open)
- **Typical join**: `ft.sk_ticket = dt.sk_ticket` for descriptive attributes
- **Taxonomy join**: `ft.sk_taxonomy = dtx.sk_taxonomy` for topic classification

### How `datalake_customer_support.tickets` is built

This is the **central unified ticket entity** at the enrich layer and the primary input for `fact_tickets`. It:
- Links chat tasks (WT-prefix) and call tasks (CA-prefix) to tickets
- Resolves department/journey from GSheets `department_control`
- Applies SLA targets using a hierarchy: tag → theme → journey (with special 21-day offboarding queues)
- Computes business-day backlog excluding weekends and city holidays
- Derives contract from Greenseer session when missing from Zendesk
- Normalizes timestamps to UTC−3

## Taxonomy — Topic Classification

Taxonomy is the **topic classification system** applied to tickets. It consists of a manually filled hierarchy (theme → theme_detail) that analysts assign to each ticket they handle.

The taxonomy system works as follows:
1. An analyst resolves a ticket
2. The analyst selects the **theme** (high-level topic) and **theme_detail** (specific sub-topic)
3. The taxonomy classification is stamped on the ticket

Taxonomy has **direct impact** on two critical operational areas:
- **SLA targets** — SLA thresholds vary by taxonomy theme, and taxonomy feeds into the SLA resolution hierarchy (tag → theme → journey)
- **Ticket rate** — the weight assigned to a ticket for normalizing analyst performance metrics is determined by taxonomy and channel rules

### Taxonomy Governance

- The system governing taxonomy lifecycle (active/inactive) is called **Hogwarts** — it surfaces available taxonomy options to analysts within the ticket interface
- Taxonomies are created and defined in the **"Central Ops"** spreadsheet
- Active/inactive status changes in Hogwarts control which options are available to analysts

### How SLA tables are built

The materialized SLA target calendar is derived from the GSheets `taxonomy_sla` sheet:
- Explodes date ranges into daily SLA targets
- Computes minimum SLA per day where `dt_target_invalidated IS NULL`
- Used as join reference in `customer_support.tickets` and `tickets_backlog`

SLA resolution follows a hierarchy:
1. **Tag** — most specific: if a ticket has a tag with a defined SLA, use it
2. **Theme** — if no tag match, use the taxonomy theme–level SLA
3. **Journey** — if no theme match, fall back to the journey-level SLA

Special rules:
- Offboarding queues (e.g., "Offboarding Reparos") have a **21-day SLA** by default

## Key Metrics

- **Ticket volume** per month (by `ts_created` or `ts_closed`)
- **DSAT** — dissatisfaction rate (proportion of bad CSAT ratings). Metric in `metric_ss__tickets.dsat`
- **FCR** — First Contact Resolution rate. Metric in `metric_ss__tickets.fcr`
- **Recontact** — when a customer contacts support more than once for the same issue. Metric in `metric_ss__tickets.recontact`
- **Escalation** — rate of interactions escalated from chatbot to human. Metric in `metric_ss__tickets.escalation`
- **Backlog** — tickets that have exceeded their SLA target. Tracked daily in `fact_tickets_backlog`
- **SLA compliance** — percentage of tickets resolved within the SLA target
- **Ticket rate** — a weight assigned to tickets based on taxonomy and channel rules; used to normalize analyst performance metrics
- **Ticket volume by taxonomy** — how many tickets per theme/theme_detail
- **SLA compliance by taxonomy** — are certain topics consistently breaching SLA?
- **Ticket rate distribution** — how weights are distributed across taxonomy categories
- **Taxonomy coverage** — percentage of tickets with taxonomy filled vs blank
- **DSAT by taxonomy** — dissatisfaction rate per topic

## Relationships with Other Entities

### Contact (1:N — one ticket may be linked to multiple contacts)

A ticket may have associated calls and/or chats. In `fact_tickets`, contacts are linked via chat tasks (WT-prefix) and call tasks (CA-prefix). For contact-level detail, use `fact_customer_contacts`.

For **chatbot** paths (retention vs escalation, bot-side volume), use **`datalake_chatbot.sessions`** and **`datalake_chatbot.messages`** — not `dw_customer_support.fact_sessions_chatbot` (deprecated).

### Analyst (N:1 — many tickets to one analyst)

JOIN via `ft.sk_last_analyst` (or `ft.sk_first_analyst`) to `dw_customer_support.dim_analyst` (`da`) on `da.sk_analyst`. Ticket rate (from taxonomy) is used to weight tickets when computing normalized analyst performance metrics. An analyst handling complex topics (high ticket rate) gets more credit than one handling simple topics.

### Department (N:1 — many tickets to one department)

JOIN via `ft.sk_main_department` (or `ft.sk_first_department`) to `dw_customer_support.dim_department` (`dd`) on `dd.sk_department`. Different taxonomy topics can appear within the same department, and the same topic can appear across departments. Together, taxonomy and department drive SLA targets.

### Contract (N:1 — many tickets to one contract)

JOIN via `ft.sk_contract` to `dw_rent.dim_contract` (`dc`) when contract context is needed.

### CSAT (1:N — one ticket can have multiple CSAT scores)

A single ticket may receive more than one CSAT response. `fact_tickets` carries both `first_csat_score` (earliest response) and `last_csat_score` (most recent response) to cover this. For the full CSAT detail table, JOIN `ft.sk_ticket` to `dw_satisfaction_rating.fact_ticket_csat` on `id_ticket` (note: `fact_ticket_csat` uses `id_ticket`, not `sk_ticket`).

### Termination / Offboarding

Tickets linked to offboarding cases are identified by department/journey. See the Termination entity for offboarding-specific ticket analysis.

## Dos and Don'ts

**Do:**
- Start from `dw_customer_support.fact_tickets` for ticket-centric queries
- Use `sk_ticket` to join `fact_tickets` with `dim_ticket`
- Use `sk_main_department` (not `sk_department`) when joining to `dim_department`
- Use `sk_last_analyst` or `sk_first_analyst` (not `sk_analyst`) when joining to `dim_analyst`
- Filter by `dim_department` or `dim_taxonomy` when slicing by team or topic
- Use `fact_tickets_backlog` for daily SLA breach analysis — the flag is `is_backlog_within_sla`
- Use `metric_ss__tickets` for pre-aggregated KPIs (DSAT, FCR, recontact, escalation)
- Remember that SLA targets follow a hierarchy: tag → theme → journey
- Use `dim_taxonomy` as the primary taxonomy dimension — columns are `theme` and `theme_detail` (not `taxonomy_macro`/`taxonomy_micro`)
- Consider ticket rate when comparing analyst performance across different topic areas
- For chatbot-linked analysis, join to **`datalake_chatbot.sessions`** / **`datalake_chatbot.messages`** as needed

**Don't:**
- Don't confuse `ts_created` (when the ticket was created) with `ts_closed` (when it was resolved) — each answers a different question
- Don't forget that some tickets are created by bots or APIs
- Don't mix Front Office and Back Office tickets without filtering by channel/department — they have different operational characteristics
- Don't assume a ticket has a linked call or chat — email tickets have no contact entity
- Don't confuse ticket rate (weight for analyst performance) with ticket volume (count)
- Don't assume all tickets have taxonomy filled — some may have NULL taxonomy (analyst didn't classify)
- Don't confuse taxonomy (topic classification) with department (routing/queue) — they are orthogonal dimensions
- Don't ignore the Hogwarts system when asking about available taxonomy options — it governs which options are currently active
- Don't compute SLA targets manually — use the materialized `sla_theme` / `sla_journey` tables
- Don't forget that taxonomy has date-versioned SLA targets — a theme may have different SLA thresholds in different periods
- **Don't use `dw_customer_support.fact_sessions_chatbot`** — it is deprecated; use `datalake_chatbot.sessions` and `datalake_chatbot.messages` instead

## Golden Queries

### Query 1 — Base ticket pattern with descriptive attributes

Tickets with their descriptive attributes (status, channel, taxonomy, department).

```sql
SELECT
    ft.*,
    dt.*,
    dd.department,
    dd.journey_step,
    dtx.theme,
    dtx.theme_detail
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_ticket AS dt
    ON ft.sk_ticket = dt.sk_ticket
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN dw_customer_support.dim_taxonomy AS dtx
    ON ft.sk_taxonomy = dtx.sk_taxonomy
```

### Query 2 — Ticket volume with SLA compliance by journey

Monthly ticket volume and SLA compliance grouped by journey.

```sql
SELECT
    date_trunc('month', CAST(ft.ts_created AS TIMESTAMP)) AS month_created,
    dd.journey_step,
    COUNT(*) AS ticket_volume,
    SUM(CASE WHEN fb.is_backlog_within_sla THEN 1 ELSE 0 END) AS tickets_in_sla,
    CAST(SUM(CASE WHEN fb.is_backlog_within_sla THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS sla_compliance_rate
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN dw_customer_support.fact_tickets_backlog AS fb
    ON ft.sk_ticket = fb.sk_ticket
WHERE ft.ts_created >= DATE '2025-01-01'
GROUP BY 1, 2
```

### Query 3 — Ticket with CSAT and contact data

Tickets enriched with satisfaction score and linked contact information.

```sql
SELECT
    ft.sk_ticket,
    ft.sk_contract,
    ft.channel,
    fc.status,
    fcsat.first_csat_score,
    dd.department,
    dd.journey_step,
    fc.channel AS contact_channel,
    fc.status AS contact_status,
    ft.ts_created,
    ft.ts_closed
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN dw_customer_support.fact_customer_contacts AS fc
    ON ft.sk_ticket = fc.sk_ticket
LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS fcsat
  ON fcsat.sk_ticket = ft.sk_ticket
WHERE ft.ts_created >= DATE '2025-01-01'
```

### Query 4 — Ticket volume by taxonomy

Monthly ticket volume by theme and theme_detail.

```sql
SELECT
    date_trunc('month', CAST(ft.ts_created AS TIMESTAMP)) AS month_created,
    dtx.theme,
    dtx.theme_detail,
    COUNT(*) AS ticket_volume
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_taxonomy AS dtx
    ON ft.sk_taxonomy = dtx.sk_taxonomy
WHERE ft.ts_created >= DATE '2025-01-01'
GROUP BY 1, 2, 3
```

### Query 5 — DSAT by taxonomy

Dissatisfaction rate per taxonomy topic to identify pain points. Uses `csat_score` directly from `fact_tickets`.

```sql
SELECT
    dtx.theme,
    dtx.theme_detail,
    COUNT(*) AS total_rated,
    SUM(CASE WHEN fcsat.first_csat_score <= 2 THEN 1 ELSE 0 END) AS bad_ratings,
    CAST(SUM(CASE WHEN fcsat.first_csat_score <= 2 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS dsat_rate
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_taxonomy AS dtx
    ON ft.sk_taxonomy = dtx.sk_taxonomy
LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS fcsat
  ON fcsat.sk_ticket = ft.sk_ticket
WHERE ft.ts_created >= DATE '2025-01-01'
    AND dtx.theme IS NOT NULL
    AND fcsat.first_csat_score IS NOT NULL
GROUP BY 1, 2
```
