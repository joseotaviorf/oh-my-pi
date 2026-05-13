# Matthew

## Overview

Matthew is the **AI agent dedicated to tenants with open balances** — overdue invoices or invoices not yet due — helping them regularize their debts via direct payment, payment-method support, or full-debt negotiation (installments / discounts). It is the collections counterpart to QuintoAndar's general-purpose support bot Wall-E.

Matthew operates in **two environments**:

1. **WhatsApp** — Matthew runs as a standalone host (`bot = 'matthew'`).
2. **In-app chat** — Matthew runs as a sub-agent inside the Wall-E host (`bot = 'wall-e'` plus a Matthew-specific signal).

Conversations come from two flows:
- **Inbound** (in-app and WhatsApp) — the user organically reaches out to regularize a debt.
- **Outbound** (WhatsApp only) — QuintoAndar sends a debt-reminder notification; once the user replies, Matthew picks up the conversation. Detect via `is_notification_reply = 1` (presence of the `outbound_payload_from_dto` observation) and use `notif_text_extracted` / `notif_template_extracted` for notification content.

The Matthew session lifecycle:
1. **Session creation** — user opens a conversation through WhatsApp or in-app chat (`sessions.ts_created`).
2. **Matthew detection** — observation-based (`is_matthew_in_session`, derived from `flag_collectionsinput_agent`, `flag_debt_retriever_tool`, `flag_user_debt_classifier_tool`, `flag_debt_finder_tool`) or legacy score-based (`ai_agent_source_legacy`).
3. **Tools and helpers** — Matthew calls tools (debt retrieval, payment allegation, negotiation proposer, yearly invoices report) and helpers (debt summary, deal-renegotiation, non-tenant handling).
4. **Negotiation** — proposals sent (`send_proposal_count`) and confirmed (`confirm_negotiation_count`, `flag_create_negotiation`).
5. **Resolution or escalation** — the session ends, optionally escalating to human support (`is_escalation = TRUE`), with an LLM-declared reason in `matthew_declared_escalation_reason`.

Not all sessions reach negotiation. Many resolve via debt visualization, payment-method instructions, payment allegation verification, or yearly-invoice-report retrieval (Imposto de Renda).

## Glossary and Synonyms

- **Matthew** → the collections AI agent. In analytics, "Matthew was involved" means `ai_agent_source <> 'Wall-e'` (i.e. `'Matthew in Whatsapp'` or `'Matthew in Chat'`).
- **Matthew in Whatsapp** → Matthew running as a standalone WhatsApp host. Filter: `ai_agent_source = 'Matthew in Whatsapp'` (which is `bot = 'matthew'`).
- **Matthew in Chat** → Matthew running inside the Wall-E in-app host. Filter: `ai_agent_source = 'Matthew in Chat'` (which is `bot = 'wall-e'` + Matthew observation signal).
- **Wall-E** → general-purpose in-app support host. When Matthew triggers inside Wall-E, the row stays `bot = 'wall-e'` but `ai_agent_source` flips to `'Matthew in Chat'`.
- **Outbound / inbound** → outbound = QuintoAndar-initiated reminder (WhatsApp only); inbound = user-initiated. Outbound signal: `is_notification_reply = 1`.
- **Escalation / transbordo** → handoff to human support (`is_escalation = TRUE`). Reason declared by Matthew is in `matthew_declared_escalation_reason`.
- **Sessão com trace** → session that has at least one Langfuse trace recorded (`flag_session_with_trace = TRUE`). Sessions without trace exist only to track outbound send-offs and have no user interaction — **always exclude them from analysis**.
- **Acordo / negociação** → debt negotiation (installment or discount). Tracked by `flag_create_negotiation`, `confirm_negotiation_count`, `send_proposal_count`.
- **Boleto** → Brazilian invoice payment slip. Common conversation theme; filter via regex on `messages.full_conversation` (e.g. `LOWER(full_conversation) LIKE '%boleto%'`).
- **Imposto de Renda / IR report** → yearly paid-invoices report for tax declaration. Tool: `flag_get_yearly_paid_invoices_report_tool`.
- **Alegação de pagamento** → user claims to have paid an invoice; Matthew verifies it. Tool: `flag_payment_allegation_tool`.
- **CollectionsInput / V2** → canonical Matthew V2 entrypoint observation. Tool/flag: `flag_collectionsinput_agent`. `matthew_version = 'V2'`.
- **DebtRetrieverTool / UserDebtClassifierTool / V1.5** → Matthew V1.5 entrypoint. `matthew_version = 'V1.5'`.
- **DebtFinderTool / V1** → legacy V1 entrypoint. `matthew_version = 'V1'`.
- **id_external** → Langfuse session ID; the engineering team uses it to debug specific conversations. Always include it in analytical exports for traceability.

## Tables

| You need... | Use this table |
|-------------|----------------|
| One row per session with bot, channel-derived `ai_agent_source`, escalation, outbound flag, user roles, and trace presence | `datalake_ai_collections_quintoandar.sessions` (`s`) — merge key `id_sauron_session`. **Always filter `flag_session_with_trace = TRUE`**. |
| Deterministic milestones (negotiation steps, tools called, helpers, data errors, escalation reason) at session grain | `datalake_ai_collections_quintoandar.observation` (`o`) — one row per Langfuse session. JOIN via `o.id_langfuse_session = s.id_external`. |
| Full agglutinated conversation text per session for LLM analysis or regex theme filtering (e.g. `boleto`, `IR`) | `datalake_ai_collections_quintoandar.messages` (`m`) — one row per Matthew session. JOIN via `m.id_sauron_session = s.id_sauron_session`. Includes both `'Matthew in Whatsapp'` and `'Matthew in Chat'` only. |
| Pre-joined wide table: sessions + observations + messages + user wallet context (overdue, contracts, open invoices) at session date | `dw_collection_ai_agents.fact_ai_agents_interaction` (`f`) — analytical OBT. Already filters `flag_session_with_trace = TRUE`. |
| User wallet snapshot at any reference date (delay, overdue amount, active/ended contract counts) | `dw_collection_ai_agents.fact_user_wallet_timeline` (`fuwt`) — daily user-grain snapshot. Used to enrich Matthew sessions with delinquency context. |

**Critical rules:**
- **Mandatory filter**: `flag_session_with_trace = TRUE`. Sessions without trace are kept in `sessions` only to record outbound send-offs (no user reply yet) and contain no analysable interaction. Skip them in every analysis except outbound funnel volume.
- **`ai_agent_source` (observation-based) vs `ai_agent_source_legacy` (score-based)**: the **observation-based** `ai_agent_source` is the **correct, deterministic** view. Use it for current metrics. The score-based `ai_agent_source_legacy` is non-deterministic and suffers from incomplete eval coverage, but is the **only** way to reproduce historical escalation rate / volume metrics that pre-date the observation logic — use it explicitly for back-comparable trends.
- **`is_matthew_in_session` is observation-only and strictly narrower than `ai_agent_source`**: historical `bot = 'matthew'` (WhatsApp) sessions without recorded traces can have `ai_agent_source = 'Matthew in Whatsapp'` and `is_matthew_in_session = FALSE` simultaneously. For the canonical "Matthew was involved" question use `ai_agent_source <> 'Wall-e'`.
- **`messages` only includes Matthew sessions** (`ai_agent_source IN ('Matthew in Chat', 'Matthew in Whatsapp')` with trace) — do not assume it covers Wall-E-only sessions.
- **Always include `id_external`** (Langfuse session ID) in analytical exports; engineering uses it to drill into specific traces.

## Key Metrics

- **Session volume** — `COUNT(DISTINCT s.id_session)`, broken down by `ai_agent_source` and month of `dt_session_created`.
- **Escalation rate** (primary metric) — `COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) / COUNT(DISTINCT id_session)`. Indicates lack of capability or hard scenarios for Matthew.
- **Escalation volume** — `COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END)`. For trended back-comparable analyses, use `ai_agent_source_legacy`.
- **Outbound reply rate** — share of sessions where `is_notification_reply = 1`, scoped to WhatsApp.
- **Negotiation rate** — share of Matthew sessions with `flag_create_negotiation = 1` or `confirm_negotiation_count > 0`.
- **Proposal volume per session** — `AVG(send_proposal_count)` among Matthew sessions.
- **Tool-usage rate** — share of sessions hitting each tool (`flag_payment_allegation_tool`, `flag_get_yearly_paid_invoices_report_tool`, `flag_negotiation_proposer_tool`, ...).
- **Data-failure escalation rate (Pillar A)** — escalation rate among sessions with `flag_has_collections_data_error = 1 OR flag_handle_no_contracts = 1 OR flag_has_finance_fetch_error = 1`. Best deterministic proxy for escalations driven by data-acquisition failures.
- **In-domain coverage** — share of escalations where the conversation is genuinely within Matthew's scope (Pillars B and C) vs out-of-scope (NON_TENANT_PROFILE, CREDIT_GUARANTEE, CONTRACT_TERMINATION, REIMBURSEMENT_*, NON_RECURRING_FINANCE, SERVICE_BILLS, PROPERTY_OPERATIONS, CONTRACT_CHANGES). Requires LLM-based classification on `full_conversation`.

### Escalation analysis pillars

When investigating escalations, decompose hierarchically:

- **Pillar A — Data failures** (deterministic). Sessions where Matthew failed to fetch the user's collections context. Proxy: `flag_has_collections_data_error = 1 OR flag_handle_no_contracts = 1 OR flag_has_finance_fetch_error = 1`.
- **Pillar B — Out-of-scope themes** (no ready observation; needs LLM analysis on `full_conversation`). The user brings a problem Matthew is not designed to solve — see the out-of-scope categories list below.
- **Pillar C — Conversation-driven escalations** (no ready observation; needs LLM analysis). The conversation itself failed (misunderstanding, repeated loops, user dissatisfaction) despite the topic being in scope. `flag_handle_non_tenant`, `flag_original_invoice_values_disagreement_helper`, and `flag_ongoing_deal_renegotiation_request_helper` can hint at specific patterns but do not fully explain.

**Out-of-scope categories** (used by Pillar B classification on `full_conversation`):
`NON_TENANT_PROFILE`, `CREDIT_GUARANTEE`, `CONTRACT_TERMINATION`, `REIMBURSEMENT_QA`, `REIMBURSEMENT_CONDO`, `REIMBURSEMENT_REPAIRS`, `NON_RECURRING_FINANCE`, `SERVICE_BILLS`, `PROPERTY_OPERATIONS`, `CONTRACT_CHANGES`. Note: an ended contract whose user only wants to pay/negotiate the residual debt is **IN_DOMAIN**, not `CONTRACT_TERMINATION`.

## Relationships with Other Entities

### Chatbot Sessions (1:1 — Matthew sessions are a subset of chatbot sessions)

- `datalake_ai_collections_quintoandar.sessions` is built from `datalake_chatbot.sessions` filtered to `bot IN ('matthew', 'wall-e')`.
- For broader chatbot context (other bots: `sonia`, `isaias`, `concierge`, `vandinha`, `old bot`), see `business_entities/chatbot_sessions.md`.
- JOIN back: `datalake_ai_collections_quintoandar.sessions.id_sauron_session = datalake_chatbot.sessions.id_sauron_session`.

### Collections (N:1 — many Matthew sessions per contract / user)

- A user touched by Matthew typically has open invoices in `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`. The flag `has_matthew_interaction` on that timeline is the cross-reference.
- For deeper collections context (negotiations, deals, recovery channels, T1/T2/T3 delays, evictions), see `business_entities/collections.md`.

### User Wallet (1:1 at session date)

- `dw_collection_ai_agents.fact_ai_agents_interaction` already joins `fact_user_wallet_timeline` on `sk_user = id_user` and `dt_reference = dt_session_created`.
- For ad-hoc joins from `sessions`: `fuwt.sk_user = s.id_user AND fuwt.dt_reference = s.dt_session_created`.

### Support Tickets (1:1 — one ticket per escalated session)

- `s.id_ticket` populated when `is_escalation = TRUE`.
- JOIN to `datalake_customer_support.tickets.id_ticket` for SLA and queue routing context.

### Langfuse Traces / Observations (1:N — one session has many traces and observations)

- `datalake_langfuse_clean.traces.id_session = s.id_external`.
- `datalake_langfuse_clean.observations.id_trace = traces.id_trace`.
- `datalake_ai_collections_quintoandar.observation` already aggregates the relevant Matthew observations per session — prefer it over raw Langfuse tables for session-grain analysis.

## Dos and Don'ts

**Do:**
- Always filter `flag_session_with_trace = TRUE` (or `flag_session_with_trace` shorthand) on `datalake_ai_collections_quintoandar.sessions` before any analytical aggregation.
- Use `ai_agent_source` as the canonical agent attribution for current metrics; group by it (`'Matthew in Chat'`, `'Matthew in Whatsapp'`, `'Wall-e'`) instead of by `bot`.
- Use `ai_agent_source_legacy` only when reproducing historical escalation rate / volume series that pre-date the observation logic.
- Use `dw_collection_ai_agents.fact_ai_agents_interaction` as the default starting point for analytical questions — it already has user wallet context and full conversation joined.
- Include `id_external` (Langfuse session ID) in any analytical export so engineering can debug specific sessions.
- For outbound analyses (WhatsApp only), filter `is_notification_reply = 1` and use `notif_text_extracted` / `notif_template_extracted` to attribute the campaign.
- For thematic conversation breakdowns (e.g. boleto, IR, alegação), apply `LOWER(full_conversation) LIKE '%term%'` regex on `datalake_ai_collections_quintoandar.messages` or on the OBT.
- For Pillar A escalation analysis, combine the three data-failure flags with OR.

**Don't:**
- Don't analyse Matthew sessions on `bot = 'matthew'` alone — that excludes Matthew V2 running inside Wall-E (`'Matthew in Chat'`). Use `ai_agent_source <> 'Wall-e'` instead.
- Don't equate `is_matthew_in_session` with "Matthew was involved" in WhatsApp — historical `bot = 'matthew'` sessions without traces have `is_matthew_in_session = FALSE` despite Matthew being the host. Use `ai_agent_source <> 'Wall-e'` for the canonical question.
- Don't drop sessions with `flag_session_with_trace = FALSE` silently when measuring outbound send-off volume — those rows exist precisely to count send-offs without replies.
- Don't read column descriptions for any of the columns referenced here from this file alone; full column-level documentation lives in `metadata/enrich/sessions.yml`, `metadata/enrich/observation.yml`, `metadata/enrich/messages.yml` and `metadata/dw/fact_ai_agents_interaction.yml`.
- Don't use `matthew_version = 'V2'` as a filter for "Matthew was involved" — V2 is observation-derived only and excludes V1 / V1.5 / WhatsApp-without-traces sessions.
- Don't assume `messages.full_conversation` is available for Wall-E-only sessions — `messages` is filtered to `ai_agent_source IN ('Matthew in Chat', 'Matthew in Whatsapp')` only.
- Don't try to explain Pillars B and C from observations alone — they require LLM analysis on `full_conversation` against the out-of-scope category list.

## Golden Queries

### Query 1 — Escalation rate by month and agent source (current, observation-based)

Reproduces the canonical Matthew escalation-rate metric. Always filter `flag_session_with_trace`.

```sql
SELECT
    DATE(date_trunc('month', dt_session_created)) AS month_session,
    ai_agent_source,
    COUNT(DISTINCT id_session) AS n_sessions,
    COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) AS n_escalated_sessions,
    CAST(COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_session), 0) AS escalation_rate
FROM datalake_ai_collections_quintoandar.sessions
WHERE flag_session_with_trace
  AND dt_session_created >= DATE '{start_date}'
  AND dt_session_created < DATE '{end_date}'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 2 — Pillar A escalation breakdown (data-failure proxy)

Splits escalations into Pillar A (data failures, deterministic) vs the rest (Pillars B + C, requiring LLM follow-up). Includes `id_external` for engineering drill-down.

```sql
SELECT
    DATE(date_trunc('month', dt_session_created)) AS month_session,
    ai_agent_source,
    COUNT(DISTINCT id_session) AS n_sessions,
    COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) AS n_escalated,
    COUNT(DISTINCT CASE
        WHEN is_escalation
         AND (flag_has_collections_data_error = 1
              OR flag_handle_no_contracts = 1
              OR flag_has_finance_fetch_error = 1)
        THEN id_session
    END) AS n_escalated_pillar_a,
    COUNT(DISTINCT CASE
        WHEN is_escalation
         AND NOT (flag_has_collections_data_error = 1
                  OR flag_handle_no_contracts = 1
                  OR flag_has_finance_fetch_error = 1)
        THEN id_session
    END) AS n_escalated_pillar_b_or_c
FROM dw_collection_ai_agents.fact_ai_agents_interaction
WHERE dt_session_created >= DATE '{start_date}'
  AND dt_session_created < DATE '{end_date}'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 3 — Outbound (WhatsApp) reply funnel by notification template

Outbound is WhatsApp-only; `is_notification_reply = 1` marks sessions that started as a reply to a Matthew-driven reminder.

```sql
SELECT
    DATE(date_trunc('month', dt_session_created)) AS month_session,
    notif_template_extracted,
    COUNT(DISTINCT id_session) AS n_sessions,
    COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) AS n_escalated,
    COUNT(DISTINCT CASE WHEN flag_create_negotiation = 1 THEN id_session END) AS n_with_negotiation
FROM dw_collection_ai_agents.fact_ai_agents_interaction
WHERE ai_agent_source = 'Matthew in Whatsapp'
  AND is_notification_reply = 1
  AND dt_session_created >= DATE '{start_date}'
  AND dt_session_created < DATE '{end_date}'
GROUP BY 1, 2
ORDER BY 1 DESC, n_sessions DESC
```

### Query 4 — Sample sessions for LLM analysis (Pillars B and C)

Pulls escalated sessions without a Pillar A signal, with the full conversation, ready to feed into an LLM classifier against the out-of-scope category list. `id_external` is included so engineering can locate the trace in Langfuse.

```sql
SELECT
    f.id_session,
    f.id_sauron_session,
    f.id_external,
    f.ai_agent_source,
    f.dt_session_created,
    f.user_wallet_overdue_t2,
    f.flag_user_delay,
    f.matthew_declared_escalation_reason,
    f.full_conversation
FROM dw_collection_ai_agents.fact_ai_agents_interaction AS f
WHERE f.is_escalation
  AND f.flag_has_collections_data_error = 0
  AND f.flag_handle_no_contracts = 0
  AND f.flag_has_finance_fetch_error = 0
  AND f.dt_session_created >= DATE '{start_date}'
  AND f.dt_session_created < DATE '{end_date}'
ORDER BY f.dt_session_created DESC
LIMIT 200
```
