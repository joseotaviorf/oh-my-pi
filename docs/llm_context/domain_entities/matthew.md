# Matthew

## Ownership

**Data Owner:**
- thiago.villani@quintoandar.com.br

**Data Steward:**
- thiago.villani@quintoandar.com.br

## Overview

Matthew is the **AI agent dedicated to tenants with open balances** — overdue invoices or invoices not yet due — helping them regularize their debts via direct payment, payment-method support, or full-debt negotiation (installments / discounts). It is the collections counterpart to QuintoAndar's general-purpose support bot Wall-E.

Matthew operates in **three environments**:

1. **WhatsApp** — Matthew runs as a standalone host (`bot = 'matthew'`).
2. **In-app chat** — Matthew runs as a sub-agent inside the Wall-E host (`bot = 'wall-e'` plus a Matthew-specific signal).
3. **Voice** — Matthew collections outbound calls via Copilot + Twilio (production Langfuse traces tagged with both `matthew` and `online_call`; the endpoint name is not part of the analytical contract). Voice sessions do **not** flow through `datalake_chatbot.sessions`; use the voice tables below instead of `fact_ai_agents_interaction`.

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

**Host planner version (WhatsApp only).** `matthew_host_version` tags the Matthew WhatsApp *host* planner LLM experiment: `V2` when the first `Host - HostPlanner` GENERATION uses `openai/gpt-4o-2024-11-20`, `V3` when it uses `openai/gpt-5.6-luna`. NULL for Matthew-in-Chat (Wall-e host uses `WallEHost - HostPlanner`), other host models, or sessions without a host planner call. Distinct from `matthew_version` (collections-agent architecture) and `matthew_model` (collections-agent LLM). Raw model name is in `matthew_llm_metrics.matthew_host_model` (enrich only).

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
- **MCP tools** → backend-for-bots services the V3-or-later agent calls: `get_financial_context_v1` (contracts + debts, including contract billing facts), `get_debt_breakdown_v1`, `get_negotiation_options_v1`, `simulate_negotiation_v1` (proposal simulation), `create_negotiation_v1` (deal creation), `get_ongoing_negotiation_information_v1`, `get_annual_tax_report_v1` / `get_paid_invoices_annual_report_v1` (IR report), `get_last_paid_invoices_v1`, `get_original_invoices_by_status_v1`.
- **Garantia Locatícia / mora e paga / paga e mora** → how this tenant pays rent relative to occupancy. **Mora e paga** (occupies first, pays after) means the contract has Garantia Locatícia (`matthew_mcp_observations.flag_has_rental_guarantee = 1`). **Paga e mora** (pays rent in advance, typically Fairfax) is `flag_has_rental_guarantee = 0`. NULL means `get_financial_context_v1` did not log a successful SeuBarriga `GetContractBillingFacts` call — do not treat NULL as paga e mora. Per-call values live in `mcp_tool_logs.call_has_rental_guarantee`.
- **Occupancy start / início de ocupação / boletinho / boletão** → calendar date the tenant's occupancy started (`matthew_mcp_observations.dt_occupancy_started`, from `mcp_tool_logs.call_dt_occupancy_started`). Used to tell first-month billing cases apart (boletinho vs boletão). Stored as the SeuBarriga start-period date with no timezone conversion.
- **Condominium payer / quem paga o condomínio** → who pays the condominium fee on the collected contract (`matthew_mcp_observations.condominium_payer` / `mcp_tool_logs.call_condominium_payer`): `TENANT` (tenant or QuintoAndar), `LANDLORD` (including self-condo), or `NONE` (no condominium charge).
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
- **matthew_host_version** → Matthew WhatsApp host planner experiment tag (`V2` / `V3` / NULL) from the first `Host - HostPlanner` GENERATION in the session. NULL for Matthew-in-Chat. Column in `fact_ai_agents_interaction`; raw model in `matthew_llm_metrics.matthew_host_model`.
- **flag_outbound_responsibility_helper** → 1 when the Matthew host invoked `outbound_debt_responsibility_denial_helper` (user denied responsibility for an outbound debt reminder); else 0. WhatsApp host only.
- **flag_authentication_helper** → 1 when the Matthew host invoked `authentication_helper` (WhatsApp login guidance after auth failure); else 0. Distinct from `authentication_failure_helper`. WhatsApp host only.
- **Payin online evals** → sparse hourly LLM-as-a-judge sample of Matthew WhatsApp sessions, pivoted from Langfuse scores `PayinResolutionEvaluator`, `PayinFailureDiagnosisEval`, and `PayinFrustrationEval`. Columns on the fact: `eval_payin_resolution` (0/1), `eval_payin_failure_diagnosis` (`FORA_DE_ESCOPO` / `SEM_CONTRATO` / `SEM_CAPACIDADE` / `FALHA_DE_COMPORTAMENTO`), `eval_payin_frustration` (`SEM_FRUSTRACAO` / `FRUSTRACAO_GERAL` / `FRUSTRACAO_COM_O_BOT`). NULL means the session was not judged, not a negative. Always NULL for Matthew-in-Chat. Join key is `id_external`.
- **LLM call / planner call** → one collections-agent LLM invocation (a `CollectionsAgentV<N> - ReactPlanner` planner step, which drives exactly one LLM generation). Counted per session by `n_llm_calls`. "LLM calls" and "planner calls" are the same thing.
- **Agent message** → a message/turn (Langfuse trace) in which the collections agent called the LLM at least once. Counted per session by `n_agent_messages`. This is the denominator for "per message" metrics.
- **Collections-agent cost** → USD cost of the collections-agent LLM calls only (`total_collections_agent_cost`), excluding host-side moderator + answer-processor LLM cost. `total_llm_cost` is the all-in session LLM cost (agent + host-side).
- **Timeout** → a message whose collections-agent-input observation was recorded with `level = 'ERROR'` (the agent exceeded its time budget, ~90s). Session flag: `flag_session_had_timeout = 1`.
- **Voice call / id_langfuse_session** → one outbound Matthew collections dial. Primary key across voice tables (`id_langfuse_session` = Langfuse `traces.id_session` = Copilot `voice_call_attempt.id_voice_call_external`). Twilio SID is `id_twilio_call` (`call_sid` on the Langfuse `traces.output`, session grain only — Copilot `voice_call_provider_id` is not a Twilio SID). It lives on `fact_ai_agents_voice_sessions`; join it in when you need the SID next to an event.
- **Call duration** → `call_duration` on the session table is the wrapping Langfuse span `latency` in seconds (the earliest observation on the trace, today named `/v1/voice`). It approximates Twilio talk time. Do not derive duration from Copilot `voice_session` timestamps — those are campaign-grain.
- **VAD (voice activity detection)** → after each `user_speech` group, a single `vad` timeline row records the honor/suppress gate: `vad_first_decision` (`honor` / `suppress`) and `vad_final_outcome` (`honor_immediate` / `barge_in_honored` / `backchannel_discarded`). **Failed VAD** = `flag_failed_vad = 1` (discarded with a non-empty user transcript).
- **Agent interrupt** → not a separate event type; `flag_agent_interrupted = 1` on `agent_speech` rows when playback was cancelled mid-turn. In a reconstructed transcript, keep the turn and append ` (interrupted)` to the line.
- **Voice transcript** → there is no stored `full_conversation` for voice. Rebuild from `user_speech` + `agent_speech` in `event_index` order, dropping user turns whose following VAD is `backchannel_discarded`. See **Reconstructing a voice transcript** and Golden Query 9.
- **Voice error / n_error_observations** → count of Langfuse observations named `error` on the call. Do not read it as a dial failure: observed rows are `invalid_request_error` protocol races from barge-in handling (`conversation_already_has_active_response`, `response_cancel_not_active`). The producer currently emits each error twice, so the count is the raw span total until that logging is fixed. Langfuse `observations.level` is always `DEFAULT` on voice traces and carries no error signal.
- **LLM voice judge** → sparse sample (~8% of calls) tagged with `MatthewVoiceTag*` scores pivoted to `eval_*` on the session table. `has_llm_voice_tags = 0` means `eval_*` is NULL (not judged), not a negative. Deterministic twins: `flag_call_answered`, `flag_user_spoke`, `flag_answered_by_machine`, identity trio (`flag_identity_check_triggered`, `n_identity_check_calls`, `flag_identity_check_result`).

## Tables

| You need... | Use this table |
|-------------|----------------|
| One row per session with bot, channel-derived `ai_agent_source`, `matthew_version`, escalation, outbound flag, user roles, and trace presence | `datalake_ai_collections_quintoandar.sessions` (`s`) — merge key `id_sauron_session`. **Always filter `flag_session_with_trace = TRUE`**. |
| Pre-joined wide table: sessions + V2/V3+-unified business signals + V3+-only MCP signals + messages + user wallet context and 2-day post-session recovery | `dw_collection_ai_agents.fact_ai_agents_interaction` (`f`) — analytical OBT, **default starting point**. Already filters `flag_session_with_trace = TRUE`. |
| Granular V2 milestones plus versioned-input and ReactPlanner detection at session grain | `datalake_ai_collections_quintoandar.observation` (`o`) — one row per Langfuse session. JOIN via `o.id_langfuse_session = s.id_external`; use `flag_collections_agent_input` and `collections_agent_version` for generic version detection. |
| Granular V3+ MCP activity (per-tool call/error counts like `n_financial_context_calls`, `n_create_negotiation_errors`, contract-level negotiation breakdowns, and contract billing facts) at session grain | `datalake_ai_collections_quintoandar.matthew_mcp_observations` (`mo`) — one row per Langfuse session with MCP activity. JOIN via `mo.id_langfuse_session = s.id_external`. Billing facts from `get_financial_context_v1`: `flag_has_rental_guarantee`, `dt_occupancy_started`, `condominium_payer`. |
| Per-session LLM model, cost, latency and call-volume counters (for comparing Matthew across LLM models) | `datalake_ai_collections_quintoandar.matthew_llm_metrics` (`llm`) — one row per Langfuse session. Already joined into `fact_ai_agents_interaction` (columns `matthew_model`, `matthew_host_version`, `n_agent_messages`, `n_llm_calls`, `total_llm_cost`, `total_collections_agent_cost`, `total_message_latency_sum`, `collections_agent_latency_sum`, `collections_agent_llm_latency_sum`, `flag_session_had_timeout`) — **prefer the fact**. JOIN standalone via `llm.id_langfuse_session = s.id_external`. Raw host model: `matthew_host_model` (enrich only). |
| Online Payin evaluator scores for Matthew WhatsApp (resolution, failure diagnosis, frustration) | `datalake_ai_collections_quintoandar.matthew_payin_evals` — one row per judged Langfuse session. Already joined into `fact_ai_agents_interaction` (`eval_payin_resolution`, `eval_payin_failure_diagnosis`, `eval_payin_frustration`) — **prefer the fact**. JOIN standalone via `id_langfuse_session = s.id_external`. |
| Individual V3+ MCP tool requests and their downstream service calls (debugging grain) | `datalake_ai_collections_quintoandar.mcp_tool_logs` — one row per downstream service call inside an MCP tool request. Engineering-oriented; prefer the session-grain tables for analytics. SeuBarriga `GetContractBillingFacts` rows expose `call_has_rental_guarantee`, `call_dt_occupancy_started`, `call_condominium_payer` (NULL on every other function). |
| Full agglutinated conversation text per session for LLM analysis or regex theme filtering (e.g. `boleto`, `IR`) | `datalake_ai_collections_quintoandar.messages` (`m`) — one row per Matthew session. JOIN via `m.id_sauron_session = s.id_sauron_session`. Includes both `'Matthew in Whatsapp'` and `'Matthew in Chat'` only. |
| User wallet snapshot at any reference date (delay, overdue amount, active/ended contract counts) | `dw_collection_ai_agents.fact_user_wallet_timeline` (`fuwt`) — daily user-grain snapshot. Used to enrich Matthew sessions with delinquency context. |
| **Voice** — reconstructable call timeline (user/agent speech, VAD, tools) | `datalake_ai_collections_quintoandar.matthew_voice_events` (enrich) / `dw_collection_ai_agents.fact_ai_agents_voice_events` (DW wrap). JOIN to sessions on `id_langfuse_session`. Order by `event_index`. |
| **Voice** — one row per call with dial state, debt context, metrics, LLM tags, deterministic flags | `datalake_ai_collections_quintoandar.matthew_voice_sessions` (enrich) / `dw_collection_ai_agents.fact_ai_agents_voice_sessions` (DW wrap). Grain = one production Langfuse session tagged with both `matthew` and `online_call`. |

**Voice pipeline pattern:** heavy parsing lives in **enrich** (`matthew_voice_events`, `matthew_voice_sessions`); **DW** facts are thin `SELECT` projections for analyst access — same split as text Matthew (`observation` / `messages` → `fact_ai_agents_interaction`).

**Critical rules (voice):**
- Default quality filter: `flag_call_answered = 1 AND flag_user_spoke = 1`.
- Reconstruct a voice transcript from events (see **Reconstructing a voice transcript**); the sessions table does not store `full_conversation`, and chat `messages.full_conversation` does not cover voice.
- `eval_*` is NULL when `has_llm_voice_tags = 0`; never treat missing judge tags as negatives.
- Failed identity check is inferred: `flag_identity_check_triggered = 1 AND flag_identity_check_result = 0` (no `eval_user_failed_identity_check` column).

**Critical rules (chat):**
- **Mandatory filter**: `flag_session_with_trace = TRUE`. Sessions without trace are kept in `sessions` only to record outbound send-offs (no user reply yet) and contain no analysable interaction. Skip them in every analysis except outbound funnel volume.
- **Unified vs V3+-only vs granular columns in the fact table**:
  - **Unified columns** work for every session regardless of version (V3+ MCP value when the session has MCP activity, V2 observation value otherwise): `send_proposal_count`, `confirm_negotiation_count`, `flag_create_negotiation`, `handle_negotiation_cancelled_count`, `flag_handle_segments_without_proposals`, `flag_fetch_financial_data`, `flag_fetch_financial_data_error`, `flag_has_fetch_contracts`, `flag_handle_no_contracts`, `flag_get_yearly_paid_invoices_report_tool`, `flag_negotiation_proposer_tool`, `flag_ongoing_deal_renegotiation_request_helper`, `flag_handle_non_tenant`, `flag_has_prorated_rent`. Use these by default.
  - **`flag_matthew_talked_to_user`** is a 0/1 flag (never NULL), unified across all generations: 1 when Matthew actually spoke to the user, else 0. `bot = 'matthew'` (WhatsApp host) always counts; `bot = 'wall-e'` counts only when `is_matthew_in_session` AND the collections agent relayed a message (V3+ `TalkToUserTool` or legacy V2 `CollectionsInput` `RESPOND EXACTLY`). Because the WhatsApp-host branch is version-agnostic and V1/V1.5 exist only there, do not read a `0` as "no Matthew" — pair it with `ai_agent_source` / `matthew_version` for version splits.
  - **V3+-only columns** are NULL for V2 sessions: `n_contracts_mcp`, `flag_all_empty_invoices_mcp`, `user_segment`, `negotiation_options_list`, `created_negotiation_option_key`, `created_negotiation_payment_method`, `flag_negotiation_created_missing_payment_info`, `ts_first_mcp_call`, `ts_last_mcp_call`. Never use them to compare V2 with V3+ — V2 will look like zero/NULL by construction.
  - **Granular signals** live in the source tables: per-tool V2 flags (e.g. `flag_payment_allegation_tool`, `flag_debt_retriever_tool`) in `observation`; per-tool V3+ call/error counts (e.g. `n_financial_context_calls`, `n_create_negotiation_errors`) and contract billing facts (`flag_has_rental_guarantee`, `dt_occupancy_started`, `condominium_payer`) in `matthew_mcp_observations`. Join those tables when a question needs that depth. These billing-fact columns are **not** on `fact_ai_agents_interaction`.
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
- **`eval_payin_*` is NULL when the WhatsApp session was not sampled** by the hourly online eval job (or for Matthew-in-Chat). Never treat missing Payin evals as negatives. `eval_payin_resolution` is a discrete 0/1 code — rates among judged sessions only, never `AVG` across the full fact.
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
- For a readable voice call transcript, follow **Reconstructing a voice transcript**: keep `user_speech` and `agent_speech` in `event_index` order, drop user turns the VAD discarded (`backchannel_discarded`), and append ` (interrupted)` to agent turns with `flag_agent_interrupted = 1`.

**Don't:**
- Don't analyse Matthew sessions on `bot = 'matthew'` alone — that excludes Matthew running inside Wall-E (`'Matthew in Chat'`). Use `ai_agent_source <> 'Wall-e'` instead.
- Don't equate `is_matthew_in_session` with "Matthew was involved" in WhatsApp — historical `bot = 'matthew'` sessions without traces have `is_matthew_in_session = FALSE` despite Matthew being the host. Use `ai_agent_source <> 'Wall-e'` for the canonical question.
- Don't drop sessions with `flag_session_with_trace = FALSE` silently when measuring outbound send-off volume — those rows exist precisely to count send-offs without replies.
- Don't use columns exclusive to one architecture to compare V2 with V3+ — the V3+-only columns (`user_segment`, `n_contracts_mcp`, `created_negotiation_*`, `ts_*_mcp_call`, ...) are NULL for V2 sessions by construction. Version-agnostic metrics (escalation rate, negotiation rate, the unified flags, post-session recovery) are valid comparison grounds.
- Don't look for granular per-tool signals in the fact table — they live in `observation` (V2 per-tool flags like `flag_payment_allegation_tool`) and `matthew_mcp_observations` (V3+ per-tool call/error counts and contract billing facts); join those tables when that depth is needed.
- Don't join Retsuko `contract.guarantee` / `ts_period_started` to classify paga e mora vs mora e paga or occupancy start for V3+ Matthew sessions — use `matthew_mcp_observations.flag_has_rental_guarantee` and `dt_occupancy_started` (or the `mcp_tool_logs.call_*` columns at call grain). `flag_has_rental_guarantee` NULL means the billing-facts lookup did not succeed, not paga e mora.
- Don't confuse `n_contracts` (user wallet snapshot at session date) with `n_contracts_mcp` (contracts the V3-or-later agent actually saw during the conversation) — their disagreement is precisely what `flag_no_contracts_mismatch` measures.
- Don't read column descriptions for any of the columns referenced here from this file alone; full column-level documentation lives in `metadata/enrich/sessions.yml`, `metadata/enrich/observation.yml`, `metadata/enrich/matthew_mcp_observations.yml`, `metadata/enrich/messages.yml` and `metadata/dw/fact_ai_agents_interaction.yml`.
- Don't use `matthew_version` as a filter for "Matthew was involved" — it is observation-derived only and excludes WhatsApp-without-traces sessions (NULL version). Use `ai_agent_source <> 'Wall-e'`.
- Don't assume `messages.full_conversation` is available for Wall-E-only sessions — `messages` is filtered to `ai_agent_source IN ('Matthew in Chat', 'Matthew in Whatsapp')` only.
- Don't try to explain Pillars B and C from observations alone — they require LLM analysis on `full_conversation` against the out-of-scope category list.
- Don't average the LLM cost/latency metrics as `AVG(per_session_value)` — the tables store additive counters exactly so you compute `SUM(numerator)/SUM(denominator)`; averaging pre-averaged per-session values biases the result. (The only plain average is `timeout_rate = AVG(flag_session_had_timeout)`, a per-session 0/1 flag.)
- Don't use `matthew_version` as the model-comparison dimension for cost/latency — that is the architecture generation. Use `matthew_model` (the LLM). A single version can run different models (e.g. V4 model tests).
- Don't dump every voice event into a transcript. Tool calls and VAD rows are not spoken turns. User speech that VAD discarded (`vad_final_outcome = 'backchannel_discarded'`) was never heard by the agent — leave it out. Do not use chat `messages.full_conversation` for voice calls.

## Reconstructing a voice transcript

Voice sessions have no stored `full_conversation`. Build the transcript from `dw_collection_ai_agents.fact_ai_agents_voice_events` (or the enrich twin `matthew_voice_events`).

**Keep only spoken turns.** `event_type IN ('user_speech', 'agent_speech')`. Drop `vad` and `tool_call` rows from the text; they are control events, not utterances.

**Drop ignored user speech.** After each user turn the VAD gate either honors the utterance or discards it as backchannel. A `vad` row with `vad_final_outcome = 'backchannel_discarded'` belongs to the latest `user_speech` that opened before it (`event_index` running max). That user turn never reached the agent — omit it. Keep `honor_immediate` and `barge_in_honored`: the user was heard (including barge-in). `flag_failed_vad = 1` is the QA subset of those discards (non-empty transcript); for transcripts, filter on the outcome, not only the QA flag.

**Mark interrupted agent speech.** When `flag_agent_interrupted = 1`, the agent was cut off mid-playback. Keep the row and append ` (interrupted)` to the end of that line. Do not drop the turn.

**Line format** (one line per kept turn, chronological by `event_index`):

```
user: <transcript>
agent: <transcript>
agent: <transcript> (interrupted)
```

Use Golden Query 9. Join `fact_ai_agents_voice_sessions` when you also need `id_twilio_call` or dial flags.

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
  AND dt_session_created < DATE {end_date}
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
  AND dt_session_created < DATE {end_date}
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
  AND dt_session_created < DATE {end_date}
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
  AND f.dt_session_created < DATE {end_date}
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
  AND dt_session_created < DATE {end_date}
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
  AND dt_session_created < DATE {end_date}
GROUP BY 1
ORDER BY n_sessions DESC
```

### Query 7 — Reconstruct a voice call timeline

```sql
SELECT
    e.event_index,
    e.event_type,
    e.transcript,
    e.vad_first_decision,
    e.vad_final_outcome,
    e.tool_name,
    e.flag_failed_vad,
    e.flag_agent_interrupted,
    e.ts_started
FROM dw_collection_ai_agents.fact_ai_agents_voice_events AS e
WHERE e.id_langfuse_session = '{id_langfuse_session}'
ORDER BY e.event_index
```

### Query 8 — VAD QA and identity funnel

```sql
-- Failed VAD: discarded user speech that had a transcript
SELECT
    s.id_langfuse_session,
    s.id_twilio_call,
    e.event_index,
    e.transcript,
    e.vad_first_decision,
    e.vad_final_outcome
FROM dw_collection_ai_agents.fact_ai_agents_voice_events AS e
INNER JOIN dw_collection_ai_agents.fact_ai_agents_voice_sessions AS s
    ON s.id_langfuse_session = e.id_langfuse_session
WHERE e.event_type = 'vad'
  AND e.flag_failed_vad = 1
  AND s.year = {year}
  AND s.month = {month}
LIMIT 100
;

-- Identity funnel (deterministic flags on every call)
SELECT
    id_langfuse_session,
    flag_identity_check_triggered,
    n_identity_check_calls,
    flag_identity_check_result
FROM dw_collection_ai_agents.fact_ai_agents_voice_sessions
WHERE flag_identity_check_triggered = 1
  AND year = {year}
  AND month = {month}
LIMIT 100
```

### Query 9 — Reconstruct a voice call transcript

Spoken turns only: drop user utterances the VAD discarded, keep barge-in, mark interrupted agent playback with ` (interrupted)`.

```sql
WITH timeline AS (
    SELECT
        e.id_langfuse_session,
        e.event_index,
        e.event_type,
        e.transcript,
        e.flag_agent_interrupted,
        e.vad_final_outcome,
        MAX(
            CASE
                WHEN e.event_type = 'user_speech' THEN e.event_index
            END
        ) OVER (
            PARTITION BY e.id_langfuse_session
            ORDER BY e.event_index ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_user_event_index
    FROM
        dw_collection_ai_agents.fact_ai_agents_voice_events AS e
    WHERE
        e.id_langfuse_session = '{id_langfuse_session}'
),
ignored_user_turns AS (
    SELECT DISTINCT
        id_langfuse_session,
        last_user_event_index AS event_index
    FROM
        timeline
    WHERE
        event_type = 'vad'
        AND vad_final_outcome = 'backchannel_discarded'
        AND last_user_event_index IS NOT NULL
),
spoken_turns AS (
    SELECT
        t.id_langfuse_session,
        t.event_index,
        CASE
            WHEN t.event_type = 'user_speech'
            THEN CONCAT('user: ', COALESCE(t.transcript, ''))
            WHEN t.flag_agent_interrupted = 1
            THEN CONCAT('agent: ', COALESCE(t.transcript, ''), ' (interrupted)')
            ELSE CONCAT('agent: ', COALESCE(t.transcript, ''))
        END AS line
    FROM
        timeline AS t
    LEFT JOIN
        ignored_user_turns AS ign
            ON ign.id_langfuse_session = t.id_langfuse_session
            AND ign.event_index = t.event_index
    WHERE
        t.event_type IN ('user_speech', 'agent_speech')
        AND ign.event_index IS NULL
)
SELECT
    id_langfuse_session,
    ARRAY_JOIN(
        TRANSFORM(
            ARRAY_SORT(ARRAY_AGG(STRUCT(event_index, line))),
            element -> element.col2
        ),
        '\n'
    ) AS voice_transcript
FROM
    spoken_turns
GROUP BY
    id_langfuse_session
```

### Query 10 — Contract billing facts (Garantia Locatícia / occupancy start / condominium payer)

Session-grain billing facts logged by `get_financial_context_v1` (SeuBarriga `GetContractBillingFacts`). Join `matthew_mcp_observations` — these columns are not on the fact table. Filter `flag_has_rental_guarantee IS NOT NULL` when the lookup must have succeeded; NULL is "not logged", not paga e mora.

```sql
SELECT
    s.dt_session_created,
    s.id_external,
    s.ai_agent_source,
    mo.flag_has_rental_guarantee,
    CASE
        WHEN mo.flag_has_rental_guarantee = 1 THEN 'mora e paga'
        WHEN mo.flag_has_rental_guarantee = 0 THEN 'paga e mora'
    END AS rent_vs_occupancy,
    mo.dt_occupancy_started,
    mo.condominium_payer,
    mo.n_financial_context_calls
FROM datalake_ai_collections_quintoandar.sessions AS s
JOIN datalake_ai_collections_quintoandar.matthew_mcp_observations AS mo
    ON mo.id_langfuse_session = s.id_external
WHERE s.flag_session_with_trace
    AND s.dt_session_created >= DATE '{start_date}'
    AND s.dt_session_created < DATE {end_date}
    AND mo.flag_has_rental_guarantee IS NOT NULL
ORDER BY s.dt_session_created DESC
LIMIT 200
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
