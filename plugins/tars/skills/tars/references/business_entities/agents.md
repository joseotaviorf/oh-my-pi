# Agents Domain

QuintoAndar real-estate agents — activation, performance, workload, brokerage, and preferred fixed agent.

## Overview

⚠ **"Agent" is a multi-type entity — always ask the user which agent type they mean before querying.** The word "agente" in Portuguese can refer to visit agents (Visita), property inspectors (Vistoria), photographer agents (SessaoFotos), outsourced inspection agents (VistoriaQuarteirizada), or repair/check-up agents (CheckUpLar). Most datasets mix all types unless explicitly filtered. If the user does not specify, ask: *"Você quer todos os tipos de agente ou só agentes de visita/demanda?"* Default scope for CIQ/activation/brokerage analyses is usually Visita (demand visit) agents — but confirm before assuming.

Agents in this domain are QuintoAndar field agents who operate on properties — conducting visits, inspections, photo sessions, lead qualification, and earning brokerage commissions. This file covers all agent operation types. It does NOT cover AI chatbots or AI-driven agents (Wall-E, Matthew, Sauron) — those are documented in `chatbot_sessions.md` and `matthew.md`.

Two affiliation populations coexist. **1P / CIQ agents** are directly affiliated with QuintoAndar, enrolled in the CIQ (Corretor Integrado QuintoAndar) program; they appear with `affiliation_type = '1P'` in accreditation tables. **3P / partner agents** are affiliated through external partner firms; they appear with `is_3p_agent = true` in `dim_agent` and `affiliation_type = '3P'` in `datalake_agent_accreditation.agent`. Both populations appear in most tables. Note that these affiliation labels say nothing about operation type — a 1P agent can be a photographer or an inspector, not just a visit agent.

The agent lifecycle runs through several stages: **prospect** (intention to create an account) → **accreditation** (accepted into the platform) → **first commercial event** (first listing, first TQC referral, or first PPA) → **activated** (definition varies — always ask the user what activation means in their context) → **tiered** (performance tier assigned) → **payments** (revenue share) → **churned** (inactive status).

Three time grains are used across the domain. **Monthly snapshot** tables use `reference_month` (a DATE always truncated to the first of the month, e.g. `2026-06-01`), covering tables such as `datalake_agent_reports.*`. **Daily** tables use `dt_reference` (a DATE), covering tables such as `dw_public.dim_agent`. **Point-in-time SCD** tables use `ts_started` / `ts_ended` or `ts_relation_started` / `ts_relation_ended` timestamp pairs to represent validity windows, covering PFA and accreditation history tables.

`datalake_agent_accreditation.agent` is the **hub node** and canonical identity source for the agent domain. Five downstream enrich DAGs depend on it. The `id_agent` field in this table is the cross-system agent identity key and should be used as the join anchor when working with PFA, accreditation, and 3P history tables. Note that `id_agent` ≠ `id_user` — `id_user` is the platform user key used in monthly report and hub allocation tables.

## Glossary and Synonyms

| Term | Meaning |
|------|---------|
| **Agente CIQ / CIQ agent** | Agent enrolled and active in the CIQ program; `ciq_status` active in `agent_status_by_month`; `is_ciq_eligible = true` in agent flag fields |
| **BIG_AGENT** | `revenue_source = 'BIG_AGENT'` in `agent_revenue_share`; newer brokerage model |
| **Nazaré** | `revenue_source = 'NAZARE'` in `agent_revenue_share`; legacy per-offer brokerage system |
| **Agente 3P / third-party agent** | `is_3p_agent = true` in `dim_agent`; `affiliation_type = '3P'` in `datalake_agent_accreditation.agent` |
| **Agente ativo / active agent** | ⚠ Ambiguous — **always ask the user what they mean before querying**. Common interpretations: (1) has a platform account available → `is_agent_active = true` in `dim_agent` (default/weakest definition); (2) has at least one visit in a period → join to `dw_visit.fact_visit_schedules`; (3) is eligible and operating on the platform → combine `is_agent_active`, `is_user_active`, `is_blocked`, `is_service_link_active` in `dim_agent`; (4) has opened the agent app → Amplitude events in `datalake_amplitude_agents_app`. Never assume which definition applies. |
| **Ativação / activation** | ⚠ No consensus definition — **always ask the user what they mean**. Possible meanings: (1) `is_activated = true` in `agent_new_agent_activation_metrics` (new-agent cohort, first commercial event within 60 days of registration); (2) first visit scheduled; (3) first listing published; (4) first TQC referral; (5) first deal closed. Definition varies by team and OKR context. |
| **TQC (Trás Quem Compra)** | Lead-qualification contact event. Usually define using column `id_user_agent_lead_referral` = column `id_user_agent` in `datalake_sale_offer_flows.offer_specialists`  |
| **PPA** | (Preferred Property Agent); Agent fixed to a specific listing, this relation begins when the agents bring the supply (property) to QuintoAndar. Table: `datalake_ebdb_agents.preferred_property_agent_relation_history` |
| **PFA / Preferred Fixed Agent** | Agent fixed to a specific lead, usually by first-visit criteria, but it can have different reasons for PFA creation, defined at the column `origin` for table: `datalake_ebdb_agents.preferred_property_agent_relation_history` |
| **VBBA (Visits Booked by Agent)** | Visits that were booked by the agent, not the seeker. Defined by `sk_author_creator` = `sk_user_agent` in `dw_visit.fact_visit_schedules`. |
| **VCBA (Visits Completed Booked by Agent)** | Same criteria as VBBA but the visit must be completed: `is_completed = 1`. |
| **Hub / Business Unit** | `hub_name`, `id_business_unit` in `agent_hub_alocation` — physical or virtual agent grouping by region |
| **EN / Negotiation Executive** | `id_user_negotiation_executive` in `agent_hub_alocation`; the internal QuintoAndar staff member responsible for the agent's hub |
| **Perfil do agente / agent profile** | Operation type the agent is accredited for. Values in `datalake_agent_accreditation.agent_profile.profile` and `datalake_ebdb_clean.agent_data.agent_type` (raw source): `Visita` — agents responsible for conducting property visits (the most common type; usually what business teams mean by "agente" or "demand agent"); `Vistoria` — agents responsible for property inspections before tenant move-in and after contract end; `VistoriaQuarteirizada` — outsourced agents responsible for conducting property visits/inspections; `SessaoFotos` — photographer agents responsible for taking property photos for listings; `CheckUpLar` — agents responsible for performing and analyzing reported repairs. An agent can hold multiple profiles over time. Filter `ts_revision_ended IS NULL` for current profile. The raw `agent_type` column in `datalake_ebdb_clean.agent_data` is the upstream source; it propagates into accreditation tables. |
| **Demand Agent / agente de demanda** | ⚠ Business jargon, not a product concept. Loosely means a visit agent (profile `Visita`) who acquires and manages demand (buyers/tenants). In data, translate to: `profile = 'Visita'` AND `is_allow_demand_acquisition = true` (or capability `DEMAND_ACQUISITION ENABLED`) in `datalake_agent_accreditation.agent`. Prefer capability filters over legacy jargon. |
| **CIQ agent / agente CIQ** | ⚠ Business jargon that conflates two things: (1) affiliation — enrolled in the CIQ program (`affiliation_type = '1P'`, `is_ciq_eligible = true`); (2) operation type — typically a Visita agent. In data, use `ciq_status` in `agent_status_by_month` for CIQ program status, and `profile = 'Visita'` for the operation type. Always confirm which dimension the user means. |
| **CIQ-Only agent** | ⚠ Business jargon. Refers to an agent whose sole active business is CIQ (no independent demand acquisition). In data: has the CIQ status Active, but not Demand agent status active. Prefer capability-based definition: `DEMAND_ACQUISITION DISABLED` AND `SUPPLY_CONVERSION_CONSULTANCY ENABLED`. |
| **Independent Agent / agente independente** | ⚠ Business jargon. Agent who operates independently and has both acquisition and demand attributions. In data: Has both CIQ and Agent status as active and is_passive_lead_receiver False (from datalake_ebdb_clean.agent_data). Most equivalent capability is: `DEMAND_ACQUISITION ENABLED` AND `affiliation_type = '1P'`. |
| **Capability / capacidade** | Fine-grained permission model in `datalake_agent_accreditation.agent_capability`. Types: `DEMAND_ACQUISITION` (can acquire demand leads), `DEMAND_VISIT_MANAGEMENT` (can manage demand visits — has `business_context` RENT/SALE), `SUPPLY_ACQUISITION` (can acquire supply), `SUPPLY_CONVERSION_CONSULTANCY` (CIQ conversion consultancy), `NEGOTIATION` (can negotiate deals). Status: `ENABLED` or `DISABLED`. For quick boolean checks, use the `is_allow_*` flags on the `agent` table instead. |
| **Primeira listagem / first listing** | ⚠ Ask the user whether they mean (1) **first listing** — any first listing event for an agent, regardless of duplicates — or (2) **valid first listing** — the Operations team's deduplication-gated definition that excludes re-listed/duplicated properties (gated by `enrich_listing_deduplication.valid_first_listing`). Valid first listing is used for CIQ payment eligibility and agent activation criteria. If context is agents/CIQ payments, default to valid first listing and confirm. |

## Tables

### Quick Lookup

| You need… | Use this table (alias) | Merge key | Notes |
|-----------|------------------------|-----------|-------|
| Agent status + CIQ (monthly) | `datalake_agent_reports.agent_status_by_month` (`asm`) | `id_user, reference_month` | Freshest monthly lifecycle snapshot; partition: `reference_month` |
| Agent identity, status, capabilities flags | `datalake_agent_accreditation.agent` (`acc`) | `id_agent` | Hub node; canonical `id_agent` source; `affiliation_type`, `status` (ACTIVE/INACTIVE), `profile`, `is_allow_*` capability booleans, `days_in_current_status` |
| Agent fine-grained capabilities | `datalake_agent_accreditation.agent_capability` (`acap`) | `id_agent, type` | One row per agent × capability type; `status` (ENABLED/DISABLED), `business_context` (RENT/SALE/null); see capability types below |
| Agent geo-region assignment history | `datalake_agent_accreditation.agent_major_region_code` (`amrc`) | `id_agent, major_region_code` | Region assignment periods with `total_days_in_region_code`; `ts_started/ended` |
| CIQ membership flags (light join) | `datalake_ebdb_agents.ciq_agents` (`ciq`) | `id_user` | `is_active`, `is_sale_agent`, `is_rent_agent` |
| 3P agent type + contract history | `datalake_ebdb_agents.agent_3p_history` (`a3h`) | `id_agent` | SCD; `is_current = true` for present contract type |
| DW agent snapshot (sk↔id bridge) | `dw_public.dim_agent` (`da`) | `sk_agent` / `id_user` | Use only to bridge `sk_agent ↔ id_user`; ⚠ `rede_partner` DEPRECATED |
| Agent hub assignment, NE, region (daily) | `datalake_hub_services.member_hub_allocation` (`mha`) | `id_user, dt_reference` | Replacement for deprecated `agent_hub_alocation`; filter `is_active = true` for current-state; has `profile`, `city_name`, `lead_types`, `id_region` built in; NE via `id_parent_user` / `user_parent_*`; partition: `year/month/day` |
| Agent hub assignment + NE (daily) — **DEPRECATED** | `datalake_hub_services.agent_hub_alocation` (`aha`) | `id_user, dt_reference` | ⚠ **DEPRECATED** — use `member_hub_allocation` instead. Note typo in name: `alocation` (one `l`). Kept for backward compatibility; partition: `year/month/day` |
| Agent↔hub relation + lead types — **DEPRECATED** | `datalake_hub_services.agent_hub_relation` (`ahr`) | `id_agent` | ⚠ **DEPRECATED** — `member_hub_allocation` merges this table's `profile`, `city_name`, `lead_types`, `id_region` columns. |
| Brokerage revenue per house (BIG_AGENT + Nazaré) | `datalake_agent_payments.agent_revenue_share` (`ars`) | `id_user, id_house, revenue_source` | ⚠ Always filter `revenue_source` — double-count risk; partition: `year/month/day` on `dt_updated` |
| Per-offer brokerage fee (Nazaré) | `datalake_brokerage.partner_brokerage` (`pb`) | `id_offer, id_user_agent` | `agent_role`, `partner_brokerage_fee`, `is_share_invalidated` |
| CIQ rent commission per house | `datalake_ciq.ciq_listing_purchase` (`clp`) | `id_house, id_partner` | ⚠ RENT + CIQ_FULL only; validity gated by `enrich_listing_deduplication.valid_first_listing` |
| PFA relation history (per listing) | `datalake_ebdb_agents.preferred_property_agent_relation_history` (`ppar`) | `id_house, id_related_agent` | `ts_relation_ended IS NULL` for active; ⚠ `ts_relation_started` is synthetic before 2025-06-03 |
| PFA program eligibility | `datalake_ebdb_agents.preferred_property_agent_program_eligibility` (`ppae`) | `id_agent, program` | Filter `ts_status_ended IS NULL` for current eligibility |
| Visit performance (historical only) | `dw_agent.fact_visit_agent_performance` | `sk_agent, dt_reference` | ⚠ **STALE — pipeline stopped 2025-09-21**; data back to 2024-01-01; use only for historical analysis pre-Oct 2025 |
| Visit schedule metrics (historical only) | `datalake_visit_agent_performance.fact_agent_visit_schedule_daily` | `id_agent, dt_reference` | ⚠ **STALE — same pipeline**; last updated 2025-09-23 |

### Critical Rules

- **Agent type disambiguation (mandatory)**: "agent" covers Visita, Vistoria, VistoriaQuarteirizada, SessaoFotos, and CheckUpLar profiles. Most tables include all types. Always confirm the intended scope before building a query — most CIQ/activation/brokerage questions target `profile = 'Visita'` only. Filter via `datalake_agent_accreditation.agent_profile` (SCD, `ts_revision_ended IS NULL` for current) or `datalake_ebdb_clean.agent_data.agent_type` (raw source). For capability-based filtering, use `agent_capability` — prefer this over legacy jargon like "Demand Agent" or "CIQ-Only".

- **Legacy subtype jargon → capability translation**: terms like "Demand Agent", "CIQ", "CIQ-Only", "Independent Agent" are business nomenclature with no direct column equivalent in modern tables. Always translate to capability filters (`agent_capability.type + status`) or `agent_type_segment` in `agent_new_agent_activation_metrics`. See Glossary for the mapping.

- **Identity bridge**: `sk_agent` (DW star-schema) ↔ `id_user` (operational/enrich). They are NOT interchangeable. Bridge through `dw_public.dim_agent` (join on `sk_agent`, take `id_user`). `id_agent` ≠ `id_user` — `id_agent` is the accreditation entity key, `id_user` is the platform user key.

- **`agent_revenue_share` double-count trap**: `agent_revenue_share` stores one row per (`id_user`, `id_house`, `revenue_source`, `revenue_role`). It UNIONs BIG_AGENT and NAZARE data. Never `SUM(revenue_amount)` or percentages without filtering `revenue_source` first — you will count the same house twice.

- **`agent_hub_alocation` is deprecated**: Use `datalake_hub_services.member_hub_allocation` for all new queries. The two tables are NOT interchangeable without adaptation: (1) `member_hub_allocation` has ~1,100 more users per day (broader "member" scope beyond visit agents); (2) it requires `is_active = true` to filter current allocations; (3) NE data moved from dedicated columns (`id_user_negotiation_executive`, `negotiation_executive_*`) to parent-member columns (`id_parent_user`, `user_parent_*`); (4) `profile`, `city_name`, `city_group`, `lead_types`, `id_region` are now included directly (previously required joining `agent_hub_relation`). The old table's name also has a typo (`alocation`, one `l`) — the new table is spelled correctly.

- **Stale visit pipeline**: All tables under `dw_agent.*` (facts) and `datalake_visit_agent_performance.*` stopped updating **2025-09-21**. Do NOT use for current-state analysis. There is no confirmed replacement pipeline for daily visit funnel metrics as of 2026-06 — tell the user the data is unavailable for post-Sep 2025 and escalate to the data engineering team. For monthly lifecycle questions (status, CIQ), use `datalake_agent_reports.agent_status_by_month` instead.

- **Monthly partition filter**: `reference_month` is a DATE, always first of month. Use `reference_month = DATE_TRUNC('month', CURRENT_DATE)` for the latest available month.

- **Daily partition filter**: `year`, `month`, `day` are INTEGER columns. Filter as `year = 2026 AND month = 6 AND day = 3`, not with `BETWEEN` on `dt_reference` (that scans all partitions).

- **`rede_partner` is deprecated**: `dw_public.dim_agent.rede_partner` — never reference. Use `sk_broker` → `dw_brokers.dim_broker` for broker company data.

- **`offer_flow_events` / `offer_flow_performance` epoch overflow**: minimum dates show as `1899-12-29` due to a timestamp-to-date conversion bug. Always add `WHERE ts_event > DATE '2010-01-01'` when using these tables.

- **`house_consultant_history` fragile**: `datalake_big_agent.house_consultant_history` has 33 cross-domain references but its `consultant_type` values (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) are targeted by an active RFC. Do not write new analyses that rely on these specific values until the RFC is resolved.

- **`dw_brokers.dim_brokers` is invalid**: the schema has `DELTA_LAKE_INVALID_SCHEMA`. Use `dw_public.dim_agent` for identity lookup instead.

### Column Groups for Complex Tables

#### `datalake_agent_accreditation.agent` — 26 columns

| Column group | Columns |
|---|---|
| Identity | `id_agent`, `id_agent_data`, `id_partner`, `id_user`, `id_negotiation_executive_user` |
| UUIDs (cross-system) | `uuid_company`, `uuid_agent`, `uuid_person` |
| CRECI registration | `creci`, `creci_uf` |
| Classification | `affiliation_type` (1P/3P), `status` (ACTIVE/INACTIVE), `company_product_name`, `profile` |
| Capability booleans (fast filter) | `is_allow_supply_acquisition`, `is_allow_demand_acquisition`, `is_allow_visit`, `is_allow_demand_sale`, `is_allow_demand_rent` |
| Partnership flags | `is_1p_partnership`, `is_3p_partnership`, `is_reactivated` |
| Lifecycle timing | `days_in_current_status`, `ts_last_status_changed`, `ts_created`, `ts_updated` |

> Use `is_allow_*` booleans for quick capability checks on a single table. Use `agent_capability` when you need capability-level detail (status per type, business_context scoping, or history via `ts_created/updated`).

#### `datalake_agent_accreditation.agent_capability` — capability type reference

Grain: one row per `(id_agent, type, business_context)`. For context-agnostic types (null business_context) there is one row per `(id_agent, type)`. For `DEMAND_VISIT_MANAGEMENT` there are two rows per agent — one for RENT and one for SALE. Full enum confirmed in the datalake:

| type | status values | business_context |
|---|---|---|
| `DEMAND_ACQUISITION` | ENABLED / DISABLED | null (not context-specific) |
| `DEMAND_VISIT_MANAGEMENT` | ENABLED / DISABLED | RENT or SALE (one row per context) |
| `NEGOTIATION` | ENABLED | null |
| `SUPPLY_ACQUISITION` | ENABLED / DISABLED | null |
| `SUPPLY_CONVERSION_CONSULTANCY` | ENABLED / DISABLED | null |

Filter pattern for agents with a specific capability enabled:
```sql
SELECT ac.id_agent
FROM datalake_agent_accreditation.agent_capability AS ac
WHERE ac.type = 'DEMAND_VISIT_MANAGEMENT'
  AND ac.status = 'ENABLED'
  AND ac.business_context = 'RENT'
```

#### `datalake_hub_services.member_hub_allocation` — 37 columns

| Column group | Columns |
|---|---|
| Member identity | `id_member_relationship`, `id_member_profile`, `id_user`, `id_main_user`, `id_agent`, `uuid_person`, `uuid_company` |
| Hub / region | `id_business_unit`, `hub_name`, `id_region`, `city_group`, `city_name`, `short_region_name` |
| Classification | `profile`, `agent_type`, `business_context`, `lead_types`, `is_active` |
| Member contact | `user_name`, `user_email`, `user_phone_number`, `user_secondary_phone_number`, `user_cpf` |
| Parent member (NE / manager) | `id_parent_member_profile`, `id_parent_user`, `id_parent_main_user`, `id_parent_agent`, `uuid_parent_person`, `user_parent_name`, `user_parent_email`, `user_parent_phone_number`, `user_parent_secondary_phone_number`, `user_parent_cpf` |
| Partition | `dt_reference`, `year`, `month`, `day` |

> Filter `is_active = true` for current allocation state. The "parent member" columns replace the old `negotiation_executive_*` columns from `agent_hub_alocation`.

#### `datalake_tiers.agent_performance` — EAV format

One row per `(id_user, id_agent, id_metric_period, metric_name, metric_value)`. To get a wide view, pivot on `metric_name`:

```sql
SELECT
    id_user,
    MAX(CASE WHEN metric_name = 'visits_completed' THEN metric_value END)   AS visits_completed,
    MAX(CASE WHEN metric_name = 'listings_published' THEN metric_value END) AS listings_published
FROM datalake_tiers.agent_performance
WHERE id_metric_period = '<period>'
GROUP BY id_user
```

> Confirm exact `metric_name` strings by running `SELECT DISTINCT metric_name FROM datalake_tiers.agent_performance LIMIT 50` before building wide pivots — values may evolve.

#### `datalake_agent_payments.agent_revenue_share` — key columns

| Column group | Columns |
|---|---|
| Identity | `id_user`, `id_house`, `uuid_person` |
| Context | `business_context`, `revenue_source` (`BIG_AGENT` or `NAZARE`), `revenue_role` (`DEMAND` or `SUPPLY`) |
| Amounts | `revenue_amount`, `revenue_percentage` |
| Share breakdown | `brokerage_percentage` (demand conversion fee), `tqc_percentage` (TQC acquisition bonus), `ciq_percentage` (CIQ supply commission) |
| Timing | `dt_created`, `dt_updated`; partition: `year / month / day` on `dt_updated` |

## Key Metrics

- **Active agents (monthly)** — count of agents with `agent_status = 'ACTIVE'` in a reference month. ⚠ This covers **all agent types** (Visita, Vistoria, SessaoFotos, etc.). Add a JOIN to `datalake_agent_accreditation.agent_profile` and filter `profile = 'Visita'` if the question targets only visit/demand agents:

```sql
SELECT
    reference_month,
    COUNT(DISTINCT id_user) AS active_agents
FROM datalake_agent_reports.agent_status_by_month
WHERE reference_month = DATE '{reference_month}'
  AND agent_status = 'ACTIVE'
GROUP BY reference_month
```

- **CIQ active agents (monthly)** — agents with an active `ciq_status` in the reference month (confirm non-null/active values by inspecting `ciq_status` enum in `agent_status_by_month`):

```sql
SELECT
    reference_month,
    ciq_status,
    COUNT(DISTINCT id_user) AS ciq_active_agents
FROM datalake_agent_reports.agent_status_by_month
WHERE reference_month = DATE '{reference_month}'
  AND ciq_status IS NOT NULL
GROUP BY reference_month, ciq_status
```

- **Agent count per hub (daily)** — workload snapshot by hub and business context:

```sql
SELECT
    hub_name,
    business_context,
    COUNT(DISTINCT id_user) AS agent_count
FROM datalake_hub_services.member_hub_allocation
WHERE year     = YEAR(CURRENT_DATE)
  AND month    = MONTH(CURRENT_DATE)
  AND day      = DAY(CURRENT_DATE)
  AND is_active = true
GROUP BY hub_name, business_context
ORDER BY agent_count DESC
```

- **Brokerage earned per agent (date range)** — total brokerage percentage per agent, filtered to a single `revenue_source`:

```sql
SELECT
    id_user,
    SUM(brokerage_percentage) AS total_brokerage_pct
FROM datalake_agent_payments.agent_revenue_share
WHERE revenue_source = 'BIG_AGENT'   -- ⚠ always filter revenue_source to avoid double-count
  AND dt_updated >= DATE '{start_date}'
  AND dt_updated <  DATE '{end_date}'
GROUP BY id_user
ORDER BY total_brokerage_pct DESC
```

- **Active PFA relations** — count of listings currently with an active PFA:

```sql
SELECT COUNT(DISTINCT id_house) AS listings_with_active_pfa
FROM datalake_ebdb_agents.preferred_property_agent_relation_history
WHERE ts_relation_ended IS NULL
```

## Relationships with Other Entities

### Agent Accreditation Hub

`datalake_agent_accreditation.agent` is the identity anchor for the entire domain. `id_user` bridges to all monthly report tables (`agent_status_by_month`, `agent_new_agent_activation_metrics`) and hub allocation tables. `id_agent` bridges to PFA tables (`preferred_property_agent_relation_history`, `preferred_property_agent_program_eligibility`) and 3P history (`agent_3p_history`).

### Agent Reports (1:N — one agent has many monthly rows)

```sql
acc.id_user = asm.id_user AND asm.reference_month = DATE '{month}'
```

### Hub Services (1:N — one agent has many daily allocation rows)

```sql
acc.id_user = aha.id_user
  AND aha.year  = X
  AND aha.month = X
  AND aha.day   = X
```

### Brokerage (N:1 per house — multiple agents may share brokerage per house)

```sql
acc.id_user = ars.id_user
```

Always filter `revenue_source` before aggregating to avoid double-counting BIG_AGENT and NAZARE rows.

### PFA (1:N — one agent may be PFA for multiple listings)

```sql
acc.id_agent = ppar.id_related_agent
```

Filter `ts_relation_ended IS NULL` for currently active PFA assignments.

### DW Performance (stale bridge — historical only)

`dw_public.dim_agent.sk_agent` bridges DW star-schema tables to the operational layer via `dim_agent.id_user = acc.id_user`. ⚠ All DW performance facts (`dw_agent.fact_visit_agent_performance`, `datalake_visit_agent_performance.*`) are stale since **2025-09-21**. This bridge is only useful for historical analysis.

### Visit Domain

For current visit metrics, see `business_entities/visits.md`. Agents are linked via `sk_agent` in `dw_visit.fact_visits`.

### Support Tickets

`datalake_agent_reports.agent_support_tickets_by_month` joins to `dw_customer_support.fact_tickets` for per-agent ticket analysis.

## Dos and Don'ts

**Do:**
- Ask which agent type the user means — Visita, Vistoria, SessaoFotos, VistoriaQuarteirizada, or CheckUpLar — before scoping any query; most datasets include all types unless filtered
- When the user says "Demand Agent", "CIQ", "CIQ-Only", or "Independent Agent", translate to capability/profile filters (see Glossary) rather than treating these as literal column values — they are business jargon, not product concepts
- Prefer capability-based filters (`agent_capability.type + status`) over legacy subtype jargon whenever the accreditation tables are available
- Ask the user to clarify "active agent" before querying — it can mean account-available, has-visits, app-active, or operationally-eligible; each maps to a different table/filter
- Ask the user to clarify "activation" — definition varies by team and OKR; do not default to `is_activated` without confirming
- Ask the user whether "first listing" means any first listing or valid first listing (dedup-gated); if the context is CIQ payments or activation criteria, default to valid first listing and confirm
- Use `datalake_agent_accreditation.agent` as the canonical identity source for `id_agent`
- Bridge `sk_agent ↔ id_user` via `dw_public.dim_agent` when mixing DW and enrich tables
- Filter `revenue_source` in `agent_revenue_share` before any aggregation
- Filter `ts_relation_ended IS NULL` for active PFA relations
- Filter `ts_status_ended IS NULL` for current PFA program eligibility
- Filter daily-partitioned tables with `year = X AND month = X AND day = X` (integer columns), not with `dt_reference BETWEEN`
- Note `ts_relation_started` may be synthetic for PFA rows created before 2025-06-03
- Pivot `datalake_tiers.agent_performance` on `metric_name` before wide analysis
- Confirm `metric_name` enum values live via `SELECT DISTINCT metric_name FROM datalake_tiers.agent_performance LIMIT 50` before building derived metrics

**Don't:**
- Use `datalake_hub_services.agent_hub_alocation` or `agent_hub_relation` for new queries — both are deprecated; use `member_hub_allocation` with `is_active = true` instead
- Reference `dw_public.dim_agent.rede_partner` (explicitly deprecated)
- Reference `dw_public.dim_agent_region.area_deprecated` or `secondary_area_deprecated` (deprecated)
- Use `dw_agent.fact_visit_agent_performance` or any `datalake_visit_agent_performance.*` table for current data — pipeline stopped 2025-09-21; historical analysis only
- Reference `dw_brokers.dim_brokers` (trailing `s`) — schema has `DELTA_LAKE_INVALID_SCHEMA`
- Use `offer_flow_events` without `WHERE ts_event > DATE '2010-01-01'` (epoch overflow in min dates)
- Treat `datalake_big_agent.house_consultant_history` `consultant_type` values (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) as stable — RFC pending, semantics may change
- Query `temp_demand_agents.*` or `sandbox.temp_pfa_*` tables in production analysis — experimental, non-production
- Assume AI agents (Wall-E, Matthew, Sauron) are in this domain — see `chatbot_sessions.md` and `matthew.md`

## Golden Queries

### Query 1 — Current agents per hub (latest day)

Daily workload snapshot: how many active members are allocated to each hub right now, broken down by business context and profile. Uses `member_hub_allocation` (replacement for deprecated `agent_hub_alocation`).

```sql
SELECT
    mha.hub_name,
    mha.city_name,
    mha.business_context,
    mha.profile,
    mha.agent_type,
    COUNT(DISTINCT mha.id_user) AS number_agents
FROM datalake_hub_services.member_hub_allocation AS mha
WHERE mha.year      = YEAR(CURRENT_DATE)
  AND mha.month     = MONTH(CURRENT_DATE)
  AND mha.day       = DAY(CURRENT_DATE)
  AND mha.is_active = true
GROUP BY mha.hub_name, mha.city_name, mha.business_context, mha.profile, mha.agent_type
ORDER BY number_agents DESC
```

### Query 2 — Brokerage revenue per agent (BIG_AGENT, date range)

Total brokerage percentage earned per agent in a period. Always filters to a single `revenue_source` to avoid double-counting.

```sql
SELECT
    ars.id_user,
    da.is_rent_agent,
    da.is_sale_agent,
    SUM(ars.brokerage_percentage)  AS total_brokerage_pct,
    SUM(ars.tqc_percentage)        AS total_tqc_pct,
    SUM(ars.revenue_amount)        AS total_revenue_amount,
    COUNT(DISTINCT ars.id_house)   AS distinct_houses
FROM datalake_agent_payments.agent_revenue_share AS ars
LEFT JOIN dw_public.dim_agent AS da
    ON ars.id_user = da.id_user
WHERE ars.revenue_source = 'BIG_AGENT'      -- ⚠ always filter revenue_source to avoid double-count
  AND ars.dt_updated >= DATE '{start_date}'
  AND ars.dt_updated <  DATE '{end_date}'
GROUP BY ars.id_user, da.is_rent_agent, da.is_sale_agent
ORDER BY total_revenue_amount DESC
LIMIT 100
```

### Query 3 — Agents with a specific capability enabled (accreditation filter)

Finds all currently active agents who have a given capability enabled, with their profile and business context history. Useful for "how many agents can do X?" questions.

```sql
SELECT
    acc.id_agent,
    acc.id_user,
    acc.affiliation_type,
    acc.profile,
    acc.status                                    AS agent_status,
    acc.days_in_current_status,
    acap.type                                     AS capability_type,
    acap.status                                   AS capability_status,
    acap.business_context                         AS capability_business_context
FROM datalake_agent_accreditation.agent AS acc
INNER JOIN datalake_agent_accreditation.agent_capability AS acap
    ON acc.id_agent = acap.id_agent
WHERE acc.status = 'ACTIVE'
  AND acap.type   = 'DEMAND_VISIT_MANAGEMENT'    -- replace with desired capability type
  AND acap.status = 'ENABLED'
  AND acap.business_context = 'RENT'             -- omit this line for context-agnostic capabilities
ORDER BY acc.days_in_current_status DESC
```

### Query 4 — Active PFA relations and agent eligibility

Lists listings that currently have an active Preferred Fixed Agent assigned, with the agent's current program eligibility.

```sql
SELECT
    ppar.id_house,
    ppar.id_related_agent,
    ppar.business_context,
    ppar.ts_relation_started,   -- ⚠ synthetic for rows before 2025-06-03; not a true creation timestamp
    ppae.program,
    ppae.is_eligible,
    ppae.ts_status_started      AS eligibility_started
FROM datalake_ebdb_agents.preferred_property_agent_relation_history AS ppar
LEFT JOIN datalake_ebdb_agents.preferred_property_agent_program_eligibility AS ppae
    ON  ppar.id_related_agent = ppae.id_agent
    AND ppae.ts_status_ended IS NULL   -- current eligibility only
WHERE ppar.ts_relation_ended IS NULL   -- active PFA relations only
ORDER BY ppar.ts_relation_started DESC
```
