# Matthew

## Ownership

**Data Owner:**
- thiago.villani@quintoandar.com.br

**Data Steward:**
- thiago.villani@quintoandar.com.br

## Overview

Matthew is the **AI agent dedicated to tenants with open balances** — overdue invoices or invoices not yet due — helping them regularize their debts via direct payment, payment-method support, or full-debt negotiation (installments / discounts). It is the collections counterpart to QuintoAndar's general-purpose support bot Wall-E.

Matthew operates in **two environments**:

1. **WhatsApp** — Matthew runs as a standalone host (`bot = 'matthew'`).
2. **In-app chat** — Matthew runs as a sub-agent inside the Wall-E host (`bot = 'wall-e'` plus a Matthew-specific signal).

Conversations come from two flows:
- **Inbound** (in-app and WhatsApp) — the user organically reaches out to regularize a debt.
- **Outbound** (WhatsApp only) — QuintoAndar sends a debt-reminder notification; once the user replies, Matthew picks up the conversation. Detect via `is_notification_reply = 1` (presence of the `outbound_payload_from_dto` observation) and use `notif_text_extracted` / `notif_template_extracted` for notification content.

### Agent generations and model versions

Matthew has two internal architectures and multiple tracked versions with **unified analytics**:

- **V2** — LangChain graph agent. Observability comes from Langfuse graph-node observations, aggregated per session in `datalake_ai_collections_quintoandar.observation`.
- **V3** — single agent calling **MCP tools** (backend-for-bots services such as `get_financial_context_v1`, `simulate_negotiation_v1`, `create_negotiation_v1`). Observability comes from MCP tool request logs, aggregated per session in `datalake_ai_collections_quintoandar.matthew_mcp_observations`.
- **V4** — same architecture, tools, and analytical signals as V3, with the LLM changed to **GPT-5.4 mini** for model testing. Its entrypoint observation is `collectionsagentv4input`.

Historical rollout timeline: the **V2-vs-V3 A/B test started on 2026-05-15**; on **2026-05-25 V3 went to 100%** of the user base. V2 rows are kept for history. V4 is a model-only successor to V3, so V3 and later versions share the MCP-backed analytical behavior described below.

Identify the version with `matthew_version` (`'V4'`, `'V3'`, `'V2'`, `'V1.5'`, `'V1'`, future numeric versions, or NULL). Versioned entrypoints matching `collectionsagentv<number>input` are detected dynamically; the historical rollout name `collectionsagentv1input` maps to V3.

**Model (LLM) vs version (architecture).** `matthew_version` is the *agent architecture* generation (V2 graph, V3/V4 MCP). `matthew_model` (in `fact_ai_agents_interaction`) is the *underlying LLM* the collections agent calls (e.g. `openai/gpt-4o-2024-11-20`, `openai/gpt-5.4-mini-2026-03-17`) — there is one model per session. The collections-agent planner (ReactPlanner) is the only place Matthew calls an LLM, so `matthew_model` is "the Matthew model". Use `matthew_model` — not `matthew_version` — as the dimension for **cost / latency / LLM-efficiency model comparisons** (e.g. gpt-4o vs gpt-5.4-mini). These figures live in `fact_ai_agents_interaction` as **additive counters** (`n_agent_messages`, `n_llm_calls`, `total_llm_cost`, `total_collections_agent_cost`, `total_message_latency_sum`, `collections_agent_latency_sum`, `collections_agent_llm_latency_sum`, `flag_session_had_timeout`), sourced from `datalake_ai_collections_quintoandar.matthew_llm_metrics`.

In `dw_collection_ai_agents.fact_ai_agents_interaction`, the **business-signal columns are unified across generations**: each unified column is populated with the V3-or-later MCP value when the session has MCP activity and falls back to the V2 observation value otherwise — so metrics like negotiation rate or proposal count can be computed with a single column regardless of version.

The Matthew session lifecycle:
1. **Session creation** — user opens a conversation through WhatsApp or in-app chat (`sessions.ts_created`).
2. **Matthew detection** — observation-based (`is_matthew_in_session`, `matthew_version`) or legacy score-based (`ai_agent_source_legacy`). `matthew_version` can be NULL even when Matthew was involved: when Matthew is the WhatsApp host (`bot = 'matthew'`) and answers the user directly from the host prompt and FAQ without ever calling the collections agent, no version signal is recorded. Use `matthew_version` as a filter for version-specific analysis, but be aware that for overall Matthew analysis filtering on it drops these host-only-handled sessions — use `ai_agent_source <> 'Wall-e'` for the canonical "Matthew was involved" question.
3. **Financial-context fetch** — the agent retrieves the user's contracts and debts (`flag_fetch_financial_data`, with failures in `flag_fetch_financial_data_error`).
4. **Negotiation** — proposals sent (`send_proposal_count`), confirmed by the user (`confirm_negotiation_count`) and deals created (`flag_create_negotiation`).
5. **Resolution or escalation** — the session ends, optionally escalating to human support (`is_escalation = TRUE`), with an LLM-declared reason in `matthew_declared_escalation_reason`.

Not all sessions reach negotiation. Many resolve via debt visualization, payment-method instructions, payment allegation verification, or yearly-invoice-report retrieval (Imposto de Renda).

## Glossary and Synonyms

- **Matthew** → the collections AI agent. In analytics, "Matthew was involved" means `ai_agent_source <> 'Wall-e'` (i.e. `'Matthew in Whatsapp'` or `'Matthew in Chat'`).
- **Matthew in Whatsapp** → Matthew running as a standalone WhatsApp host. Filter: `ai_agent_source = 'Matthew in Whatsapp'` (which is `bot = 'matthew'`).
- **Matthew in Chat** → Matthew running inside the Wall-E in-app host. Filter: `ai_agent_source = 'Matthew in Chat'` (which is `bot = 'wall-e'` + Matthew observation signal).
- **Wall-E** → general-purpose in-app support host. When Matthew triggers inside Wall-E, the row stays `bot = 'wall-e'` but `ai_agent_source` flips to `'Matthew in Chat'`.
- **Outbound / inbound** → outbound = QuintoAndar-initiated reminder (WhatsApp only); inbound = user-initiated. Outbound signal: `is_notification_reply = 1`.
- **Escalation / transbordo** → handoff to human support (`is_escalation = TRUE`). Reason declared by Matthew is in `matthew_declared_escalation_reason`; `flag_escalation_attempted` marks that Matthew invoked the escalation tool.
- **Sessão com trace** → session that has at least one Langfuse trace recorded (`flag_session_with_trace = TRUE`). Sessions without trace exist only to track outbound send-offs and have no user interaction — **always exclude them from analysis**.
- **Acordo / negociação** → debt negotiation (installment or discount). Tracked by the unified columns `send_proposal_count` (proposals shown), `confirm_negotiation_count` (user confirmations) and `flag_create_negotiation` (deal actually created — the main success outcome). For V3-or-later sessions, the closed deal's details are in `created_negotiation_option_key` and `created_negotiation_payment_method`.
- **Matthew talked to the user / falou com o usuário** → Matthew actually spoke to the user in the session (rather than only running tools internally). Flag: `flag_matthew_talked_to_user = 1` in `sessions` / `fact_ai_agents_interaction`, **unified across all Matthew agent versions**. Always true when Matthew is the WhatsApp host (`ai_agent_source = 'Matthew in Whatsapp'`), since the host talks to the user directly; when Matthew runs inside Wall-E (`'Matthew in Chat'`), true only when the collections agent relayed a message to the user.
- **MCP tools** → backend-for-bots services the V3-or-later agent calls: `get_financial_context_v1` (contracts + debts), `get_debt_breakdown_v1`, `get_negotiation_options_v1`, `simulate_negotiation_v1` (proposal simulation), `create_negotiation_v1` (deal creation), `get_ongoing_negotiation_information_v1`, `get_annual_tax_report_v1` / `get_paid_invoices_annual_report_v1` (IR report), `get_last_paid_invoices_v1`, `get_original_invoices_by_status_v1`.
- **Boleto** → Brazilian invoice payment slip. Common conversation theme; filter via regex on `messages.full_conversation` (e.g. `LOWER(full_conversation) LIKE '%boleto%'`).
- **Imposto de Renda / IR report** → yearly paid-invoices report for tax declaration. Unified flag: `flag_get_yearly_paid_invoices_report_tool` (V2 graph tool or V3+ MCP annual-tax-report tools). This feature has a known failure mode, the **"prorated rent error"**: when the user's payment history has specific rental payments the current tool does not cover, it cannot produce a clean report. Visible in `flag_has_prorated_rent` (sourced from `observation.has_prorated_rent_error`).
- **Alegação de pagamento** → user claims to have paid an invoice; Matthew verifies it. **V2-only signal** — `flag_payment_allegation_tool` lives in `datalake_ai_collections_quintoandar.observation`, not in the fact table; V3 and later versions have no deterministic equivalent.
- **Segmento (customer segment)** → ChargeHub segment guiding the collection approach (e.g. EVICTIONS). V3-or-later column `user_segment` in the fact table.
- **CollectionsAgentV4Input / V4** → Matthew V4 entrypoint observation (`collectionsagentv4input`). Same MCP behavior as V3, using GPT-5.4 mini for the model test; `matthew_version = 'V4'`.
- **CollectionsAgentV3Input / V3** → Matthew V3 entrypoint observation (`collectionsagentv3input`). The historical `collectionsagentv1input` rollout name also maps to `matthew_version = 'V3'`.
- **Versioned collections-agent input** → any observation matching `collectionsagentv<number>input`. `observation.flag_collections_agent_input` detects V2 and all versioned inputs; `observation.collections_agent_version` stores the highest detected numeric V3+ version for the session.
- **CollectionsInput / V2** → Matthew V2 entrypoint observation. `matthew_version = 'V2'`.
- **DebtRetrieverTool / UserDebtClassifierTool / V1.5** → Matthew V1.5 entrypoint. `matthew_version = 'V1.5'`.
- **DebtFinderTool / V1** → legacy V1 entrypoint. `matthew_version = 'V1'`.
- **id_external** → Langfuse session ID; the engineering team uses it to debug specific conversations. Always include it in analytical exports for traceability.
- **matthew_model (the LLM / "the Matthew model")** → the underlying LLM the collections agent calls (e.g. `openai/gpt-4o-2024-11-20`, `openai/gpt-5.4-mini-2026-03-17`). One per session; column `matthew_model` in `fact_ai_agents_interaction`. This is the comparison dimension for cost/latency/efficiency — **not** `matthew_version` (that is the agent architecture generation V2/V3/V4).
- **LLM call / planner call** → one collections-agent LLM invocation (a `CollectionsAgentV<N> - ReactPlanner` planner step, which drives exactly one LLM generation). Counted per session by `n_llm_calls`. "LLM calls" and "planner calls" are the same thing.
- **Agent message** → a message/turn (Langfuse trace) in which the collections agent called the LLM at least once. Counted per session by `n_agent_messages`. This is the denominator for "per message" metrics.
- **Collections-agent cost** → USD cost of the collections-agent LLM calls only (`total_collections_agent_cost`), excluding host-side moderator + answer-processor LLM cost. `total_llm_cost` is the all-in session LLM cost (agent + host-side).
- **Timeout** → a message whose collections-agent-input observation was recorded with `level = 'ERROR'` (the agent exceeded its time budget, ~90s). Session flag: `flag_session_had_timeout = 1`.

## Tables

| You need... | Use this table |
|-------------|----------------|
| One row per session with bot, channel-derived `ai_agent_source`, `matthew_version`, escalation, outbound flag, user roles, and trace presence | `datalake_ai_collections_quintoandar.sessions` (`s`) — merge key `id_sauron_session`. **Always filter `flag_session_with_trace = TRUE`**. |
| Pre-joined wide table: sessions + V2/V3+-unified business signals + V3+-only MCP signals + messages + user wallet context and 2-day post-session recovery | `dw_collection_ai_agents.fact_ai_agents_interaction` (`f`) — analytical OBT, **default starting point**. Already filters `flag_session_with_trace = TRUE`. |
| Granular V2 milestones plus versioned-input and ReactPlanner detection at session grain | `datalake_ai_collections_quintoandar.observation` (`o`) — one row per Langfuse session. JOIN via `o.id_langfuse_session = s.id_external`; use `flag_collections_agent_input` and `collections_agent_version` for generic version detection. |
| Granular V3+ MCP activity (per-tool call/error counts like `n_financial_context_calls`, `n_create_negotiation_errors`, contract-level negotiation breakdowns) at session grain | `datalake_ai_collections_quintoandar.matthew_mcp_observations` (`mo`) — one row per Langfuse session with MCP activity. JOIN via `mo.id_langfuse_session = s.id_external`. |
| Per-session LLM model, cost, latency and call-volume counters (for comparing Matthew across LLM models) | `datalake_ai_collections_quintoandar.matthew_llm_metrics` (`llm`) — one row per Langfuse session. Already joined into `fact_ai_agents_interaction` (columns `matthew_model`, `n_agent_messages`, `n_llm_calls`, `total_llm_cost`, `total_collections_agent_cost`, `total_message_latency_sum`, `collections_agent_latency_sum`, `collections_agent_llm_latency_sum`, `flag_session_had_timeout`) — **prefer the fact**. JOIN standalone via `llm.id_langfuse_session = s.id_external`. |
| Individual V3+ MCP tool requests and their downstream service calls (debugging grain) | `datalake_ai_collections_quintoandar.mcp_tool_logs` — one row per downstream service call inside an MCP tool request. Engineering-oriented; prefer the session-grain tables for analytics. |
| Full agglutinated conversation text per session for LLM analysis or regex theme filtering (e.g. `boleto`, `IR`) | `datalake_ai_collections_quintoandar.messages` (`m`) — one row per Matthew session. JOIN via `m.id_sauron_session = s.id_sauron_session`. Includes both `'Matthew in Whatsapp'` and `'Matthew in Chat'` only. |
| User wallet snapshot at any reference date (delay, overdue amount, active/ended contract counts) | `dw_collection_ai_agents.fact_user_wallet_timeline` (`fuwt`) — daily user-grain snapshot. Used to enrich Matthew sessions with delinquency context. |

**Critical rules:**
- **Mandatory filter**: `flag_session_with_trace = TRUE`. Sessions without trace are kept in `sessions` only to record outbound send-offs (no user reply yet) and contain no analysable interaction. Skip them in every analysis except outbound funnel volume.
- **Unified vs V3+-only vs granular columns in the fact table**:
  - **Unified columns** work for every session regardless of version (V3+ MCP value when the session has MCP activity, V2 observation value otherwise): `send_proposal_count`, `confirm_negotiation_count`, `flag_create_negotiation`, `handle_negotiation_cancelled_count`, `flag_handle_segments_without_proposals`, `flag_fetch_financial_data`, `flag_fetch_financial_data_error`, `flag_has_fetch_contracts`, `flag_handle_no_contracts`, `flag_get_yearly_paid_invoices_report_tool`, `flag_negotiation_proposer_tool`, `flag_ongoing_deal_renegotiation_request_helper`, `flag_handle_non_tenant`, `flag_has_prorated_rent`. Use these by default.
  - **`flag_matthew_talked_to_user`** is a 0/1 flag (never NULL), unified across all generations: 1 when Matthew actually spoke to the user, else 0. `bot = 'matthew'` (WhatsApp host) always counts; `bot = 'wall-e'` counts only when `is_matthew_in_session` AND the collections agent relayed a message (V3+ `TalkToUserTool` or legacy V2 `CollectionsInput` `RESPOND EXACTLY`). Because the WhatsApp-host branch is version-agnostic and V1/V1.5 exist only there, do not read a `0` as "no Matthew" — pair it with `ai_agent_source` / `matthew_version` for version splits.
  - **V3+-only columns** are NULL for V2 sessions: `n_contracts_mcp`, `flag_all_empty_invoices_mcp`, `user_segment`, `negotiation_options_list`, `created_negotiation_option_key`, `created_negotiation_payment_method`, `flag_negotiation_created_missing_payment_info`, `ts_first_mcp_call`, `ts_last_mcp_call`. Never use them to compare V2 with V3+ — V2 will look like zero/NULL by construction.
  - **Granular signals** live in the source tables: per-tool V2 flags (e.g. `flag_payment_allegation_tool`, `flag_debt_retriever_tool`) in `observation`; per-tool V3+ call/error counts (e.g. `n_financial_context_calls`, `n_create_negotiation_errors`) in `matthew_mcp_observations`. Join those tables when a question needs that depth.
- **`ai_agent_source` (observation-based) vs `ai_agent_source_legacy` (score-based)**: the **observation-based** `ai_agent_source` is the **correct, deterministic** view. Use it for current metrics. The score-based `ai_agent_source_legacy` is non-deterministic, suffers from incomplete eval coverage, and **does not encode V3 or later versions**, but is the **only** way to reproduce historical escalation rate / volume metrics that pre-date the observation logic — use it explicitly for back-comparable trends.
- **`is_matthew_in_session` is observation-only and strictly narrower than `ai_agent_source`**: historical `bot = 'matthew'` (WhatsApp) sessions without recorded traces can have `ai_agent_source = 'Matthew in Whatsapp'` and `is_matthew_in_session = FALSE` simultaneously. For the canonical "Matthew was involved" question use `ai_agent_source <> 'Wall-e'`.
- **`messages` only includes Matthew sessions** (`ai_agent_source IN ('Matthew in Chat', 'Matthew in Whatsapp')` with trace) — do not assume it covers Wall-E-only sessions.
- **LLM cost/latency are stored as ADDITIVE COUNTERS, not averages — compute every average as `SUM(numerator) / SUM(denominator)`, never `AVG(...)` of a per-session average.** `matthew_llm_metrics` / `fact_ai_agents_interaction` deliberately expose only sums and counts (`n_agent_messages`, `n_llm_calls`, `total_llm_cost`, `total_collections_agent_cost`, `total_message_latency_sum`, `collections_agent_latency_sum`, `collections_agent_llm_latency_sum`) precisely so that averaging across a group of sessions is correct. Every headline average is derivable:
  - **avg LLM calls per message** = `SUM(n_llm_calls) / SUM(n_agent_messages)`
  - **avg collections-agent cost per message** = `SUM(total_collections_agent_cost) / SUM(n_agent_messages)`
  - **avg collections-agent cost per LLM call** = `SUM(total_collections_agent_cost) / SUM(n_llm_calls)`
  - **avg total latency per message** (s) = `SUM(total_message_latency_sum) / SUM(n_agent_messages)`
  - **avg collections-agent latency per message** (s) = `SUM(collections_agent_latency_sum) / SUM(n_agent_messages)`
  - **avg collections-agent latency per LLM call** (s) = `SUM(collections_agent_llm_latency_sum) / SUM(n_llm_calls)`
  - **timeout rate** = `AVG(flag_session_had_timeout)` (this one is a per-session 0/1 flag, so a plain average over sessions is correct).
  Always wrap the denominators with `NULLIF(..., 0)`. Latency numerators are scoped to **agent messages** (turns where the collections agent ran), matching the `n_agent_messages` denominator.
- **Always include `id_external`** (Langfuse session ID) in analytical exports; engineering uses it to drill into specific traces.

## Key Metrics

- **Session volume** — `COUNT(DISTINCT s.id_session)`, broken down by `ai_agent_source` and month of `dt_session_created`.
- **Escalation rate** (primary metric) — `COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) / COUNT(DISTINCT id_session)`. Indicates lack of capability or hard scenarios for Matthew.
- **Escalation volume** — `COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END)`. For trended back-comparable analyses, use `ai_agent_source_legacy`.
- **Outbound reply rate** — share of sessions where `is_notification_reply = 1`, scoped to WhatsApp.
- **Negotiation rate** — share of Matthew sessions with `flag_create_negotiation = 1`. Funnel detail: `send_proposal_count` → `confirm_negotiation_count` → `flag_create_negotiation`; `handle_negotiation_cancelled_count` captures confirmations that did not become deals.
- **Proposal volume per session** — `AVG(send_proposal_count)` among Matthew sessions.
- **Tool-usage rate** — share of sessions hitting each unified tool flag (`flag_get_yearly_paid_invoices_report_tool`, `flag_negotiation_proposer_tool`, `flag_ongoing_deal_renegotiation_request_helper`, ...). For V2-only tools (e.g. payment allegation) join `observation`; for V3+ per-tool call counts join `matthew_mcp_observations`.
- **Data-failure escalation rate (Pillar A)** — escalation rate among sessions with `flag_fetch_financial_data_error = 1 OR flag_empty_invoices_mismatch = 1 OR flag_no_contracts_mismatch = 1`. Combines the fetch-error flag with the data-quality cross-checks against the user wallet snapshot.
- **Post-session recovery** — `user_overdue_recovered_amount_t2_w_2` (overdue recovered) and `user_payment_w_2` (total paid) within a 2-day window starting at the session date. Used to attribute payment lift to Matthew conversations across versions.
- **Agent-version comparison** — group any version-agnostic metric by `matthew_version`. Use the 2026-05-15 to 2026-05-25 experiment context for historical V2-vs-V3 analysis and the relevant V4 test window for V3-vs-V4 analysis. Avoid V3+-only MCP detail columns when one side is V2.
- **Data-quality cross-checks (V3+)** — `flag_empty_invoices_mismatch` (agent saw only empty invoices but the wallet snapshot has invoices) and `flag_no_contracts_mismatch` (agent concluded "no contracts" but the wallet shows contracts). High rates signal data-acquisition problems on the agent side.
- **In-domain coverage** — share of escalations where the conversation is genuinely within Matthew's scope (Pillars B and C) vs out-of-scope (NON_TENANT_PROFILE, CREDIT_GUARANTEE, CONTRACT_TERMINATION, REIMBURSEMENT_*, NON_RECURRING_FINANCE, SERVICE_BILLS, PROPERTY_OPERATIONS, CONTRACT_CHANGES). Requires LLM-based classification on `full_conversation`.
- **LLM cost / latency / efficiency by model** — compare `matthew_model` groups using the additive counters, always as `SUM(numerator)/SUM(denominator)` (see the averages rule under Critical rules): avg LLM calls per message, cost per message, cost per LLM call, latency per message (total and collections-agent), latency per LLM call, and timeout rate. Also useful in absolute terms: `SUM(total_llm_cost)` (all-in spend) and `SUM(total_collections_agent_cost)` (agent-only spend) per model. See Golden Query 6.

### Escalation analysis pillars

When investigating escalations, decompose hierarchically:

- **Pillar A — Data failures** (deterministic). Sessions where Matthew failed to fetch the user's collections context, or where the data it saw disagrees with the user wallet snapshot. Proxy on the fact table: `flag_fetch_financial_data_error = 1 OR flag_empty_invoices_mismatch = 1 OR flag_no_contracts_mismatch = 1`.
- **Pillar B — Out-of-scope themes** (no ready observation; needs LLM analysis on `full_conversation`). The user brings a problem Matthew is not designed to solve — see the out-of-scope categories list below.
- **Pillar C — Conversation-driven escalations** (no ready observation; needs LLM analysis). The conversation itself failed (misunderstanding, repeated loops, user dissatisfaction) despite the topic being in scope. `flag_handle_non_tenant` and `flag_ongoing_deal_renegotiation_request_helper` can hint at specific patterns but do not fully explain; for V3-or-later sessions, `flag_negotiation_created_missing_payment_info` flags deals closed without the payment instructions being shown.

**Out-of-scope categories** (used by Pillar B classification on `full_conversation`):
`NON_TENANT_PROFILE`, `CREDIT_GUARANTEE`, `CONTRACT_TERMINATION`, `REIMBURSEMENT_QA`, `REIMBURSEMENT_CONDO`, `REIMBURSEMENT_REPAIRS`, `NON_RECURRING_FINANCE`, `SERVICE_BILLS`, `PROPERTY_OPERATIONS`, `CONTRACT_CHANGES`. Note: an ended contract whose user only wants to pay/negotiate the residual debt is **IN_DOMAIN**, not `CONTRACT_TERMINATION`.

## Relationships with Other Entities

### Chatbot Sessions (1:1 — Matthew sessions are a subset of chatbot sessions)

- `datalake_ai_collections_quintoandar.sessions` is built from `datalake_chatbot.sessions` filtered to `bot IN ('matthew', 'wall-e')`.
- For broader chatbot context (other bots: `sonia`, `isaias`, `concierge`, `vandinha`, `old bot`), see `domain_entities/chatbot_sessions.md`.
- JOIN back: `datalake_ai_collections_quintoandar.sessions.id_sauron_session = datalake_chatbot.sessions.id_sauron_session`.

### Collections (N:1 — many Matthew sessions per contract / user)

- A user touched by Matthew typically has open invoices in `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`. The flag `has_matthew_interaction` on that timeline is the cross-reference.
- For deeper collections context (negotiations, deals, recovery channels, T1/T2/T3 delays, evictions), see `domain_entities/collections.md`.

### User Wallet (1:1 at session date)

- `dw_collection_ai_agents.fact_ai_agents_interaction` already joins `fact_user_wallet_timeline` on `sk_user = id_user` and `dt_reference = dt_session_created`.
- For ad-hoc joins from `sessions`: `fuwt.sk_user = s.id_user AND fuwt.dt_reference = s.dt_session_created`.

### CDP (N:1 — user journey and persona outside session grain)

- For **cross-entity user context** (visits, offers, contracts, invoices in one row set for Domi/Matthew-style products) → `datalake_transactional_entities.entities` on `sessions.id_user = entities.id_user`; see `domain_entities/cdp.md`.
- For **current platform role / journey step** → `datalake_cdp.persona` (external system, not in this repo) on `id_user` — not `datalake_cdp_personas.persona` (the repo-built table) unless the question is historical.
- Session-level chatbot metrics stay in this doc and `domain_entities/chatbot_sessions.md` — CDP does not replace `datalake_chatbot.sessions`.

### Support Tickets (1:1 — one ticket per escalated session)

- `s.id_ticket` populated when `is_escalation = TRUE`.
- JOIN to `datalake_customer_support.tickets.id_ticket` for SLA and queue routing context.

### Langfuse Traces / Observations (1:N — one session has many traces and observations)

- `datalake_langfuse_clean.traces.id_session = s.id_external`.
- `datalake_langfuse_clean.observations.id_trace = traces.id_trace`.
- `datalake_ai_collections_quintoandar.observation` (V2 signals plus generic version detection), `datalake_ai_collections_quintoandar.matthew_mcp_observations` (V3+ MCP signals) and `datalake_ai_collections_quintoandar.matthew_llm_metrics` (LLM model / cost / latency / call counters) already aggregate the relevant Matthew activity per session — prefer them over raw Langfuse tables for session-grain analysis. All join via `id_langfuse_session = s.id_external`. `matthew_llm_metrics` cost/latency come from the observation `GENERATION` rows (`cost_details.total`, `latency`), since trace-level `total_cost`/`latency` are not populated.

## Dos and Don'ts

**Do:**
- Always filter `flag_session_with_trace = TRUE` (or `flag_session_with_trace` shorthand) on `datalake_ai_collections_quintoandar.sessions` before any analytical aggregation.
- Use `ai_agent_source` as the canonical agent attribution for current metrics; group by it (`'Matthew in Chat'`, `'Matthew in Whatsapp'`, `'Wall-e'`) instead of by `bot`.
- Use `ai_agent_source_legacy` only when reproducing historical escalation rate / volume series that pre-date the observation logic.
- Use `dw_collection_ai_agents.fact_ai_agents_interaction` as the default starting point for analytical questions — it already has the V2/V3+-unified business signals, user wallet context and full conversation joined.
- Use `matthew_version` to split V2, V3, V4, and future versions. The V2-vs-V3 historical timeline is A/B from 2026-05-15 and V3 at 100% from 2026-05-25; use the applicable rollout window for V3-vs-V4 model-test comparisons.
- Include `id_external` (Langfuse session ID) in any analytical export so engineering can debug specific sessions.
- For outbound analyses (WhatsApp only), filter `is_notification_reply = 1` and use `notif_text_extracted` / `notif_template_extracted` to attribute the campaign.
- For thematic conversation breakdowns (e.g. boleto, IR, alegação), apply `LOWER(full_conversation) LIKE '%term%'` regex on `datalake_ai_collections_quintoandar.messages` or on the OBT.
- For Pillar A escalation analysis, combine the three data-failure flags with OR (`flag_fetch_financial_data_error = 1 OR flag_empty_invoices_mismatch = 1 OR flag_no_contracts_mismatch = 1`).
- For LLM cost/latency/efficiency comparisons, group by `matthew_model` (the LLM) and compute every average as `SUM(numerator)/SUM(denominator)` from the additive counters (see Golden Query 6).

**Don't:**
- Don't analyse Matthew sessions on `bot = 'matthew'` alone — that excludes Matthew running inside Wall-E (`'Matthew in Chat'`). Use `ai_agent_source <> 'Wall-e'` instead.
- Don't equate `is_matthew_in_session` with "Matthew was involved" in WhatsApp — historical `bot = 'matthew'` sessions without traces have `is_matthew_in_session = FALSE` despite Matthew being the host. Use `ai_agent_source <> 'Wall-e'` for the canonical question.
- Don't drop sessions with `flag_session_with_trace = FALSE` silently when measuring outbound send-off volume — those rows exist precisely to count send-offs without replies.
- Don't use columns exclusive to one architecture to compare V2 with V3+ — the V3+-only columns (`user_segment`, `n_contracts_mcp`, `created_negotiation_*`, `ts_*_mcp_call`, ...) are NULL for V2 sessions by construction. Version-agnostic metrics (escalation rate, negotiation rate, the unified flags, post-session recovery) are valid comparison grounds.
- Don't look for granular per-tool signals in the fact table — they live in `observation` (V2 per-tool flags like `flag_payment_allegation_tool`) and `matthew_mcp_observations` (V3+ per-tool call/error counts); join those tables when that depth is needed.
- Don't confuse `n_contracts` (user wallet snapshot at session date) with `n_contracts_mcp` (contracts the V3-or-later agent actually saw during the conversation) — their disagreement is precisely what `flag_no_contracts_mismatch` measures.
- Don't read column descriptions for any of the columns referenced here from this file alone; full column-level documentation lives in `metadata/enrich/sessions.yml`, `metadata/enrich/observation.yml`, `metadata/enrich/matthew_mcp_observations.yml`, `metadata/enrich/messages.yml` and `metadata/dw/fact_ai_agents_interaction.yml`.
- Don't use `matthew_version` as a filter for "Matthew was involved" — it is observation-derived only and excludes WhatsApp-without-traces sessions (NULL version). Use `ai_agent_source <> 'Wall-e'`.
- Don't assume `messages.full_conversation` is available for Wall-E-only sessions — `messages` is filtered to `ai_agent_source IN ('Matthew in Chat', 'Matthew in Whatsapp')` only.
- Don't try to explain Pillars B and C from observations alone — they require LLM analysis on `full_conversation` against the out-of-scope category list.
- Don't average the LLM cost/latency metrics as `AVG(per_session_value)` — the tables store additive counters exactly so you compute `SUM(numerator)/SUM(denominator)`; averaging pre-averaged per-session values biases the result. (The only plain average is `timeout_rate = AVG(flag_session_had_timeout)`, a per-session 0/1 flag.)
- Don't use `matthew_version` as the model-comparison dimension for cost/latency — that is the architecture generation. Use `matthew_model` (the LLM). A single version can run different models (e.g. V4 model tests).

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
         AND (flag_fetch_financial_data_error = 1
              OR flag_empty_invoices_mismatch = 1
              OR flag_no_contracts_mismatch = 1)
        THEN id_session
    END) AS n_escalated_pillar_a,
    COUNT(DISTINCT CASE
        WHEN is_escalation
         AND NOT (flag_fetch_financial_data_error = 1
                  OR flag_empty_invoices_mismatch = 1
                  OR flag_no_contracts_mismatch = 1)
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
    f.matthew_version,
    f.dt_session_created,
    f.user_wallet_overdue_t2,
    f.flag_user_delay,
    f.matthew_declared_escalation_reason,
    f.full_conversation
FROM dw_collection_ai_agents.fact_ai_agents_interaction AS f
WHERE f.is_escalation
  AND f.flag_fetch_financial_data_error = 0
  AND f.flag_empty_invoices_mismatch = 0
  AND f.flag_no_contracts_mismatch = 0
  AND f.dt_session_created >= DATE '{start_date}'
  AND f.dt_session_created < DATE '{end_date}'
ORDER BY f.dt_session_created DESC
LIMIT 200
```

### Query 5 — Agent-version comparison

Compares Matthew versions on negotiation funnel, data failures, escalation and 2-day post-session recovery, using version-agnostic metrics so every selected version is measured identically. Use the historical A/B window for V2-vs-V3 or the applicable model-test window for V3-vs-V4.

```sql
SELECT
    matthew_version,
    COUNT(DISTINCT id_session) AS n_sessions,
    AVG(send_proposal_count) AS avg_proposals,
    CAST(COUNT(DISTINCT CASE WHEN flag_create_negotiation = 1 THEN id_session END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_session), 0) AS negotiation_rate,
    CAST(COUNT(DISTINCT CASE
        WHEN flag_fetch_financial_data_error = 1
          OR flag_empty_invoices_mismatch = 1
          OR flag_no_contracts_mismatch = 1
        THEN id_session
    END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_session), 0) AS data_failure_rate,
    CAST(COUNT(DISTINCT CASE WHEN is_escalation THEN id_session END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_session), 0) AS escalation_rate,
    SUM(user_overdue_recovered_amount_t2_w_2) AS total_overdue_recovered_2d,
    SUM(user_payment_w_2) AS total_payment_2d
FROM dw_collection_ai_agents.fact_ai_agents_interaction
WHERE matthew_version IN ('V2', 'V3', 'V4')
  AND dt_session_created >= DATE '{start_date}'
  AND dt_session_created < DATE '{end_date}'
GROUP BY 1
ORDER BY 1
```

### Query 6 — LLM cost / latency / efficiency by model

Compares Matthew across LLM models using the additive counters. **Every average is `SUM(numerator)/SUM(denominator)`** so the comparison stays correct across the whole group of sessions (never `AVG` of a per-session average). Group by `matthew_model`; add `matthew_version` if you also want to separate architecture generations.

```sql
SELECT
    matthew_model,
    COUNT(DISTINCT id_session) AS n_sessions,
    SUM(n_agent_messages) AS n_agent_messages,
    SUM(n_llm_calls) AS n_llm_calls,
    -- efficiency
    CAST(SUM(n_llm_calls) AS DOUBLE) / NULLIF(SUM(n_agent_messages), 0) AS avg_llm_calls_per_message,
    -- cost (USD)
    SUM(total_llm_cost) AS total_llm_cost,
    SUM(total_collections_agent_cost) AS total_collections_agent_cost,
    SUM(total_collections_agent_cost) / NULLIF(SUM(n_agent_messages), 0) AS avg_collections_agent_cost_per_message,
    SUM(total_collections_agent_cost) / NULLIF(SUM(n_llm_calls), 0) AS avg_collections_agent_cost_per_llm_call,
    -- latency (seconds)
    SUM(total_message_latency_sum) / NULLIF(SUM(n_agent_messages), 0) AS avg_total_latency_per_message,
    SUM(collections_agent_latency_sum) / NULLIF(SUM(n_agent_messages), 0) AS avg_collections_agent_latency_per_message,
    SUM(collections_agent_llm_latency_sum) / NULLIF(SUM(n_llm_calls), 0) AS avg_collections_agent_latency_per_llm_call,
    -- reliability
    AVG(CAST(flag_session_had_timeout AS DOUBLE)) AS timeout_rate
FROM dw_collection_ai_agents.fact_ai_agents_interaction
WHERE matthew_model IS NOT NULL
  AND dt_session_created >= DATE '{start_date}'
  AND dt_session_created < DATE '{end_date}'
GROUP BY 1
ORDER BY n_sessions DESC
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
