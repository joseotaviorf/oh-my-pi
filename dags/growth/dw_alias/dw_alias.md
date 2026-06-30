# Spec: Alias Data Warehouse — Unified Model

**Status:** Draft  
**Owner:** vitor.musachio@quintoandar.com.br  
**Domain:** Broker XP / Growth  
**Last updated:** 2026-06-25  

---

## 0. Conversation Summary & Business Context

This spec consolidates work that started on branch `feature/alias-obt` (PR #24433) with production Alias OLTP data (`datalake_alias_clean`) and broker coverage in `dw_brokers`. The goal is a single star schema that supports both **B2B Ops / Growth** and **AI agent performance / conversational funnel** analytics.

### What was decided in this conversation

| Topic | Decision |
|---|---|
| Broker coverage | Extend `core_brokers` with product **40 (Alias)**, propagate to `dw_brokers`, join `dw_alias` via **`sk_broker`** — no separate `dim_alias_broker` |
| Alias-only brokers | 25 Alias companies total: **13 pure Alias** (product 40 only) + **12 Rede + Alias**. Pure Alias brokers need Track 1 to get `sk_broker` |
| Address / CRECI / CNPJ | Trino validation: **100% CNPJ**, **92% CRECI**, **80% address** in `datalake_company_clean` — populated via `core_brokers`, not assumed NULL |
| Standalone dimensions | `dim_alias_ai_agent`, `dim_alias_crm_integration`, `dim_alias_listing` |
| Agent call fact | **`fact_alias_agent_calls`** — observation grain (Langfuse AGENT/TOOL call); session roll-ups live in **`fact_alias_sessions`** |
| Key naming | DW PKs/FKs use **`sk_*`** (same value as source UUID where applicable); **`uuid_company`** replaced by **`sk_broker`** in DW outputs |
| `id_property` | Renamed to **`id_synthetic_house`** — Alias internal ID from `listing_fingerprint`, **not** joinable to `dw_house.dim_house` (0/23 match) |
| Fact unification | **`fact_alias_lead_engagements`** merged into **`fact_alias_sessions`** (94.3% of sessions have exactly 1 engagement) |
| Listing dimension | **`dim_alias_listing`** added with inline JSON parsing (Option A: top amenities/installations → booleans, tail → `amenities_other` string); no SCD2 initially |
| OBT gaps | **`fact_alias_agent_calls`** (observation grain, aligned with OBT commit `cc2f148e62`) + full funnel fields in **`fact_alias_sessions`** from Langfuse |
| Langfuse sources | **`datalake_langfuse_clean.observations`** + **`datalake_langfuse_clean.traces`** + **`datalake_chatbot.sessions`** (`bot = 'alias'`) |
| Test sessions | `is_test` via `company_uuid IN ('00000000-0000-4000-8000-000000000001', '31616192-288b-439a-baec-890a5c89e20a')` from OBT commit `cc2f148e62` |
| CRM in `dim_broker` | `alias_crm_platform` / `crm_platform` kept as convenience flags; detailed CRM config lives in **`dim_alias_crm_integration`** |

### Additional business context

**Product:** Alias is QuintoAndar's B2B WhatsApp AI agent for partner real-estate agencies. It qualifies inbound leads, searches the agency's inventory, schedules visits, escalates to humans when needed, and posts structured outcomes back to the agency's CRM (e.g. SIENGE, NAVENT) without manual handling on common paths.

**Core entities (Alias OLTP → clean):**

- **Broker / company** (`brokers`, `ai_agents`, `crm_integrations`) — onboarding, WhatsApp verification, CRM platform
- **Lead funnel** (`leads` → `lead_sessions` → `lead_engagements` → `lead_resolutions`) — one lead can have multiple sessions; resolutions include `VISIT_INTENTION` and `ESCALATION`
- **Inventory** (`inventory_ingestions`, `listing_fingerprint`) — portfolio sync from CRM/XML; listings enriched with `text2filter_prediction` (classifier) and `cached_location` (lat/lon)
- **Conversational layer** — `lead_sessions.uuid_chat_session` links to Copilot/Langfuse via `datalake_chatbot.sessions.id_langfuse_session` (~89.6% match when WhatsApp is active)

**Conversational sub-agents (Langfuse observation names):** profiling (`alias_profile_agentV1`), inventory search (`alias_inventory_agentV1`), recommendations (`alias_get_recommendations_by_company`), scheduling (`alias_schedule_visit_agentV1`), availability (`alias_visit_get_availability`), visit registration (`alias_register_visit_intention`), escalation (`alias_escalation_agentV1`), plus config tool `get_alias_configuration` ( supplies `company_uuid` for broker attribution and `is_test`).

**Implementation tracks:** PR1 `core_brokers` (product 40) → PR2 `dw_brokers` enrichment → PR3 `dw_alias` star schema (can be developed in parallel; runtime depends on `alias` + `company` clean).

---

## 1. Context and Motivation

**Alias** is QuintoAndar's B2B product: a WhatsApp AI agent that qualifies leads for partner agencies, integrates with the agency CRM, and returns structured outcomes without human intervention on the most common flows.

The Alias ingestion pipeline (`dags/growth/alias/alias_declaration.yml`) is already in production, capturing 9 PostgreSQL tables into raw/clean layers. What **does not exist** today is the Alias DW layer, nor `dw_brokers` expansion to include agencies that are Alias-only customers.

### Problem

1. **Incomplete `dw_brokers` coverage:** today only agencies with product 27 (Rede Sale) or 30 (Rede Rent) appear in `dim_broker`. Agencies with product 40 (Alias) are excluded — blocking Alias analyses that cross broker dimensions.

2. **No unified analytical facts:** there is no DW layer to answer B2B Ops questions (onboarding, activation, portfolio ingestion) or AI agent performance questions (conversational funnel, latency, LLM cost). Prior work (`feature/alias-obt`) covered conversational data via Langfuse only, without production Alias service data.

### Goals

- Include all Alias brokers in `dim_broker` with a consistent `sk_broker`.
- Create analytical facts for B2B Ops and agent performance questions.
- Reuse the existing conversational OBT as the base for `fact_alias_sessions`.
- Connect `dw_alias` to `dw_brokers` via `sk_broker`.

### Non-goals

- Change Alias raw/clean layers (already in production).
- Create a separate `dim_alias_broker` — reuse `dw_brokers.dim_broker`.
- Expose lead PII — `uuid_lead` is an opaque FK; no `phone`, `name`, or `email`.

---

## 2. Data Model

### 2.1 Overall diagram

```
                         ┌─────────────────────────────────┐
                         │         dw_brokers               │
                         │  dim_broker  (sk_broker)  ◄──────┼──── core_brokers.brokers
                         │  dim_broker_products              │     (products 27, 30, 40)
                         └──────────────┬──────────────────-┘
                                        │ sk_broker (FK)
                         ┌──────────────▼──────────────────────────────────────┐
                         │                   dw_alias                           │
                         │                                                      │
                         │  dims:                       facts:                  │
                         │  dim_alias_ai_agent     ──►  fact_alias_leads        │
                         │  dim_alias_crm_integration   fact_alias_sessions     │
                         │  dim_alias_listing      ◄─►  fact_alias_lead_resolutions│
                         │                              fact_alias_inventory_ingestions│
                         │                              fact_alias_agent_calls   │
                         │                                (Langfuse per-call)    │
                         │                                (via id_langfuse_session)│
                         └──────────────────────────────────────────────────────┘
```

### 2.2 `dw_brokers.dim_broker` — new Alias fields

| Field | Type | Source | Description |
|---|---|---|---|
| `is_alias_broker` | BOOLEAN | `company_product.id_product = 40` | TRUE if the agency has the Alias product |
| `is_alias_active` | BOOLEAN | `ai_agents.ts_phone_verified IS NOT NULL` | TRUE if the WhatsApp agent is verified and operational |
| `alias_crm_platform` | STRING | `crm_integrations.platform` | Configured CRM platform (e.g. SIENGE, NAVENT) |
| `ts_alias_registered` | TIMESTAMP | `alias_clean.brokers.ts_created` | Alias registration date |

Pure Alias agencies will have **`broker_name_tag`** and **`broker_trade_name_tag`** populated (derived from company name). For `broker_address`, `creci`, and `cnpj`: **100% of 25 Alias agencies have CNPJ**, 92% have CRECI, and 80% have address in `datalake_company_clean` — these fields are populated by the `core_brokers` Spark job via LEFT JOIN to document and address tables. Only the 2–5 agencies without complete registration will have occasional NULLs.

### 2.3 `dw_brokers.dim_broker_products` — new Alias column

| Field | Type | Source | Description |
|---|---|---|---|
| `crm_platform` | STRING | `crm_integrations.platform` | CRM platform for Alias rows (`business_context = 'ALIAS'`); NULL for Rede |

Alias rows will have `commission`, `demand_fee`, `supply_fee`, `platform_fee`, `bank`, `agency_number`, `account_number`, `account_type`, and `tier_name` as **NULL** — not applicable to the Alias product.

### 2.4 `dw_alias` — star schema

#### `fact_alias_leads`

**Grain:** one row per lead (`uuid_lead`). Current lead state at the agency.

| Field | Type | Source |
|---|---|---|
| `sk_lead` | STRING | `uuid_lead` (same value — PK) |
| `sk_broker` | STRING | `CAST(company.id AS VARCHAR)` |
| `qt_sessions_total` | INT | COUNT of `lead_sessions` per `uuid_lead` |
| `qt_sessions_resolved` | INT | COUNT of sessions with at least one `lead_resolution` |
| `qt_sessions_escalated` | INT | COUNT of sessions with resolution type `ESCALATION` |
| `qt_sessions_visit_intention` | INT | COUNT of sessions with resolution type `VISIT_INTENTION` |
| `is_crm_sent` | BOOLEAN | MAX of `lead_resolutions.ts_sent_to_crm IS NOT NULL` |
| `ts_first_contact` | TIMESTAMP | MIN `lead_sessions.ts_created` |
| `ts_last_contact` | TIMESTAMP | MAX `lead_sessions.ts_updated` |
| `dt_first_contact` | DATE | DATE(ts_first_contact) |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `dt_first_contact` |

#### `fact_alias_sessions`

**Grain:** one row per lead session (`uuid_lead_session`). Conversational funnel unit — combines Alias OLTP data with Langfuse OBT conversational metrics.

> **Engagements merged:** `fact_alias_lead_engagements` was **unified** into this table. Trino validation confirmed **94.3%** of sessions have exactly 1 engagement — `origin_first` and `ts_engagement_first` capture the primary entry channel for the vast majority of cases. `qt_engagements` preserves actual cardinality.

> **OBT join:** `lead_sessions.uuid_chat_session` = `datalake_chatbot.sessions.id_langfuse_session` (89.6% match, coverage for the period with active WhatsApp). Unmatched columns remain NULL.

| Field | Type | Source |
|---|---|---|
| — **Keys** — | | |
| `sk_lead_session` | STRING | `uuid_lead_session` (same value — PK) |
| `sk_lead` | STRING | `uuid_lead` (same value — FK to `fact_alias_leads`) |
| `sk_broker` | STRING | via `leads.uuid_company → company.id` |
| `id_langfuse_session` | STRING | `uuid_chat_session` = `chatbot_sessions.id_langfuse_session` — FK to OBT |
| `id_sauron_session` | STRING | `chatbot_sessions.id_sauron_session` — Sauron session |
| — **Status and context (Alias OLTP)** — | | |
| `status` | STRING | `lead_sessions.status` (OPEN / IN_PROGRESS / CLOSED) |
| `origin_first` | STRING | First entry channel for the session (IMOVELWEB, ZAPGROUP, WHATSAPP_DIRECT, ...) |
| `channel` | STRING | `chatbot_sessions.channel` — WhatsApp channel type (distinct from `origin_first`) |
| `ts_engagement_first` | TIMESTAMP | `MIN(lead_engagements.ts_created)` — first entry timestamp |
| `qt_engagements` | INT | COUNT of `lead_engagements` per session (94.3% = 1) |
| `is_resolved` | BOOLEAN | EXISTS `lead_resolutions` for the session |
| `is_escalated` | BOOLEAN | EXISTS resolution type `ESCALATION` |
| `is_visit_intention` | BOOLEAN | EXISTS resolution type `VISIT_INTENTION` |
| `is_crm_sent` | BOOLEAN | EXISTS resolution with `ts_sent_to_crm IS NOT NULL` |
| `is_chat_started` | BOOLEAN | `ts_chat_started IS NOT NULL` |
| `qt_resolutions` | INT | COUNT of `lead_resolutions` |
| — **Bot metadata (OBT)** — | | |
| `bot_version` | STRING | `langfuse_traces.version` — agent version at session time |
| `is_test` | BOOLEAN | `company_uuid IN (test company UUIDs)` — flag to exclude QA sessions |
| — **Conversational funnel flags (OBT — actual names)** — | | |
| `had_profiling` | BOOLEAN | `alias_profile_agentV1` was called in the session |
| `had_inventory` | BOOLEAN | `alias_inventory_agentV1` was called |
| `had_recommendations` | BOOLEAN | `alias_get_recommendations_by_company` was called |
| `had_scheduling` | BOOLEAN | `alias_schedule_visit_agentV1` was called |
| `had_availability` | BOOLEAN | `alias_visit_get_availability` was called |
| `had_visit_registered` | BOOLEAN | `alias_register_visit_intention` was called |
| `had_escalation` | BOOLEAN | `alias_escalation_agentV1` was called |
| `visit_registered_success` | BOOLEAN | output of `alias_register_visit_intention` contains "registered successfully" |
| `escalation_registered_success` | BOOLEAN | output of `alias_register_escalation` contains "escalation registered successfully" |
| `funnel_stage_deepest` | STRING | Deepest stage reached: `no_agent` / `profile_identified` / `inventory_searched` / `schedule_visit_agent_called` / `visit_intention_registered` / `escalated` |
| — **Funnel timestamps (OBT)** — | | |
| `ts_profiling` | TIMESTAMP | `MIN(ts_started)` of `alias_profile_agentV1` |
| `ts_inventory` | TIMESTAMP | `MIN(ts_started)` of `alias_inventory_agentV1` |
| `ts_scheduling` | TIMESTAMP | `MIN(ts_started)` of `alias_schedule_visit_agentV1` |
| `ts_availability` | TIMESTAMP | `MIN(ts_started)` of `alias_visit_get_availability` |
| `ts_visit_registered` | TIMESTAMP | `MIN(ts_started)` of `alias_register_visit_intention` |
| `ts_escalation` | TIMESTAMP | `MIN(ts_started)` of `alias_escalation_agentV1` |
| — **Turn metrics (OBT)** — | | |
| `n_user_turns` | INT | COUNT(DISTINCT traces) per session |
| `n_user_turns_until_first_recommendation` | INT | Number of turns until first recommendation |
| `n_user_turns_until_visit_intent` | INT | Number of turns until visit intention |
| `n_tool_call_errors` | INT | COUNT of tool calls with output containing "error" |
| `n_calls_get_recommendations` | INT | COUNT of calls to `alias_get_recommendations_by_company` |
| `n_calls_get_availability` | INT | COUNT of calls to `alias_visit_get_availability` |
| `n_calls_get_property` | INT | COUNT of calls to `alias_get_property_by_external_id` |
| `n_calls_register_visit` | INT | COUNT of calls to `alias_register_visit_intention` |
| `n_calls_register_escalation` | INT | COUNT of calls to `alias_register_escalation` |
| `n_recommendations_shown` | INT | Number of recommendations shown (HostGraph) |
| — **LLM cost and latency metrics (OBT)** — | | |
| `total_llm_cost_usd` | DECIMAL | Total LLM cost for the session |
| `avg_cost_per_turn_usd` | DECIMAL | `total_llm_cost_usd / n_user_turns` |
| `total_input_tokens` | INT | Total input tokens |
| `total_output_tokens` | INT | Total output tokens |
| `avg_llm_response_time_ms` | DECIMAL | Average LLM response latency |
| `p50_llm_response_time_ms` | DECIMAL | LLM latency P50 |
| `p95_llm_response_time_ms` | DECIMAL | LLM latency P95 |
| — **Full conversation (OBT)** — | | |
| `full_conversation` | STRING | Serialized full conversation (HostGraph JSON) — for NLP analysis |
| — **Timestamps** — | | |
| `ts_created` | TIMESTAMP | `lead_sessions.ts_created` |
| `ts_closed` | TIMESTAMP | `lead_sessions.ts_closed` |
| `ts_first_turn` | TIMESTAMP | `MIN(langfuse_traces.ts_created)` — first Langfuse turn |
| `ts_last_turn` | TIMESTAMP | `MAX(langfuse_traces.ts_created)` — last Langfuse turn |
| `session_wall_duration_min` | DECIMAL | `DATEDIFF(minute, ts_first_turn, ts_last_turn)` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `ts_created` |

#### `fact_alias_lead_resolutions`

**Grain:** one row per resolution (`uuid_lead_resolution`). Qualified outcome per session.

| Field | Type | Source |
|---|---|---|
| `sk_lead_resolution` | STRING | `uuid_lead_resolution` (same value — PK) |
| `sk_lead_session` | STRING | `uuid_lead_session` (same value — FK) |
| `sk_lead` | STRING | `uuid_lead` via `lead_sessions` (FK) |
| `sk_broker` | STRING | via chain |
| `type` | STRING | `lead_resolutions.type` (VISIT_INTENTION, ESCALATION, ...) |
| `id_synthetic_house` | BIGINT | `lead_resolutions.property_id` — `synthetic_house_id` from Alias `listing_fingerprint`. FK to `datalake_alias_clean.listing_fingerprint.id_synthetic_house`. **Not** joinable to `dw_house.dim_house.sk_house` (IDs from Alias internal sequence; validated: 0/23 matches in `dim_house`). |
| `is_sent_to_crm` | BOOLEAN | `ts_sent_to_crm IS NOT NULL` |
| `ts_resolved` | TIMESTAMP | `lead_resolutions.ts_resolved` |
| `ts_sent_to_crm` | TIMESTAMP | `lead_resolutions.ts_sent_to_crm` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `ts_resolved` |

#### `fact_alias_inventory_ingestions`

**Grain:** one row per ingestion run (`uuid_inventory_ingestion`).

| Field | Type | Source |
|---|---|---|
| `sk_inventory_ingestion` | STRING | `uuid_inventory_ingestion` (same value) |
| `sk_broker` | STRING | via `uuid_company → company.id` |
| `status` | STRING | `inventory_ingestions.status` |
| `is_successful` | BOOLEAN | `status = 'COMPLETED'` |
| `quantity_created` | INT | `inventory_ingestions.quantity_created` |
| `quantity_updated` | INT | `inventory_ingestions.quantity_updated` |
| `quantity_failed` | INT | `inventory_ingestions.quantity_failed` |
| `quantity_skipped` | INT | `inventory_ingestions.quantity_skipped` |
| `quantity_unpublished` | INT | `inventory_ingestions.quantity_unpublished` |
| `failure_reason` | STRING | `inventory_ingestions.failure_reason` |
| `duration_minutes` | DECIMAL | `DATEDIFF(MINUTE, ts_started, ts_completed)` |
| `ts_started` | TIMESTAMP | `inventory_ingestions.ts_started` |
| `ts_completed` | TIMESTAMP | `inventory_ingestions.ts_completed` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `ts_started` |

#### `dim_alias_ai_agent`

**Grain:** one row per configured WhatsApp agent. Currently 1:1 with broker; structure supports multiple agents per broker in the future.

> ⚠️ **Exclude credentials:** `twilio_auth_token`, `twilio_api_secret`, `twilio_auth_token_plain`, `twilio_api_secret_plain`, `id_twilio_api_key` must never enter the DW.

| Field | Type | Source |
|---|---|---|
| `sk_ai_agent` | STRING | `uuid_ai_agent` (same value — PK) |
| `sk_broker` | STRING | `CAST(company.id AS VARCHAR)` via `uuid_company` |
| `agent_name` | STRING | `ai_agents.agent_name` |
| `display_name` | STRING | `ai_agents.display_name` — name shown to the lead |
| `phone_number` | STRING | `ai_agents.phone_number` — WhatsApp Business (config, not personal PII) |
| `id_meta_business_portfolio` | STRING | `ai_agents.id_meta_business_portfolio` |
| `id_meta_waba` | STRING | `ai_agents.id_meta_waba` — WhatsApp Business Account ID |
| `id_twilio_sender` | STRING | `ai_agents.id_twilio_sender` |
| `id_twilio_account` | STRING | `ai_agents.id_twilio_account` |
| `id_twilio_messaging_service` | STRING | `ai_agents.id_twilio_messaging_service` |
| `is_carousel_enabled` | BOOLEAN | `ai_agents.is_carousel_enabled` |
| `is_phone_verified` | BOOLEAN | `ts_phone_verified IS NOT NULL` |
| `ts_phone_verified` | TIMESTAMP | `ai_agents.ts_phone_verified` |
| `ts_created` | TIMESTAMP | `ai_agents.ts_created` |
| `ts_updated` | TIMESTAMP | `ai_agents.ts_updated` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `ts_updated` |

#### `dim_alias_crm_integration`

**Grain:** one row per registered CRM integration. 1:1 with broker (validated: 24 companies, 24 distinct).

> ⚠️ **Exclude sensitive credentials/endpoints:** `crm_api_token`, `xml_inventory_url`, `post_lead_url`, `post_direct_lead_url`, `id_crm_broker_account` must never enter the DW.

| Field | Type | Source |
|---|---|---|
| `sk_crm_integration` | STRING | `uuid_crm_integration` (same value — PK) |
| `sk_broker` | STRING | `CAST(company.id AS VARCHAR)` via `uuid_company` |
| `platform` | STRING | `crm_integrations.platform` — e.g. SIENGE, NAVENT |
| `is_active` | BOOLEAN | `crm_integrations.is_active` |
| `ts_ready_gate_sent` | TIMESTAMP | `crm_integrations.ts_ready_gate_sent` — onboarding completed |
| `ts_deactivated` | TIMESTAMP | `crm_integrations.ts_deactivated` |
| `ts_created` | TIMESTAMP | `crm_integrations.ts_created` |
| `ts_updated` | TIMESTAMP | `crm_integrations.ts_updated` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `ts_updated` |

#### `dim_alias_listing`

**Grain:** one row per property in the Alias portfolio (`id_synthetic_house`). Represents inventory registered by the agency via `listing_fingerprint`.

> **Inline JSON parsing:** extraction from JSONB (`text2filter_prediction`, `cached_location`) is done directly in `dim_alias_listing.sql`. An enrich layer may be introduced later if other models need to reuse these fields.

> **Arrays → booleans + STRING (Option A):** `installations` (16 distinct values) and top `amenities` (17 values with ≥ 1,000 listings) become booleans via `array_contains(from_json(...), value)` — BOOLEAN output, no array columns in DW. The 23 tail `amenities` values are serialized as `amenities_other` (pipe-separated STRING) for ad-hoc LIKE filters. Pattern compatible with Databricks DBR and EMR Spark 3.5.

> **No SCD Type 2 (initial phase):** reflects current listing state. Full history is available in `datalake_alias_clean.listing_fingerprint` (CDC captures all changes). SCD2 when volume justifies it.

> **Expected overlap:** `has_elevator` (text classifier, 99% coverage) and `has_building_elevator` (explicit registration from installations, 8.9%) are distinct complementary sources — not redundant.

| Field | Type | Source | Coverage |
|---|---|---|---|
| `sk_listing` | STRING | `CAST(id_synthetic_house AS VARCHAR)` (PK) | 100% |
| `sk_broker` | STRING | `CAST(company.id AS VARCHAR)` via `uuid_company` | ~95% |
| `id_listing_original` | STRING | `listing_fingerprint.id_listing_original` | 100% |
| `status` | STRING | `listing_fingerprint.status` (ACTIVE, INACTIVE, ...) | 100% |
| — **text2filter_prediction (scalar boolean fields)** — | | | |
| `has_elevator` | BOOLEAN | `$.hasElevator` — inferred by text classifier | 99.9% |
| `has_doorman_24h` | BOOLEAN | `$.hasAllDayDoorman` — inferred by classifier | 99.9% |
| `is_furnished` | BOOLEAN | `$.isFurnished` — nullable by classifier design | 17% |
| — **installations (array → 16 booleans via array_contains)** — | | | |
| `has_swimming_pool` | BOOLEAN | `PISCINA` in `$.installations` | 38.2% |
| `has_party_hall` | BOOLEAN | `SALAO_DE_FESTAS` in `$.installations` | 32.7% |
| `has_gym` | BOOLEAN | `ACADEMIA` in `$.installations` | 31.0% |
| `has_playground` | BOOLEAN | `PLAYGROUND` in `$.installations` | 22.6% |
| `has_building_bbq` | BOOLEAN | `CHURRASQUEIRA_NO_PREDIO` in `$.installations` | 21.0% |
| `has_sports_court` | BOOLEAN | `QUADRA_ESPORTIVA` in `$.installations` | 18.7% |
| `has_game_room` | BOOLEAN | `SALAO_DE_JOGOS` in `$.installations` | 18.3% |
| `has_24h_front_desk` | BOOLEAN | `PORTARIA_24H` in `$.installations` (explicit) | 17.3% |
| `has_green_area` | BOOLEAN | `AREA_VERDE` in `$.installations` | 14.4% |
| `has_playroom` | BOOLEAN | `BRINQUEDOTECA` in `$.installations` | 14.0% |
| `has_sauna` | BOOLEAN | `SAUNA` in `$.installations` | 9.4% |
| `has_building_elevator` | BOOLEAN | `ELEVADOR` in `$.installations` (explicit) | 8.9% |
| `has_building_laundry` | BOOLEAN | `LAVANDERIA_NO_PREDIO` in `$.installations` | 3.0% |
| `has_access_ramps` | BOOLEAN | `RAMPAS_DE_ACESSO` in `$.installations` | 0.8% |
| `has_handrails` | BOOLEAN | `CORRIMAO` in `$.installations` | 0.1% |
| `has_tactile_paving` | BOOLEAN | `PISO_TATIL` in `$.installations` | 0.03% |
| — **top amenities (array → 17 booleans, ≥ 1,000 listings)** — | | | |
| `has_balcony` | BOOLEAN | `VARANDA` in `$.amenities` | 27.3% |
| `has_service_area` | BOOLEAN | `AREA_DE_SERVICO` in `$.amenities` | 19.6% |
| `has_kitchen_cabinets` | BOOLEAN | `ARMARIOS_NA_COZINHA` in `$.amenities` | 11.3% |
| `has_unit_bbq` | BOOLEAN | `CHURRASQUEIRA_NO_IMOVEL` in `$.amenities` | 10.5% |
| `has_air_conditioning` | BOOLEAN | `AR_CONDICIONADO` in `$.amenities` | 10.0% |
| `has_bedroom_wardrobes` | BOOLEAN | `ARMARIOS_EMBUTIDOS_NO_QUARTO` in `$.amenities` | 8.9% |
| `has_backyard` | BOOLEAN | `QUINTAL` in `$.amenities` | 7.1% |
| `has_new_or_renovated` | BOOLEAN | `NOVOS_OU_REFORMADOS` in `$.amenities` | 6.5% |
| `has_closet` | BOOLEAN | `CLOSET` in `$.amenities` | 6.0% |
| `has_unobstructed_view` | BOOLEAN | `VISTA_LIVRE` in `$.amenities` | 5.7% |
| `has_garden` | BOOLEAN | `JARDIM` in `$.amenities` | 5.0% |
| `has_private_swimming_pool` | BOOLEAN | `PISCINA_PRIVATIVA` in `$.amenities` | 4.9% |
| `has_penthouse` | BOOLEAN | `APARTAMENTO_COBERTURA` in `$.amenities` | 4.7% |
| `has_open_kitchen` | BOOLEAN | `COZINHA_AMERICANA` in `$.amenities` | 4.6% |
| `has_home_office` | BOOLEAN | `HOME_OFFICE` in `$.amenities` | 3.7% |
| `has_quiet_street` | BOOLEAN | `RUA_SILENCIOSA` in `$.amenities` | 3.6% |
| `has_bathroom_cabinets` | BOOLEAN | `ARMARIOS_NOS_BANHEIROS` in `$.amenities` | 3.4% |
| — **tail amenities (23 values < 1,000 listings → STRING)** — | | | |
| `amenities_other` | STRING | `array_join(from_json($.amenities), '\|')` — values not covered by flags above | ad-hoc |
| — **cached_location** — | | | |
| `lat` | DOUBLE | `GET_JSON_OBJECT(cached_location, '$.lat')` | 99.9% |
| `lon` | DOUBLE | `GET_JSON_OBJECT(cached_location, '$.lon')` | 99.9% |
| — **timestamps** — | | | |
| `ts_last_update` | TIMESTAMP | `listing_fingerprint.ts_last_update` | |
| `ts_created` | TIMESTAMP | `listing_fingerprint.ts_created` | |
| `ts_updated` | TIMESTAMP | `listing_fingerprint.ts_updated` | |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — pipeline load timestamp | |
| `year` / `month` / `day` | INT | Partitioned by `ts_updated` | |

**Fact FK:** `fact_alias_lead_resolutions.id_synthetic_house` → `dim_alias_listing.sk_listing` (87% match — validated via Trino).

#### `fact_alias_agent_calls`

**Grain:** one row per AGENT/TOOL observation in Langfuse. Supports latency, cost, and error analysis per sub-agent — fine granularity kept out of `fact_alias_sessions` (session-level aggregation).

> **Modeled as a fact:** metrics (`duration_ms`, `cost_*_usd`) are additive at observation grain. Join to **`fact_alias_sessions`** via `id_langfuse_session` for session context (1:N).

> **Source:** `datalake_langfuse_clean.observations` + `datalake_langfuse_clean.traces` + `datalake_chatbot.sessions` — same lineage as OBT `fact_alias_agent_calls` (commit `cc2f148e62`).

| Field | Type | Source |
|---|---|---|
| — **Keys** — | | |
| `sk_agent_call` | STRING | `id_observation` (PK — Langfuse observation ID) |
| `id_langfuse_session` | STRING | trace `id_session` — FK to `fact_alias_sessions` |
| `id_trace` | STRING | `id_trace` — groups all observations in one turn |
| `sk_broker` | STRING | via `company_uuid → company.id` |
| — **Agent attributes** — | | |
| `agent_name` | STRING | observation `name` (e.g. `alias_profile_agentV1`, `alias_inventory_agentV1`, ...) |
| `observation_type` | STRING | observation `type`: `AGENT` / `TOOL` |
| `is_tool_call` | BOOLEAN | `observation_type = 'TOOL'` |
| `turn_number` | INT | Turn number for this observation (via `ROW_NUMBER` per trace) |
| — **Performance metrics** — | | |
| `duration_ms` | DOUBLE | Call duration in milliseconds |
| `cost_input_usd` | DOUBLE | Input token cost |
| `cost_output_usd` | DOUBLE | Output token cost |
| `cost_total_usd` | DOUBLE | `cost_input_usd + cost_output_usd` |
| `input_tokens` | INT | Input tokens consumed |
| `output_tokens` | INT | Output tokens generated |
| — **Outcome** — | | |
| `had_error` | BOOLEAN | Output contains "error" or error status |
| `error_message` | STRING | Error message extracted from output (NULL if no error) |
| — **Timestamp** — | | |
| `dt_session` | DATE | Session date — for partitioning and fast joins |
| `ts_started` | TIMESTAMP | observation `ts_started` |
| `ts_ended` | TIMESTAMP | observation `ts_ended` |
| `ts_load` | TIMESTAMP | `CURRENT_TIMESTAMP` — load timestamp |
| `year` / `month` / `day` | INT | Partitioned by `dt_session` |

---

## 3. Architecture and Lineage

```
PostgreSQL (Alias)
    │
    ▼
datalake_alias_raw.*              (CDC — alias_declaration.yml — already in prod)
    │
    ▼
datalake_alias_clean.*            (clean — alias_declaration.yml — already in prod)
    │
    ├────────────────────────────────┬────────────────────────────────────────┐
    │                                │                                        │
    ▼                                ▼                                        ▼
datalake_company_clean.*    core_brokers.brokers              datalake_chatbot.sessions
(company, company_product)  core_brokers.brokers_product      (id_langfuse_session)
  products 27 + 30 + 40     (Track 1)
    │                              │
    │                              ▼
    │                        dw_brokers.dim_broker             (Track 2)
    │                        dw_brokers.dim_broker_products
    │                        [+Alias enrichment via JOIN]
    │                              │
    │                              │ sk_broker
    │                              ▼
    └──────────────────────► dw_alias.*                         (Track 3)
                               dim_alias_ai_agent
                               dim_alias_crm_integration
                               dim_alias_listing  ◄── listing_fingerprint
                                   (JSON parsing inline)        (GET_JSON_OBJECT)
                               fact_alias_agent_calls  ◄── datalake_langfuse_clean
                                   (per Langfuse observation)   (observations + traces)
                               fact_alias_leads
                               fact_alias_sessions  ◄── OBT reused
                               fact_alias_lead_resolutions
                               fact_alias_inventory_ingestions
```

---

## 4. Implementation Plan

### Track 1 — `core_brokers`: expand to product 40

**Files to modify:**

**`dags/core/core_brokers/spark_jobs/load_core_brokers.py`**
- Method `_process_company_product`: change filter from `isin([27, 30])` to `isin([27, 30, 40])`
- Effect: agencies with product 40 only pass the INNER JOIN in `_join_all_data` and enter `core_brokers.brokers`
- All `is_3p_*` flags remain correct — internal logic tests products 27/30 specifically

**`dags/core/core_brokers/spark_jobs/load_core_brokers_product.py`**
- Method `_process_company_product`: change filter from `isin([27, 30])` to `isin([27, 30, 40])`
- Method `_select_final_columns`: add `.when(col("cp.id_product") == 40, lit("ALIAS"))` to `business_context`
- Fee/banking/tier columns will be `NULL` for product 40 due to missing entries in `revenue_share`, `banking_information`, and `tier` from `company_clean`

**Expected outcome:**
- `core_brokers.brokers`: +13 pure Alias agencies (12 with Rede were already present); total: 25 Alias
- `core_brokers.brokers_product`: +25 rows with `business_context = 'ALIAS'`, fees/banking/tier = NULL

**Tests to write:**
- Unit test in `CoreBrokersSparkJob`: company with product 40 only must appear in output
- Unit test in `CoreBrokersProductSparkJob`: `business_context` must be `'ALIAS'` for `id_product = 40`
- Unit test: `is_3p_*` flags must be `FALSE` for company with product 40 only

---

### Track 2 — `dw_brokers`: Alias enrichment via JOIN

**Files to modify:**

**`dags/broker_xp/dw_brokers/queries/dw/dim_broker.sql`**
- Add `alias_data` CTE with JOIN to `datalake_alias_clean.ai_agents`, `crm_integrations`, and `brokers`
- `LEFT JOIN alias_data AS ad ON cb.uuid_company = ad.uuid_company` in final SELECT
- 4 new columns: `is_alias_broker`, `is_alias_active`, `alias_crm_platform`, `ts_alias_registered`
- Spine remains `core_brokers.brokers` — no UNION; Alias agencies arrive via Track 1

```sql
-- Alias enrichment CTE: spine from core_brokers.brokers_product
-- (product 40 available after Track 1); additional JOINs bring operational
-- attributes not present in core_brokers
alias_data AS (
  SELECT
    cbp.uuid_company,
    TRUE                                        AS is_alias_broker,
    aai.ts_phone_verified IS NOT NULL           AS is_alias_active,
    aci.platform                                AS alias_crm_platform,
    ab.ts_created                               AS ts_alias_registered
  FROM core_brokers.brokers_product AS cbp
  LEFT JOIN datalake_alias_clean.ai_agents       AS aai ON cbp.uuid_company = aai.uuid_company
  LEFT JOIN datalake_alias_clean.crm_integrations AS aci ON cbp.uuid_company = aci.uuid_company
  LEFT JOIN datalake_alias_clean.brokers          AS ab  ON cbp.uuid_company = ab.uuid_company
  WHERE cbp.business_context = 'ALIAS'
)
```

**`dags/broker_xp/dw_brokers/queries/dw/dim_broker_products.sql`**
- Add `crm_platform` via LEFT JOIN to `datalake_alias_clean.crm_integrations`
- Join condition: `cbp.uuid_company = aci.uuid_company AND cbp.business_context = 'ALIAS'`
- Rede rows: `crm_platform = NULL`; Alias rows: `crm_platform = aci.platform`

> `core_brokers.brokers_product` exposes `uuid_company` (confirmed in code) and `business_context` — sufficient for JOIN without `id_product`.

**`dags/broker_xp/dw_brokers/metadata/dw/dim_broker.yml`**
- Update `description` to include Alias coverage
- Add 4 columns with `lineage` and `description`

**`dags/broker_xp/dw_brokers/metadata/dw/dim_broker_products.yml`**
- Update `description` to include Alias product
- Add `crm_platform` column with `lineage` and `description`

---

### Track 3 — `dw_alias`: new star schema DAG

**DAG location:** `dags/growth/alias/` (co-located with CDC pipeline)  
**New file:** `dags/growth/alias/dw_alias_declaration.yml`  
**Type:** `query_delta` / `layer: dw`  

**Files to create:**

```
dags/growth/alias/
├── dw_alias_declaration.yml
├── queries/
│   └── dw/
│       ├── dim_alias_ai_agent.sql
│       ├── dim_alias_crm_integration.sql
│       ├── dim_alias_listing.sql            ← inline JSON parsing from listing_fingerprint
│       ├── fact_alias_agent_calls.sql        ← Langfuse observations (per AGENT/TOOL call)
│       ├── fact_alias_leads.sql
│       ├── fact_alias_sessions.sql          ← engagements + unified conversational OBT
│       ├── fact_alias_lead_resolutions.sql
│       └── fact_alias_inventory_ingestions.sql
└── metadata/
    └── dw/
        ├── dim_alias_ai_agent.yml
        ├── dim_alias_crm_integration.yml
        ├── dim_alias_listing.yml
        ├── fact_alias_agent_calls.yml
        ├── fact_alias_leads.yml
        ├── fact_alias_sessions.yml
        ├── fact_alias_lead_resolutions.yml
        └── fact_alias_inventory_ingestions.yml
```

**Template `dim_alias_listing.sql`:**
```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
),
parsed AS (
  SELECT
    lf.uuid_company,
    lf.id_listing_original,
    lf.id_synthetic_house,
    lf.status,
    -- text2filter_prediction — scalar boolean fields
    CAST(GET_JSON_OBJECT(lf.text2filter_prediction, '$.hasElevator')       AS BOOLEAN) AS has_elevator,
    CAST(GET_JSON_OBJECT(lf.text2filter_prediction, '$.hasAllDayDoorman')  AS BOOLEAN) AS has_doorman_24h,
    CAST(GET_JSON_OBJECT(lf.text2filter_prediction, '$.isFurnished')       AS BOOLEAN) AS is_furnished,
    -- installations: 16 values → booleans (source enum values remain PT)
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'PISCINA')                  AS has_swimming_pool,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'SALAO_DE_FESTAS')          AS has_party_hall,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'ACADEMIA')                 AS has_gym,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'PLAYGROUND')               AS has_playground,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'CHURRASQUEIRA_NO_PREDIO')   AS has_building_bbq,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'QUADRA_ESPORTIVA')          AS has_sports_court,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'SALAO_DE_JOGOS')            AS has_game_room,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'PORTARIA_24H')              AS has_24h_front_desk,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'AREA_VERDE')                AS has_green_area,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'BRINQUEDOTECA')             AS has_playroom,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'SAUNA')                    AS has_sauna,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'ELEVADOR')                 AS has_building_elevator,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'LAVANDERIA_NO_PREDIO')      AS has_building_laundry,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'RAMPAS_DE_ACESSO')          AS has_access_ramps,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'CORRIMAO')                 AS has_handrails,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.installations'), 'ARRAY<STRING>'), 'PISO_TATIL')               AS has_tactile_paving,
    -- top amenities (≥ 1,000 listings) → booleans
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'VARANDA')                      AS has_balcony,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'AREA_DE_SERVICO')              AS has_service_area,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'ARMARIOS_NA_COZINHA')          AS has_kitchen_cabinets,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'CHURRASQUEIRA_NO_IMOVEL')      AS has_unit_bbq,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'AR_CONDICIONADO')              AS has_air_conditioning,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'ARMARIOS_EMBUTIDOS_NO_QUARTO') AS has_bedroom_wardrobes,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'QUINTAL')                      AS has_backyard,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'NOVOS_OU_REFORMADOS')          AS has_new_or_renovated,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'CLOSET')                       AS has_closet,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'VISTA_LIVRE')                  AS has_unobstructed_view,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'JARDIM')                       AS has_garden,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'PISCINA_PRIVATIVA')            AS has_private_swimming_pool,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'APARTAMENTO_COBERTURA')        AS has_penthouse,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'COZINHA_AMERICANA')            AS has_open_kitchen,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'HOME_OFFICE')                  AS has_home_office,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'RUA_SILENCIOSA')               AS has_quiet_street,
    array_contains(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), 'ARMARIOS_NOS_BANHEIROS')       AS has_bathroom_cabinets,
    -- tail amenities (23 values < 1,000) → pipe-separated STRING
    array_join(from_json(GET_JSON_OBJECT(lf.text2filter_prediction, '$.amenities'), 'ARRAY<STRING>'), '|') AS amenities_other,
    -- cached_location
    CAST(GET_JSON_OBJECT(lf.cached_location, '$.lat') AS DOUBLE)           AS lat,
    CAST(GET_JSON_OBJECT(lf.cached_location, '$.lon') AS DOUBLE)           AS lon,
    lf.ts_last_update,
    lf.ts_created,
    lf.ts_updated,
    lf.year,
    lf.month,
    lf.day
  FROM datalake_alias_clean.listing_fingerprint AS lf
  WHERE {load_start_date} <= lf.ts_updated
    AND lf.ts_updated < {load_end_date}
)

SELECT
  CAST(p.id_synthetic_house AS VARCHAR) AS sk_listing,
  bm.sk_broker,
  p.id_listing_original,
  p.status,
  p.has_elevator,
  p.has_doorman_24h,
  p.is_furnished,
  p.has_swimming_pool,
  p.has_party_hall,
  p.has_gym,
  p.has_playground,
  p.has_building_bbq,
  p.has_sports_court,
  p.has_game_room,
  p.has_24h_front_desk,
  p.has_green_area,
  p.has_playroom,
  p.has_sauna,
  p.has_building_elevator,
  p.has_building_laundry,
  p.has_access_ramps,
  p.has_handrails,
  p.has_tactile_paving,
  p.has_balcony,
  p.has_service_area,
  p.has_kitchen_cabinets,
  p.has_unit_bbq,
  p.has_air_conditioning,
  p.has_bedroom_wardrobes,
  p.has_backyard,
  p.has_new_or_renovated,
  p.has_closet,
  p.has_unobstructed_view,
  p.has_garden,
  p.has_private_swimming_pool,
  p.has_penthouse,
  p.has_open_kitchen,
  p.has_home_office,
  p.has_quiet_street,
  p.has_bathroom_cabinets,
  p.amenities_other,
  p.lat,
  p.lon,
  p.ts_last_update,
  p.ts_created,
  p.ts_updated,
  CURRENT_TIMESTAMP()                   AS ts_load,
  p.year,
  p.month,
  p.day
FROM parsed AS p
LEFT JOIN broker_map AS bm ON p.uuid_company = bm.uuid_company
```

**`sk_broker` derivation in all facts:**
```sql
CAST(cc.id AS VARCHAR) AS sk_broker
-- via: LEFT JOIN datalake_company_clean.company AS cc
--        ON src.uuid_company = cc.uuid_company
```

**Conversational join in `fact_alias_sessions`:**
```sql
-- lead_sessions.uuid_chat_session = chatbot_sessions.id_langfuse_session (89.6% match)
LEFT JOIN datalake_chatbot.sessions AS cs
  ON CAST(ls.uuid_chat_session AS VARCHAR) = CAST(cs.id_langfuse_session AS VARCHAR)
```

**Reuse of existing OBT (`dw_alias.fact_alias_sessions` from PR #24433):**
- OBT computed LLM metrics (cost, tokens, latency) and funnel flags per `id_langfuse_session`
- Reused via JOIN in `fact_alias_sessions` using `cs.id_langfuse_session`
- No need to recreate Langfuse logic — only the JOIN and unification with Alias OLTP

---

## 5. Dependencies and Execution Order

### Airflow (production)

```
alias                 → datalake_alias_clean.*
company               → datalake_company_clean.*
core_brokers          → core_brokers.* (Track 1)
dw_brokers            → dw_brokers.*   (Track 2, after core_brokers)
dw_alias              → dw_alias.*     (Track 3, after dw_brokers and alias)
```

Track 3 can be **developed in parallel** with Tracks 1 and 2 — `sk_broker` is computed via JOIN to `company_clean` in the fact SQLs themselves, without requiring `dw_brokers` to run first. The dependency is runtime-only in Airflow.

### PR order

| PR | Content | Depends on |
|---|---|---|
| PR 1 | Track 1: `core_brokers` Spark jobs + unit tests | — |
| PR 2 | Track 2: `dw_brokers` SQL + metadata | PR 1 merged and run in Forno |
| PR 3 | Track 3: `dw_alias` declaration + SQLs + metadata | PR 1 (`sk_broker` available via company_clean) |

---

## 6. Pre-implementation Validations (already executed)

| Check | Result | Implication |
|---|---|---|
| `crm_integrations` cardinality per company | 24 rows, 24 distinct → 1:1 | Direct JOIN without deduplication |
| `company_product` with product 40 | 25 distinct companies | Full Alias broker coverage |
| `company.ts_created/ts_updated` | Present | Source for `ts_product_created/updated` on Alias rows |
| `company_product` schema | No own `ts_created/ts_updated` | Use `company.ts_*` (same source as `core_brokers`) |
| `uuid_chat_session → id_langfuse_session` | 89.6% match (period with active WhatsApp) | Valid join for conversational enrichment |
| Alias brokers without product 27/30 | 13 of 25 (pure Alias) | These 13 need Track 1 to get `sk_broker` |
| `sk_broker` formula | `CAST(company.id AS VARCHAR)` | Identical to Spark job — no collision risk |
| Address coverage for Alias agencies | 20/25 (80%) | `broker_address` populated for 80%; NULLs are exception, not rule |
| CNPJ coverage for Alias agencies | 25/25 (100%) | `cnpj` populated for all; columns will not be NULL for Alias |
| CRECI coverage for Alias agencies | 23/25 (92%) | `creci` populated for 92% |
| `id_property` type in `lead_resolutions` | Integer (`looks_like_integer = true`), range 1–10 digits | Alias `synthetic_house_id` (`listing_fingerprint`) — internal sequence |
| `id_property` vs `dw_house.dim_house.sk_house` | 0 of 23 distinct IDs found in `dim_house` | **Not** QuintoAndar `sk_house` — distinct IDs; renamed to `id_synthetic_house` |
| `id_property` vs `datalake_alias_clean.listing_fingerprint` | `property_id` in raw = `synthetic_house_id` (doc `alias.md`) | Valid FK to `listing_fingerprint.id_synthetic_house` within Alias domain |
| `lead_engagements` cardinality per session | 94.3% of sessions have exactly 1 engagement | `fact_alias_lead_engagements` unified into `fact_alias_sessions` via `origin_first` + `qt_engagements` |
| `text2filter_prediction` coverage in `listing_fingerprint` | 29,905/29,925 (99.9%) | `has_elevator`, `has_doorman_24h` populated for almost all listings |
| `isFurnished` field in `text2filter_prediction` | 5,010/29,925 (17%) | Nullable by design — NULL = "not inferred by classification service" |
| `cached_location` coverage in `listing_fingerprint` | 29,924/29,925 (99.9%) | `lat`/`lon` available for almost all |
| `cached_location` content | Only `lat` and `lon` — no `regionId`, `address`, `city` | Partial geocoding; future enrichment via reverse geocoding |

---

## 7. Business Questions Answered

### B2B Ops / Growth

| Question | Table(s) |
|---|---|
| How many agencies are active on Alias? | `dim_broker` (`is_alias_active`) |
| What is the most common CRM platform among Alias brokers? | `dim_broker_products` (`crm_platform`) |
| How many agencies have successful portfolio ingestion? | `fact_alias_inventory_ingestions` |
| What is the activation rate (onboarding → WhatsApp verified)? | `dim_broker` + `ts_alias_registered` vs `is_alias_active` |
| How many leads were received per agency? | `fact_alias_leads` GROUP BY `sk_broker` |
| What is the most common lead entry channel? | `fact_alias_sessions` (`origin_first`) |
| What is portfolio size per agency? | `dim_alias_listing` GROUP BY `sk_broker` |
| What % of listings have elevator / doorman / furnished? | `dim_alias_listing` (`has_elevator`, `has_doorman_24h`, `is_furnished`) |
| What is the geographic distribution of the portfolio? | `dim_alias_listing` (`lat`, `lon`) |
| What is the profile of listings that generate visit intention? | `fact_alias_lead_resolutions` JOIN `dim_alias_listing` |

### AI Agent Performance / Conversational Funnel

| Question | Table(s) |
|---|---|
| What is the session → resolution conversion rate? | `fact_alias_sessions` (`is_resolved`) |
| What is the visit intention rate? | `fact_alias_sessions` (`is_visit_intention`) |
| What is the escalation (human) rate? | `fact_alias_sessions` (`is_escalated`) |
| What is average LLM cost per session per agency? | `fact_alias_sessions` JOIN `dim_broker` |
| How long does a session last until resolution? | `fact_alias_sessions` (`ts_closed - ts_created`) |
| What is the CRM send rate after resolution? | `fact_alias_lead_resolutions` (`is_sent_to_crm`) |
| Which sub-agent has highest latency or error rate? | `fact_alias_agent_calls` GROUP BY `agent_name` |
| How many turns until first recommendation or visit intent? | `fact_alias_sessions` (`n_user_turns_until_*`) |

---

## 8. Acceptance Criteria

### Track 1

- [ ] `core_brokers.brokers` contains all 25 agencies with product 40
- [ ] `core_brokers.brokers_product` contains 25 Alias rows with `business_context = 'ALIAS'`
- [ ] Pure Alias agencies have `is_3p_rent_broker = FALSE` and `is_3p_sale_broker = FALSE`
- [ ] Rede + Alias agencies keep all 3P flags and fees unchanged
- [ ] Unit tests passing for `CoreBrokersSparkJob` and `CoreBrokersProductSparkJob`
- [ ] DAG `core_brokers` runs successfully in Forno

### Track 2

- [ ] `dw_brokers.dim_broker` contains all 25 Alias agencies
- [ ] `is_alias_broker = TRUE` for all 25
- [ ] `is_alias_active` correctly reflects `ts_phone_verified IS NOT NULL`
- [ ] `dw_brokers.dim_broker_products` contains 25 Alias rows with `business_context = 'ALIAS'`
- [ ] `crm_platform` populated for Alias rows, NULL for Rede
- [ ] Existing Rede rows: zero value changes
- [ ] DAG `dw_brokers` runs successfully in Forno

### Track 3

**`fact_alias_sessions`**
- [ ] `sk_broker` non-null for ≥ 99% of sessions with `uuid_company` of a known agency
- [ ] Conversational join (`id_langfuse_session`) present in ≥ 85% of `IN_PROGRESS`/`CLOSED` sessions with non-null `uuid_chat_session`
- [ ] `bot_version` non-null for all sessions with non-null `id_langfuse_session`
- [ ] `is_test` correctly flagged for test company UUIDs (see Section 0)
- [ ] `funnel_stage_deepest` non-null for sessions with at least one sub-agent called
- [ ] `had_visit_registered` = TRUE implies `visit_registered_success IN (TRUE, FALSE)` — no logical NULLs
- [ ] `n_user_turns` ≥ 1 for sessions with non-null `id_langfuse_session`
- [ ] `p95_llm_response_time_ms` > `avg_llm_response_time_ms` — latency distribution sanity check

**`fact_alias_lead_resolutions`**
- [ ] Contains at least one resolution for sessions marked `is_resolved = TRUE` in `fact_alias_sessions`

**`fact_alias_inventory_ingestions`**
- [ ] `is_successful` = TRUE only when `status = 'COMPLETED'`

**`dim_alias_listing`**
- [ ] Contains records for ≥ 99% of `listing_fingerprint` with `id_synthetic_house IS NOT NULL`
- [ ] `has_elevator` and `has_doorman_24h` populated for ≥ 99% of rows with `text2filter_prediction IS NOT NULL`
- [ ] `lat` and `lon` populated for ≥ 99% of rows with `cached_location IS NOT NULL`
- [ ] `sk_broker` non-null for ≥ 95% of rows

**`fact_alias_agent_calls`**
- [ ] One row per `id_observation` — no duplicates
- [ ] All rows have `id_langfuse_session` — no orphan observations
- [ ] `agent_name` contains only known values (no unexpected NULLs)
- [ ] `cost_total_usd` = `cost_input_usd + cost_output_usd` for 100% of rows with non-null cost
- [ ] `had_error = TRUE` only when `error_message IS NOT NULL`
- [ ] `fact_alias_agent_calls.id_langfuse_session` has ≥ 95% match with `fact_alias_sessions.id_langfuse_session`

**General**
- [ ] Metadata YAMLs pass `make validate-metadata-files-exist` and `make validate-metadata-files-content`
- [ ] DAG `dw_alias` runs successfully in Forno

---

## 9. Reference SQL by Table

> Spark SQL templates for each `dw_alias` `.sql` file. Parameters `{load_start_date}` / `{load_end_date}` are injected by the DAG Builder. `dim_alias_listing.sql` is already documented in Section 4.3 (Track 3).
>
> **Confirmed Langfuse tables** (commit `cc2f148e62` — `feature/alias-obt`):
> - `datalake_langfuse_clean.observations` — one row per AGENT/TOOL call; fields: `id_observation`, `id_trace`, `name`, `type`, `output`, `ts_started`, `ts_ended`, `cost_details` (ROW type).
> - `datalake_langfuse_clean.traces` — one row per user turn; fields: `id_trace`, `id_session`, `ts_created`, `version`, `id_project`.
> - `datalake_chatbot.sessions` — cross-host unified sessions; filter with `bot = 'alias'`; `full_conversation` = HostGraph JSON.

---

### `dim_alias_ai_agent.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  aai.uuid_ai_agent                           AS sk_ai_agent,
  bm.sk_broker,
  aai.agent_name,
  aai.display_name,
  aai.twilio_account_sid,
  aai.twilio_phone_number,
  aai.ts_phone_verified IS NOT NULL           AS is_phone_verified,
  -- Excluded: twilio_auth_token, twilio_api_secret, twilio_auth_token_plain,
  --            twilio_api_secret_plain, id_twilio_api_key (sensitive credentials)
  aai.ts_phone_verified,
  aai.ts_created,
  aai.ts_updated,
  CURRENT_TIMESTAMP()                         AS ts_load,
  YEAR(aai.ts_updated)                        AS year,
  MONTH(aai.ts_updated)                       AS month,
  DAY(aai.ts_updated)                         AS day
FROM datalake_alias_clean.ai_agents AS aai
LEFT JOIN broker_map AS bm ON aai.uuid_company = bm.uuid_company
WHERE {load_start_date} <= aai.ts_updated
  AND aai.ts_updated < {load_end_date}
```

---

### `dim_alias_crm_integration.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  aci.uuid_crm_integration                    AS sk_crm_integration,
  bm.sk_broker,
  aci.platform,
  aci.is_active,
  -- Excluded: access_token, client_secret, api_key, webhook_secret (sensitive credentials)
  aci.ts_created,
  aci.ts_updated,
  CURRENT_TIMESTAMP()                         AS ts_load,
  YEAR(aci.ts_updated)                        AS year,
  MONTH(aci.ts_updated)                       AS month,
  DAY(aci.ts_updated)                         AS day
FROM datalake_alias_clean.crm_integrations AS aci
LEFT JOIN broker_map AS bm ON aci.uuid_company = bm.uuid_company
WHERE {load_start_date} <= aci.ts_updated
  AND aci.ts_updated < {load_end_date}
```

---

### `fact_alias_agent_calls.sql`

```sql
-- Source: datalake_langfuse_clean.observations + datalake_langfuse_clean.traces
--        + datalake_chatbot.sessions (confirmed in commit cc2f148e62 — feature/alias-obt)
-- cost_details is a ROW type (access as struct field, not JSON).
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
),
traces_ordered AS (
  -- turn_number: chronological trace position within the session
  SELECT
    t.id_session   AS id_langfuse_session,
    t.id_trace,
    ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY t.ts_created) AS turn_number
  FROM datalake_langfuse_clean.traces AS t
  INNER JOIN datalake_chatbot.sessions AS s ON t.id_session = s.id_langfuse_session
  WHERE s.bot = 'alias'
    AND t.id_session IS NOT NULL
    AND t.ts_created >= '{load_start_date}'
),
broker_config AS (
  -- company_uuid extracted from get_alias_configuration tool output (first call in session)
  SELECT
    t.id_session AS id_langfuse_session,
    COALESCE(
      JSON_EXTRACT_SCALAR(o.output, '$.companyUuid'),
      JSON_EXTRACT_SCALAR(o.output, '$.companyUUID')
    ) AS company_uuid,
    ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY o.ts_started) AS rn
  FROM datalake_langfuse_clean.observations AS o
  INNER JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
  WHERE o.name = 'get_alias_configuration'
    AND o.type = 'TOOL'
    AND t.id_session IS NOT NULL
    AND t.ts_created >= '{load_start_date}'
),
obs_numbered AS (
  SELECT
    o.id_observation                                                AS sk_agent_call,
    tr.id_langfuse_session,
    o.id_trace,
    bc.company_uuid,
    o.name                                                          AS agent_name,
    o.type                                                          AS observation_type,
    o.type = 'TOOL'                                                 AS is_tool_call,
    tr.turn_number,
    CAST(DATE_DIFF('millisecond', o.ts_started, o.ts_ended) AS DOUBLE) AS duration_ms,
    TRY_CAST(cost_details.input  AS DOUBLE)                         AS cost_input_usd,
    TRY_CAST(cost_details.output AS DOUBLE)                         AS cost_output_usd,
    TRY_CAST(cost_details.total  AS DOUBLE)                         AS cost_total_usd,
    NULL                                                            AS input_tokens,  -- not available in observations
    NULL                                                            AS output_tokens, -- not available in observations
    LOWER(COALESCE(o.output, '')) LIKE '%error%'                    AS had_error,
    CASE WHEN LOWER(COALESCE(o.output, '')) LIKE '%error%'
         THEN o.output END                                          AS error_message,
    DATE(s.ts_created)                                              AS dt_session,
    o.ts_started,
    o.ts_ended
  FROM datalake_langfuse_clean.observations AS o
  INNER JOIN traces_ordered AS tr ON o.id_trace = tr.id_trace
  INNER JOIN datalake_chatbot.sessions AS s ON tr.id_langfuse_session = s.id_langfuse_session
  LEFT JOIN  broker_config AS bc ON tr.id_langfuse_session = bc.id_langfuse_session AND bc.rn = 1
  WHERE o.type IN ('AGENT', 'TOOL')
    AND o.name IN (
      'alias_profile_agentV1',
      'alias_inventory_agentV1',
      'alias_get_recommendations_by_company',
      'alias_schedule_visit_agentV1',
      'alias_visit_get_availability',
      'alias_register_visit_intention',
      'alias_escalation_agentV1',
      'alias_get_property_by_external_id',
      'alias_register_escalation'
    )
    AND {load_start_date} <= o.ts_started
    AND o.ts_started < {load_end_date}
)
SELECT
  on.sk_agent_call,
  on.id_langfuse_session,
  on.id_trace,
  bm.sk_broker,
  on.agent_name,
  on.observation_type,
  on.is_tool_call,
  on.turn_number,
  on.duration_ms,
  on.cost_input_usd,
  on.cost_output_usd,
  on.cost_total_usd,
  on.input_tokens,
  on.output_tokens,
  on.had_error,
  on.error_message,
  on.dt_session,
  on.ts_started,
  on.ts_ended,
  CURRENT_TIMESTAMP()                                               AS ts_load,
  YEAR(on.ts_started)                                               AS year,
  MONTH(on.ts_started)                                              AS month,
  DAY(on.ts_started)                                                AS day
FROM obs_numbered AS on
LEFT JOIN broker_map AS bm ON on.company_uuid = bm.uuid_company
```

---

### `fact_alias_leads.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
),
sessions_agg AS (
  SELECT
    ls.uuid_lead,
    COUNT(DISTINCT ls.uuid_lead_session)                                      AS qt_sessions_total,
    COUNT(DISTINCT CASE
      WHEN lr.uuid_lead_resolution IS NOT NULL THEN ls.uuid_lead_session
    END)                                                                       AS qt_sessions_resolved,
    COUNT(DISTINCT CASE
      WHEN lr.type = 'ESCALATION' THEN ls.uuid_lead_session
    END)                                                                       AS qt_sessions_escalated,
    COUNT(DISTINCT CASE
      WHEN lr.type = 'VISIT_INTENTION' THEN ls.uuid_lead_session
    END)                                                                       AS qt_sessions_visit_intention,
    BOOL_OR(lr.ts_sent_to_crm IS NOT NULL)                                    AS is_crm_sent,
    MIN(ls.ts_created)                                                         AS ts_first_contact,
    MAX(ls.ts_updated)                                                         AS ts_last_contact
  FROM datalake_alias_clean.lead_sessions AS ls
  LEFT JOIN datalake_alias_clean.lead_resolutions AS lr
    ON ls.uuid_lead_session = lr.uuid_lead_session
  GROUP BY ls.uuid_lead
)
SELECT
  l.uuid_lead                                     AS sk_lead,
  bm.sk_broker,
  COALESCE(sa.qt_sessions_total, 0)               AS qt_sessions_total,
  COALESCE(sa.qt_sessions_resolved, 0)            AS qt_sessions_resolved,
  COALESCE(sa.qt_sessions_escalated, 0)           AS qt_sessions_escalated,
  COALESCE(sa.qt_sessions_visit_intention, 0)     AS qt_sessions_visit_intention,
  COALESCE(sa.is_crm_sent, FALSE)                 AS is_crm_sent,
  sa.ts_first_contact,
  sa.ts_last_contact,
  DATE(sa.ts_first_contact)                       AS dt_first_contact,
  CURRENT_TIMESTAMP()                             AS ts_load,
  YEAR(sa.ts_first_contact)                       AS year,
  MONTH(sa.ts_first_contact)                      AS month,
  DAY(sa.ts_first_contact)                        AS day
FROM datalake_alias_clean.leads AS l
LEFT JOIN broker_map AS bm         ON l.uuid_company = bm.uuid_company
LEFT JOIN sessions_agg AS sa       ON l.uuid_lead = sa.uuid_lead
WHERE {load_start_date} <= l.ts_updated
  AND l.ts_updated < {load_end_date}
```

---

### `fact_alias_sessions.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
),
resolutions_agg AS (
  SELECT
    lr.uuid_lead_session,
    COUNT(*)                                        AS qt_resolutions,
    TRUE                                            AS is_resolved,
    BOOL_OR(lr.type = 'ESCALATION')                AS is_escalated,
    BOOL_OR(lr.type = 'VISIT_INTENTION')           AS is_visit_intention,
    BOOL_OR(lr.ts_sent_to_crm IS NOT NULL)         AS is_crm_sent
  FROM datalake_alias_clean.lead_resolutions AS lr
  GROUP BY lr.uuid_lead_session
),
engagements_agg AS (
  SELECT
    uuid_lead_session,
    COUNT(*)          AS qt_engagements,
    MIN(ts_created)   AS ts_engagement_first
  FROM datalake_alias_clean.lead_engagements
  GROUP BY uuid_lead_session
),
first_origin AS (
  -- FIRST_VALUE via window; deduplicated with ROW_NUMBER for JOIN
  SELECT uuid_lead_session, origin AS origin_first
  FROM (
    SELECT
      uuid_lead_session,
      origin,
      ROW_NUMBER() OVER (PARTITION BY uuid_lead_session ORDER BY ts_created) AS rn
    FROM datalake_alias_clean.lead_engagements
  )
  WHERE rn = 1
),
trace_meta AS (
  -- n_user_turns and turn timestamps — from traces, not observations (avoids zeroing count)
  -- Source: datalake_langfuse_clean.traces (confirmed in cc2f148e62)
  SELECT
    t.id_session                                                     AS id_langfuse_session,
    COUNT(DISTINCT t.id_trace)                                       AS n_user_turns,
    MAX(t.version)                                                   AS bot_version,
    MIN(t.ts_created)                                                AS ts_first_turn,
    MAX(t.ts_created)                                                AS ts_last_turn
  FROM datalake_langfuse_clean.traces AS t
  WHERE t.id_session IS NOT NULL
    AND t.ts_created >= '{load_start_date}'
  GROUP BY t.id_session
),
obt_agg AS (
  -- Aggregates funnel flags, tool call counters, and LLM metrics per session.
  -- Source: datalake_langfuse_clean.observations JOIN datalake_langfuse_clean.traces
  -- cost_details is ROW type — accessed as struct (TRY_CAST avoids schema errors)
  SELECT
    t.id_session                                                     AS id_langfuse_session,
    MAX(CASE WHEN o.name = 'alias_profile_agentV1'
        THEN 1 ELSE 0 END) = 1                                       AS had_profiling,
    MAX(CASE WHEN o.name = 'alias_inventory_agentV1'
        THEN 1 ELSE 0 END) = 1                                       AS had_inventory,
    MAX(CASE WHEN o.name = 'alias_get_recommendations_by_company'
        THEN 1 ELSE 0 END) = 1                                       AS had_recommendations,
    MAX(CASE WHEN o.name = 'alias_schedule_visit_agentV1'
        THEN 1 ELSE 0 END) = 1                                       AS had_scheduling,
    MAX(CASE WHEN o.name = 'alias_visit_get_availability'
        THEN 1 ELSE 0 END) = 1                                       AS had_availability,
    MAX(CASE WHEN o.name = 'alias_register_visit_intention'
        THEN 1 ELSE 0 END) = 1                                       AS had_visit_registered,
    MAX(CASE WHEN o.name = 'alias_escalation_agentV1'
        THEN 1 ELSE 0 END) = 1                                       AS had_escalation,
    MAX(CASE WHEN o.name = 'alias_register_visit_intention'
                  AND LOWER(o.output) LIKE '%registered successfully%'
        THEN 1 ELSE 0 END) = 1                                       AS visit_registered_success,
    MAX(CASE WHEN o.name = 'alias_register_escalation'
                  AND LOWER(o.output) LIKE '%escalation registered successfully%'
        THEN 1 ELSE 0 END) = 1                                       AS escalation_registered_success,
    CASE
      WHEN MAX(CASE WHEN o.name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1
        THEN 'visit_intention_registered'
      WHEN MAX(CASE WHEN o.name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1
        THEN 'escalated'
      WHEN MAX(CASE WHEN o.name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1
        THEN 'schedule_visit_agent_called'
      WHEN MAX(CASE WHEN o.name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1
        THEN 'inventory_searched'
      WHEN MAX(CASE WHEN o.name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1
        THEN 'profile_identified'
      ELSE 'no_agent'
    END                                                              AS funnel_stage_deepest,
    MIN(CASE WHEN o.name = 'alias_profile_agentV1'
             THEN o.ts_started END)                                  AS ts_profiling,
    MIN(CASE WHEN o.name = 'alias_inventory_agentV1'
             THEN o.ts_started END)                                  AS ts_inventory,
    MIN(CASE WHEN o.name = 'alias_schedule_visit_agentV1'
             THEN o.ts_started END)                                  AS ts_scheduling,
    MIN(CASE WHEN o.name = 'alias_visit_get_availability'
             THEN o.ts_started END)                                  AS ts_availability,
    MIN(CASE WHEN o.name = 'alias_register_visit_intention'
             THEN o.ts_started END)                                  AS ts_visit_registered,
    MIN(CASE WHEN o.name = 'alias_escalation_agentV1'
             THEN o.ts_started END)                                  AS ts_escalation,
    COUNT_IF(o.type = 'TOOL'
      AND LOWER(COALESCE(o.output, '')) LIKE '%error%')              AS n_tool_call_errors,
    COUNT_IF(o.name = 'alias_get_recommendations_by_company'
      AND o.type = 'TOOL')                                           AS n_calls_get_recommendations,
    COUNT_IF(o.name = 'alias_visit_get_availability'
      AND o.type = 'TOOL')                                           AS n_calls_get_availability,
    COUNT_IF(o.name = 'alias_get_property_by_external_id'
      AND o.type = 'TOOL')                                           AS n_calls_get_property,
    COUNT_IF(o.name = 'alias_register_visit_intention'
      AND o.type = 'TOOL')                                           AS n_calls_register_visit,
    COUNT_IF(o.name = 'alias_register_escalation'
      AND o.type = 'TOOL')                                           AS n_calls_register_escalation,
    -- n_user_turns_until_*: requires turn_number CTE per trace; see fact_alias_agent_calls
    -- TODO: implement with ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_first_obs)
    SUM(TRY_CAST(cost_details.total AS DOUBLE))                      AS total_llm_cost_usd,
    PERCENTILE_APPROX(
      CAST(DATE_DIFF('millisecond', o.ts_started, o.ts_ended) AS DOUBLE), 0.5
    )                                                                AS p50_llm_response_time_ms,
    PERCENTILE_APPROX(
      CAST(DATE_DIFF('millisecond', o.ts_started, o.ts_ended) AS DOUBLE), 0.95
    )                                                                AS p95_llm_response_time_ms,
    AVG(CAST(DATE_DIFF('millisecond', o.ts_started, o.ts_ended) AS DOUBLE))
                                                                     AS avg_llm_response_time_ms
  FROM datalake_langfuse_clean.observations AS o
  INNER JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
  WHERE t.id_session IS NOT NULL
    AND t.ts_created >= '{load_start_date}'
  GROUP BY t.id_session
),
broker_config AS (
  -- company_uuid via get_alias_configuration (same pattern as OBT cc2f148e62)
  SELECT
    t.id_session AS id_langfuse_session,
    COALESCE(
      JSON_EXTRACT_SCALAR(o.output, '$.companyUuid'),
      JSON_EXTRACT_SCALAR(o.output, '$.companyUUID')
    ) AS company_uuid,
    ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY o.ts_started) AS rn
  FROM datalake_langfuse_clean.observations AS o
  INNER JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
  WHERE o.name = 'get_alias_configuration'
    AND o.type = 'TOOL'
    AND t.id_session IS NOT NULL
    AND t.ts_created >= '{load_start_date}'
)
SELECT
  ls.uuid_lead_session                            AS sk_lead_session,
  ls.uuid_lead                                    AS sk_lead,
  bm.sk_broker,
  ls.uuid_chat_session                            AS id_langfuse_session,
  cs.id_sauron_session,
  ls.status,
  COALESCE(fo.origin_first, 'UNKNOWN')            AS origin_first,
  cs.channel,
  ea.ts_engagement_first,
  COALESCE(ea.qt_engagements, 0)                  AS qt_engagements,
  COALESCE(ra.is_resolved, FALSE)                 AS is_resolved,
  COALESCE(ra.is_escalated, FALSE)                AS is_escalated,
  COALESCE(ra.is_visit_intention, FALSE)          AS is_visit_intention,
  COALESCE(ra.is_crm_sent, FALSE)                 AS is_crm_sent,
  ls.ts_chat_started IS NOT NULL                  AS is_chat_started,
  COALESCE(ra.qt_resolutions, 0)                  AS qt_resolutions,
  tm.bot_version,
  -- is_test: hardcoded UUIDs per OBT feature/alias-obt (commit cc2f148e62)
  -- '00000000-0000-4000-8000-000000000001' → synthetic test company (placeholder)
  -- '31616192-288b-439a-baec-890a5c89e20a' → internal QA company
  COALESCE(bc.company_uuid, '') IN (
    '00000000-0000-4000-8000-000000000001',
    '31616192-288b-439a-baec-890a5c89e20a'
  )                                                                AS is_test,
  COALESCE(oa.had_profiling, FALSE)               AS had_profiling,
  COALESCE(oa.had_inventory, FALSE)               AS had_inventory,
  COALESCE(oa.had_recommendations, FALSE)         AS had_recommendations,
  COALESCE(oa.had_scheduling, FALSE)              AS had_scheduling,
  COALESCE(oa.had_availability, FALSE)            AS had_availability,
  COALESCE(oa.had_visit_registered, FALSE)        AS had_visit_registered,
  COALESCE(oa.had_escalation, FALSE)              AS had_escalation,
  COALESCE(oa.visit_registered_success, FALSE)    AS visit_registered_success,
  COALESCE(oa.escalation_registered_success, FALSE) AS escalation_registered_success,
  COALESCE(oa.funnel_stage_deepest, 'no_agent')   AS funnel_stage_deepest,
  oa.ts_profiling,
  oa.ts_inventory,
  oa.ts_scheduling,
  oa.ts_availability,
  oa.ts_visit_registered,
  oa.ts_escalation,
  COALESCE(tm.n_user_turns, 0)                    AS n_user_turns,
  NULL                                            AS n_user_turns_until_first_recommendation, -- TODO: ROW_NUMBER() per trace before first recommendation
  NULL                                            AS n_user_turns_until_visit_intent,          -- TODO: ROW_NUMBER() per trace before visit intent
  COALESCE(oa.n_tool_call_errors, 0)              AS n_tool_call_errors,
  COALESCE(oa.n_calls_get_recommendations, 0)     AS n_calls_get_recommendations,
  COALESCE(oa.n_calls_get_availability, 0)        AS n_calls_get_availability,
  COALESCE(oa.n_calls_get_property, 0)            AS n_calls_get_property,
  COALESCE(oa.n_calls_register_visit, 0)          AS n_calls_register_visit,
  COALESCE(oa.n_calls_register_escalation, 0)     AS n_calls_register_escalation,
  NULL                                            AS n_recommendations_shown, -- TODO: parsing HostGraph JSON
  oa.total_llm_cost_usd,
  CASE WHEN COALESCE(tm.n_user_turns, 0) > 0
    THEN oa.total_llm_cost_usd / tm.n_user_turns
  END                                             AS avg_cost_per_turn_usd,
  NULL                                            AS total_input_tokens,  -- not available in observations (see traces)
  NULL                                            AS total_output_tokens, -- not available in observations (see traces)
  oa.avg_llm_response_time_ms,
  oa.p50_llm_response_time_ms,
  oa.p95_llm_response_time_ms,
  cs.full_conversation,
  ls.ts_created,
  ls.ts_closed,
  tm.ts_first_turn,
  tm.ts_last_turn,
  CASE WHEN tm.ts_first_turn IS NOT NULL AND tm.ts_last_turn IS NOT NULL
    THEN CAST(DATE_DIFF('minute', tm.ts_first_turn, tm.ts_last_turn) AS DOUBLE)
  END                                             AS session_wall_duration_min,
  CURRENT_TIMESTAMP()                             AS ts_load,
  YEAR(ls.ts_created)                             AS year,
  MONTH(ls.ts_created)                            AS month,
  DAY(ls.ts_created)                              AS day
FROM datalake_alias_clean.lead_sessions AS ls
LEFT JOIN datalake_alias_clean.leads AS l
  ON ls.uuid_lead = l.uuid_lead
LEFT JOIN broker_map AS bm
  ON l.uuid_company = bm.uuid_company
LEFT JOIN datalake_chatbot.sessions AS cs
  ON ls.uuid_chat_session = cs.id_langfuse_session
LEFT JOIN engagements_agg AS ea   ON ls.uuid_lead_session = ea.uuid_lead_session
LEFT JOIN first_origin AS fo      ON ls.uuid_lead_session = fo.uuid_lead_session
LEFT JOIN resolutions_agg AS ra   ON ls.uuid_lead_session = ra.uuid_lead_session
LEFT JOIN trace_meta AS tm        ON ls.uuid_chat_session = tm.id_langfuse_session
LEFT JOIN obt_agg AS oa           ON ls.uuid_chat_session = oa.id_langfuse_session
LEFT JOIN broker_config AS bc     ON ls.uuid_chat_session = bc.id_langfuse_session AND bc.rn = 1
WHERE {load_start_date} <= ls.ts_updated
  AND ls.ts_updated < {load_end_date}
```

---

### `fact_alias_lead_resolutions.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  lr.uuid_lead_resolution             AS sk_lead_resolution,
  lr.uuid_lead_session                AS sk_lead_session,
  ls.uuid_lead                        AS sk_lead,
  bm.sk_broker,
  lr.type,
  lr.property_id                      AS id_synthetic_house,
  lr.ts_sent_to_crm IS NOT NULL       AS is_sent_to_crm,
  lr.ts_resolved,
  lr.ts_sent_to_crm,
  CURRENT_TIMESTAMP()                 AS ts_load,
  YEAR(lr.ts_resolved)                AS year,
  MONTH(lr.ts_resolved)               AS month,
  DAY(lr.ts_resolved)                 AS day
FROM datalake_alias_clean.lead_resolutions AS lr
JOIN datalake_alias_clean.lead_sessions AS ls
  ON lr.uuid_lead_session = ls.uuid_lead_session
JOIN datalake_alias_clean.leads AS l
  ON ls.uuid_lead = l.uuid_lead
LEFT JOIN broker_map AS bm
  ON l.uuid_company = bm.uuid_company
WHERE {load_start_date} <= lr.ts_updated
  AND lr.ts_updated < {load_end_date}
```

---

### `fact_alias_inventory_ingestions.sql`

```sql
WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  ii.uuid_inventory_ingestion          AS sk_inventory_ingestion,
  bm.sk_broker,
  ii.status,
  ii.status = 'COMPLETED'             AS is_successful,
  ii.quantity_created,
  ii.quantity_updated,
  ii.quantity_failed,
  ii.quantity_skipped,
  ii.quantity_unpublished,
  ii.failure_reason,
  CASE WHEN ii.ts_started IS NOT NULL AND ii.ts_completed IS NOT NULL
    THEN (UNIX_TIMESTAMP(ii.ts_completed) - UNIX_TIMESTAMP(ii.ts_started)) / 60.0
  END                                  AS duration_minutes,
  ii.ts_started,
  ii.ts_completed,
  CURRENT_TIMESTAMP()                  AS ts_load,
  YEAR(ii.ts_started)                  AS year,
  MONTH(ii.ts_started)                 AS month,
  DAY(ii.ts_started)                   AS day
FROM datalake_alias_clean.inventory_ingestions AS ii
LEFT JOIN broker_map AS bm ON ii.uuid_company = bm.uuid_company
WHERE {load_start_date} <= ii.ts_updated
  AND ii.ts_updated < {load_end_date}
```

---

## 10. References

- Alias CDC pipeline: `dags/growth/alias/alias_declaration.yml`
- Service documentation: `dags/growth/alias/alias.md`
- `core_brokers` Spark jobs: `dags/core/core_brokers/spark_jobs/`
- `dw_brokers` SQLs: `dags/broker_xp/dw_brokers/queries/dw/`
- Conversational OBT (base for `fact_alias_sessions`): PR #24433 (`feature/alias-obt`, commit `cc2f148e62`)
- `datalake_chatbot.sessions` schema: `dags/conversational_xp/enrich_chatbot/metadata/enrich/sessions.yml`
- Langfuse clean layer: `datalake_langfuse_clean.observations`, `datalake_langfuse_clean.traces`
