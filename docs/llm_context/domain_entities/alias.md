# Alias — B2B Conversational AI Agent for Partner Agencies

## Ownership

**Data Owner:**
- vitor.musachio@quintoandar.com.br

**Data Steward:**
- lucas.piva@quintoandar.com.br

## Overview

Alias is QuintoAndar's B2B product: a WhatsApp AI agent that partner real-estate agencies (imobiliárias) plug into their inbound flow. It qualifies leads, answers questions about the agency's own property portfolio, schedules visits, escalates to a human when needed, and posts structured outcomes back to the agency's CRM (SIENGE, NAVENT, VISTA, UNIVEN, KENLO, UNIVERSAL) — without human intervention on the most common paths. The agency, not QuintoAndar, owns the demand and the inventory.

The `dw_alias` star schema unifies two analytical worlds: **B2B Ops / Growth** (onboarding, activation, portfolio ingestion, lead volume per agency) and **AI Agent Performance** (conversational funnel, LLM cost/latency, tool errors). It reads Alias OLTP (`datalake_alias_clean`) enriched with Langfuse observability (`datalake_langfuse_clean`) and chatbot session metadata (`datalake_chatbot.sessions`, `bot = 'alias'`), and connects to the partner registry via `sk_broker`.

Lead lifecycle:
1. **Intake** — lead arrives via portal webhook or CRM; a lead + OPEN session + engagement are created (`fact_alias_leads`, `fact_alias_sessions.ts_created`).
2. **Conversation** — WhatsApp chat starts, session goes IN_PROGRESS, `uuid_chat_session` is set and links to Langfuse (`fact_alias_sessions.is_chat_started`, `id_langfuse_session`).
3. **Resolution** — the AI records outcomes; multiple per session allowed (`fact_alias_lead_resolutions.type` ∈ VISIT_INTENTION, ESCALATION, INACTIVE).
4. **CRM export** — resolution posted to the agency CRM (`is_crm_sent`, `ts_sent_to_crm`).
5. **Closure** — expiration reminder closes the session; if no resolution existed, an INACTIVE one is generated (`ts_closed`).

Not every lead reaches every stage: many stop at profiling, some are escalated, some go cold (INACTIVE).

## Glossary and Synonyms

- **Alias**, **agente do Alias**, **agente para imobiliárias**, **produto 40** → the B2B WhatsApp AI agent product. Agencies flagged via `dw_brokers.dim_broker.is_alias_broker = TRUE` (`company_product.id_product = 40`).
- **Imobiliária parceira do Alias**, **broker Alias** → partner agency on Alias → `sk_broker` (FK to `dw_brokers.dim_broker`). "Pure Alias" = product 40 only; "Rede + Alias" = also has product 27/30.
- **Lead** → buyer/renter contact at an agency → `fact_alias_leads` (`sk_lead`). No PII exposed.
- **Sessão / atendimento** → one conversation thread → `fact_alias_sessions` (`sk_lead_session`). Status: OPEN / IN_PROGRESS / CLOSED.
- **Engajamento (engagement)** → inbound touchpoint per channel (IMOVELWEB, ZAP, WhatsApp, UNIVEN) → `fact_alias_sessions.origin_first`, `qt_engagements`.
- **Resolução** → qualified outcome → `fact_alias_lead_resolutions.type`.
- **Intenção de visita** → hot lead wanting a visit → `type = 'VISIT_INTENTION'` / `is_visit_intention`.
- **Escalação / transbordo** → handoff to a human broker → `type = 'ESCALATION'` / `is_escalated`.
- **Lead frio / inativo** → session expired with no prior resolution → `type = 'INACTIVE'`.
- **Ingestão de inventário** → CRM/XML portfolio sync run → `fact_alias_inventory_ingestions`.
- **Synthetic house** → Alias-internal listing ID (`id_synthetic_house` / `sk_listing`). **Not** QuintoAndar's `sk_house`.
- **Sub-agente / tool** → Langfuse observation name (`alias_profile_agentV1`, `alias_inventory_agentV1`, `alias_get_recommendations_by_company`, `alias_schedule_visit_agentV1`, `alias_visit_get_availability`, `alias_register_visit_intention`, `alias_escalation_agentV1`) → `fact_alias_agent_calls.agent_name`.
- **Sessão de teste** → QA/synthetic company sessions → `fact_alias_sessions.is_test = TRUE` (exclude from metrics).

## Tables

| You need... | Use this table |
|-------------|----------------|
| Conversational funnel per session (status, resolution flags, funnel stage, LLM cost/latency, turns) | `dw_alias.fact_alias_sessions` (`fas`) — one row per lead session (`sk_lead_session`). Central fact. Always filter `is_test = FALSE`. |
| Lead-level rollups (session counts, escalation/visit-intention counts, CRM sent, first/last contact) | `dw_alias.fact_alias_leads` (`fal`) — one row per lead (`sk_lead`). |
| Per-resolution outcomes (type, listing, CRM send status) | `dw_alias.fact_alias_lead_resolutions` (`falr`) — one row per resolution (`sk_lead_resolution`). |
| Portfolio ingestion health (created/updated/failed counts, success, duration) | `dw_alias.fact_alias_inventory_ingestions` (`faii`) — one row per ingestion run. |
| Sub-agent / tool performance (cost, latency, errors per Langfuse call) | `dw_alias.fact_alias_agent_calls` (`faac`) — one row per Langfuse AGENT/TOOL observation. Join to sessions via `id_langfuse_session`. |
| WhatsApp agent config per agency (phone, verification, Twilio account) | `dw_alias.dim_alias_ai_agent` (`daa`) — one row per AI agent. Credentials excluded. |
| CRM integration per agency (platform, active flag) | `dw_alias.dim_alias_crm_integration` (`daci`) — one row per integration. Secrets excluded. |
| Portfolio listing attributes (amenities/installations as booleans, lat/lon, status) | `dw_alias.dim_alias_listing` (`dal`) — one row per `sk_listing` (`= id_synthetic_house`). No SCD2. |
| Whether an agency is on Alias / active, and its Alias CRM platform | `dw_brokers.dim_broker` (`is_alias_broker`, `is_alias_active`, `alias_crm_platform`) and `dw_brokers.dim_broker_products` (`crm_platform`, `business_context = 'ALIAS'`) — see `broker_xp.md`. |
| Raw conversation turns / LLM traces backing a session | `datalake_langfuse_clean.traces` / `.observations`, and `datalake_chatbot.sessions` (`bot = 'alias'`) — see `chatbot_sessions.md`. |

**Critical rules:**
- **Always exclude test sessions** — `fact_alias_sessions.is_test = FALSE` (two hardcoded QA/synthetic company UUIDs). Skipping this inflates every funnel/cost metric.
- **`sk_broker` can be NULL** in `dw_alias.*` when the agency isn't yet in `datalake_company_clean.company` / `core_brokers` (pure-Alias agencies depend on the product-40 backfill). Filter `sk_broker IS NOT NULL` when counting real agencies.
- **`sk_broker` joins are VARCHAR-to-VARCHAR** — join `dw_alias.*.sk_broker = dw_brokers.dim_broker.sk_broker` directly with no CAST.
- **`id_synthetic_house` / `sk_listing` is Alias-internal — NOT `dw_house.sk_house`** (0/23 match validated). Join it only to `dim_alias_listing.sk_listing` (87% match with `fact_alias_lead_resolutions`).
- **NULL-by-design columns (not implemented yet):** `full_conversation`, `n_recommendations_shown`, `n_user_turns_until_first_recommendation`, `n_user_turns_until_visit_intent`, `total_input_tokens`, `total_output_tokens` on `fact_alias_sessions`, and `input_tokens` / `output_tokens` on `fact_alias_agent_calls`. Don't build metrics on these.
- **DataHub CI:** list concrete `schema.table` names only — never wildcards.

## Key Metrics

- Session → resolution conversion (`COUNT_IF(is_resolved) / COUNT(*)` on `fact_alias_sessions`)
- Visit intention rate (`COUNT_IF(is_visit_intention) / COUNT(*)`)
- Escalation (human handoff) rate (`COUNT_IF(is_escalated) / COUNT(*)`)
- CRM send rate (`COUNT_IF(is_crm_sent) / COUNT_IF(is_resolved)`)
- Deepest funnel stage distribution (`funnel_stage_deepest`)
- LLM cost per session (`total_llm_cost_usd`) and per turn (`avg_cost_per_turn_usd`)
- LLM latency P50/P95 (`p50_llm_response_time_ms`, `p95_llm_response_time_ms`)
- Tool error volume per sub-agent (`fact_alias_agent_calls.has_error` grouped by `agent_name`)
- Leads per agency (`fact_alias_leads` grouped by `sk_broker`)
- Inventory ingestion success rate (`fact_alias_inventory_ingestions.is_successful`)
- Portfolio size / amenity profile per agency (`dim_alias_listing` grouped by `sk_broker`)
- Active Alias agencies (`dw_brokers.dim_broker.is_alias_active`)

## Relationships with Other Entities

### Broker XP (N:1 — many Alias records per partner agency)

- `dw_alias.<any>.sk_broker = dw_brokers.dim_broker.sk_broker` (VARCHAR join; filter `sk_broker IS NOT NULL`).
- Alias flags live on `dim_broker` (`is_alias_broker`, `is_alias_active`, `alias_crm_platform`) and `dim_broker_products` (`crm_platform`, `business_context = 'ALIAS'`). Full partner model: `broker_xp.md`.

### Chatbot Sessions / Langfuse (1:1 per session — where the conversation lives)

- `fact_alias_sessions.id_langfuse_session = datalake_chatbot.sessions.id_langfuse_session` (`bot = 'alias'`, ~89.6% coverage; NULL for OPEN sessions with no WhatsApp turn).
- Raw turns/LLM: `datalake_langfuse_clean.traces.id_session = fact_alias_sessions.id_langfuse_session`, then `observations.id_trace = traces.id_trace`. Full session/message model: `chatbot_sessions.md`.

### Internal dw_alias star joins

- `fact_alias_sessions.sk_lead = fact_alias_leads.sk_lead` (N:1).
- `fact_alias_lead_resolutions.sk_lead_session = fact_alias_sessions.sk_lead_session` (N:1).
- `fact_alias_agent_calls.id_langfuse_session = fact_alias_sessions.id_langfuse_session` (N:1).
- `fact_alias_lead_resolutions.id_synthetic_house = dim_alias_listing.sk_listing` (N:1, ~87%).
- `dim_alias_ai_agent.sk_broker` / `dim_alias_crm_integration.sk_broker` / `dim_alias_listing.sk_broker` → `sk_broker` (dimensions currently ~1:1 with broker for agent/CRM).

### House domain (no join)

- `id_synthetic_house` does **not** map to `dw_house.dim_house` — do not attempt a house-domain join. See `house_and_listing.md` only for QuintoAndar 1P/3P inventory (a different universe).

## Dos and Don'ts

**Do:**
- Start session-level analysis on `dw_alias.fact_alias_sessions` and always apply `is_test = FALSE`.
- Use the boolean flags (`is_resolved`, `is_visit_intention`, `is_escalated`, `is_crm_sent`) for funnel rates — they encode the resolution logic.
- Use `funnel_stage_deepest` for a single deepest-stage-per-session view (values: `no_agent`, `profile_identified`, `inventory_searched`, `schedule_visit_agent_called`, `visit_attempt_failed`, `escalated`, `visit_intention_registered`).
- Distinguish `has_recommendations` (recommendation tool was *called*) from `has_actual_recommendations` (tool *returned* listings).
- Use `fact_alias_agent_calls` for sub-agent latency/cost/error drill-down; roll up to session via `id_langfuse_session`.
- Join to `dw_brokers.dim_broker` for agency name/state/activity via `fas.sk_broker = b.sk_broker` (VARCHAR, no CAST); filter `sk_broker IS NOT NULL`.

**Don't:**
- Don't treat `id_synthetic_house` / `sk_listing` as `dw_house.sk_house` — they are Alias-internal IDs.
- Don't build metrics on the NULL-by-design columns listed under Critical rules.
- Don't count `sk_broker IS NULL` rows as agencies.
- Don't confuse `origin_first` (Alias intake channel) with `channel` (chatbot WhatsApp channel type).
- Don't use `dim_alias_ai_agent.twilio_phone_number` as lead PII — it is the agency's business WhatsApp config, and lead phone/name/email are intentionally absent from the whole schema.

## Golden Queries

### Query 1 — Conversational funnel per agency (monthly)

Session → resolution → visit-intention / escalation / CRM-sent rates per partner agency, excluding test sessions.

```sql
SELECT
    DATE_TRUNC('month', fas.ts_created)                                   AS month,
    b.broker_name,
    fas.sk_broker,
    COUNT(*)                                                              AS total_sessions,
    COUNT_IF(fas.is_chat_started)                                         AS sessions_with_chat,
    COUNT_IF(fas.is_resolved)                                             AS resolved_sessions,
    COUNT_IF(fas.is_visit_intention)                                      AS visit_intention_sessions,
    COUNT_IF(fas.is_escalated)                                            AS escalated_sessions,
    COUNT_IF(fas.is_crm_sent)                                             AS crm_sent_sessions,
    ROUND(CAST(COUNT_IF(fas.is_resolved) AS DOUBLE) / COUNT(*), 3)        AS resolution_rate,
    ROUND(CAST(COUNT_IF(fas.is_visit_intention) AS DOUBLE) / COUNT(*), 3) AS visit_intention_rate,
    ROUND(CAST(COUNT_IF(fas.is_escalated) AS DOUBLE) / COUNT(*), 3)       AS escalation_rate
FROM dw_alias.fact_alias_sessions AS fas
LEFT JOIN dw_brokers.dim_broker AS b ON fas.sk_broker = b.sk_broker
WHERE fas.is_test = FALSE
  AND fas.ts_created >= TIMESTAMP '{start_date}'
  AND fas.ts_created <  TIMESTAMP '{end_date}'
GROUP BY 1, 2, 3
ORDER BY month DESC, total_sessions DESC
```

### Query 2 — Deepest funnel stage distribution

How far sessions progress through the conversational funnel.

```sql
SELECT
    fas.funnel_stage_deepest,
    COUNT(*)                                                        AS sessions,
    ROUND(CAST(COUNT(*) AS DOUBLE) / SUM(COUNT(*)) OVER (), 3)      AS share
FROM dw_alias.fact_alias_sessions AS fas
WHERE fas.is_test = FALSE
  AND fas.ts_created >= TIMESTAMP '{start_date}'
  AND fas.ts_created <  TIMESTAMP '{end_date}'
GROUP BY fas.funnel_stage_deepest
ORDER BY sessions DESC
```

### Query 3 — Sub-agent cost, latency and error rate

Per-sub-agent performance for the AI Agent Performance view, joined back to session context.

```sql
SELECT
    faac.agent_name,
    COUNT(*)                                              AS calls,
    COUNT(DISTINCT faac.id_langfuse_session)              AS sessions,
    ROUND(AVG(faac.duration_ms), 0)                       AS avg_duration_ms,
    ROUND(SUM(faac.cost_total_usd), 4)                    AS total_cost_usd,
    COUNT_IF(faac.has_error)                              AS error_calls,
    ROUND(CAST(COUNT_IF(faac.has_error) AS DOUBLE) / COUNT(*), 3) AS error_rate
FROM dw_alias.fact_alias_agent_calls AS faac
WHERE faac.ts_started >= TIMESTAMP '{start_date}'
  AND faac.ts_started <  TIMESTAMP '{end_date}'
GROUP BY faac.agent_name
ORDER BY calls DESC
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
