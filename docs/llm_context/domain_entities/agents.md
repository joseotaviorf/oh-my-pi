# Agents

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** QuintoAndar field agents and their full operating lifecycle — accreditation, identity & capabilities, hub allocation, performance tiers, brokerage/revenue earnings, and Preferred Fixed/Property Agent assignment. This file is the routing index for the domain; each sub-topic has its own entity doc.
- **Asset status / lifecycle:** prospect (intends to create account) → accreditation (CRECI validation, contract signature) → first commercial event (first listing / TQC referral / PPA) → activated → tiered → paid (revenue share) → churned/inactive.
- **Typical actions / events:** sign-up, qualification steps, contract signature, region/hub allocation, visit and listing operations, brokerage/CIQ commissioning, tier assignment.
- **Common metrics:** active agents (monthly), CIQ-active agents, agents per hub, brokerage/revenue earned per agent, active PFA relations, new-agent activation rate.
- **Source systems:** EBDB (agent, prospect, qualification, contract), Hub Services (membership, NE hierarchy), Amplitude (sign-up funnel), BigAgent (earnings/tiers/incentives), Nazaré (payments), Airtable/GSheets (ops manual data).
- **Related entities:** for visit metrics see [`visits.md`](visits.md); for AI chatbots (Wall-E, Matthew, Sauron, Dominic/Matias) see [`chatbot_sessions.md`](chatbot_sessions.md) and [`matthew.md`](matthew.md) — those are **not** field agents.

---

## Related Metric Entities

- None — no metric entity doc references the Agents domain as of 2026-08.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Agente / corretor** | Field agent | Multi-type — see [`agents_profile.md`](agents_profile.md) for classification rules. |
| **Agente de visita / Visita** | Visit agent | `profile = 'Visita'`; default scope for most business questions. |
| **Agente CIQ (program)** | Affiliation — enrolled in the CIQ (Corretor Integrado QuintoAndar) program | affiliation `1P`; nearest capability signal is `is_allow_supply_acquisition` / `is_allow_supply_conversion` on `dw_agent.dim_agent`. Overloaded with "CIQ (function)" below. |
| **Agente 3P / parceiro** | Third-party / partner-firm agent | `affiliation_type = '3P'` in `agent`; `is_3p_agent = true` in `dw_public.dim_agent`. |
| **Demand Agent / agente de demanda** | Conversion function — conducts visits and converts | `profile = 'Visita'` + capability `DEMAND_VISIT_MANAGEMENT ENABLED`; `revenue_role = DEMAND`. |
| **TQC (Traz Quem Compra)** | Demand-acquisition function on Sale — brings/qualifies the buyer lead | See [`agents_programs.md`](agents_programs.md). |
| **TQA (Traz Quem Aluga)** | Demand-acquisition function on Rent — rent counterpart of TQC | See [`agents_programs.md`](agents_programs.md). |
| **CIQ (function)** | Supply-acquisition function — agent who registers/brings the property | `revenue_role = SUPPLY`; distinct from the CIQ *program* above. See [`agents_payments.md`](agents_payments.md). |
| **PPA (Preferred Property Agent)** | Agent fixed to a listing (agent brought the supply) | Separate table from PFA — see [`agents_programs.md`](agents_programs.md). |
| **PFA (Preferred Fixed Agent)** | Agent fixed to a lead/visitor (usually first-visit) | Separate table from PPA — see [`agents_programs.md`](agents_programs.md). |
| **BIG_AGENT** | Newer brokerage/earnings model | `revenue_source = 'BIG_AGENT'` in `fact_partner_payments`. See [`agents_payments.md`](agents_payments.md). |
| **Nazaré** | Legacy per-offer brokerage / payment system | `revenue_source = 'NAZARE'`. |
| **Valid First Listing** | A first listing that survives property deduplication — a re-listed / duplicated property does NOT count again | Feeds CIQ payment eligibility and activation. See [`agents_performance.md`](agents_performance.md). |
| **Compra de Carteira** | CIQ_FULL rent listing-purchase — pricing, portfolio loss, eligibility | See [`agents_performance.md`](agents_performance.md). |
| **Ativação / activation** | ⚠ No single definition — first commercial event ≤60 days of registration, or first visit/listing/TQC/deal | See [`agents_accreditation.md`](agents_accreditation.md). Always confirm which definition the user means. |
| **Lead** | New visitor associated to an agent. Could be associated through demand-acquisition or distribution from QuintoAndar. | See this file (Tables) or [`agents_programs.md`](agents_programs.md). |
| **Corretor Capacity** | Capacity Agent. Agent that receives leads from QuintoAndar. | `is_passive_lead_receiver=TRUE`. |
| **Corretor Non-Capacity** | Non-Capacity Agent. Agent that doesn't receive leads from QuintoAndar. | `is_passive_lead_receiver=FALSE`. |
| **Imóveis na carteira** | Houses in the agent's wallet. Houses that were acquired by the agent. | agents’ `sk_user` on `id_ciq_user_sale` or `id_ciq_user_rent` (from `datalake_listing_deduplication.valid_first_listing`). |


---

## Tables — this doc is the index; each row routes to the doc that owns that topic

This domain is split by topic so an analyst (or TARS) loads only what a question needs. Each linked doc is a complete, independently-governed entity doc with its own Ownership, Tables, Dos and Don'ts, and Golden Queries — this file does not duplicate their column-level detail.

| You need… | Schema / table | Read |
|-----------|----------------|------|
| Legacy `sk_agent ↔ id_user` bridge | `dw_public.dim_agent` | this file (Golden Query below) |
| **Who is the agent / what type** (business profile classification), hub/NE allocation, tier performance metrics | `dw_agent.dim_agent`, `datalake_hub_services.member_hub_allocation`, `datalake_tiers.agent_performance` | [`agents_profile.md`](agents_profile.md) |
| Canonical agent identity, capabilities, prospect/accreditation funnel, daily state | `datalake_agent_accreditation.agent`, `dw_agent.fact_agent_daily` | [`agents_accreditation.md`](agents_accreditation.md) |
| BigAgent earnings, tiers, partner payments (Sale + Rent), Nazaré | `dw_agent_payments.fact_earnings`, `fact_partner_payments` | [`agents_payments.md`](agents_payments.md) |
| Valid First Listing / property dedup, CIQ Compra de Carteira (pricing, portfolio loss, eligibility) | `datalake_listing_deduplication.valid_first_listing`, `dw_ciq.fact_ciq_listing_purchase` | [`agents_performance.md`](agents_performance.md) |
| PFA/PPA relation and eligibility, TQC/TQA acquisition | `datalake_ebdb_agents.preferred_property_agent_relation_history`, `preferred_fixed_agent_history` | [`agents_programs.md`](agents_programs.md) |
| Visit funnel / completion metrics | `dw_visit.fact_visits` | [`visits.md`](visits.md) |
| Leads distributed to agent | `dw_visit.dim_visit` (`sk_visitor` is the lead and `sk_first_associated_agent` is the agent receiving this lead in visits where `visit_request_user_role <> 'AGENT'`) | [`visits.md`](visits.md) |

**Critical rules:**
- QuintoAndar is **mid-migration** from legacy agent services to the new Agent Domain — two ID systems coexist and are NOT interchangeable: `sk_agent_data`/`id_agent_data` (LEGACY, `dadosAgent` service) vs `sk_agent`/`id_agent` (NEW, Agent Domain). The column name `sk_agent` exists in BOTH `dw_public.dim_agent` (legacy) and `dw_agent.*` (new) with **different value spaces** (confirmed: they are two distinct tables in the repo, same `table_name`, different `database_name`) — never join them directly. Bridge through a table that carries both keys (`dw_agent.fact_agent_daily`, documented in [`agents_accreditation.md`](agents_accreditation.md)), or through `id_user` as in the Golden Query below.
- Three orthogonal axes describe an agent — always confirm which the user means: **business profile** (who they are, [`agents_profile.md`](agents_profile.md)), **hub operation type** (what work they do in the hub, `member_hub_allocation.profile`), and **business function** (what they earn for — demand conversion, TQC/TQA, CIQ, see [`agents_payments.md`](agents_payments.md) and [`agents_programs.md`](agents_programs.md)). Affiliation (`1P`/`3P`) is a fourth, independent axis.

## Key Metrics

No metric entity doc owns the Agents domain yet — use [Related Metric Entities](#related-metric-entities). The bullets below are **component** metrics; each linked doc is the source of truth for grain and filters.

### Component / exploratory metrics

- **Active agents (monthly):** `COUNT(DISTINCT id_agent)` on `dw_agent.fact_agent_daily` where `is_agent_active = true` — see [`agents_accreditation.md`](agents_accreditation.md).
- **CIQ-active agents:** agents with supply-acquisition capability (`is_allow_supply_acquisition` / `is_allow_supply_conversion`) on `dw_agent.dim_agent` / `fact_agent_daily` — see [`agents_profile.md`](agents_profile.md).
- **Agents per hub:** `COUNT(DISTINCT id_user)` on `datalake_hub_services.member_hub_allocation` where `is_active = true` — see [`agents_profile.md`](agents_profile.md).
- **Brokerage / revenue earned per agent:** `SUM` on `dw_agent_payments.fact_earnings` / `fact_partner_payments` — see [`agents_payments.md`](agents_payments.md).
- **Active PFA relations:** current rows on `datalake_ebdb_agents.preferred_fixed_agent_history` — see [`agents_programs.md`](agents_programs.md).
- **New-agent activation rate:** first commercial event within the accreditation window — definition is ambiguous; confirm with [`agents_accreditation.md`](agents_accreditation.md) before computing.

## Relationships with other entities

- **Agents ↔ Accreditation (1:1 identity):** `dw_public.dim_agent.id_user = datalake_agent_accreditation.agent.id_user` (legacy → new Agent Domain). Do **not** join the two `sk_agent` columns — see [`agents_accreditation.md`](agents_accreditation.md).
- **Agents ↔ Profile / hub (1:N daily allocation):** `agent.uuid_person = member_hub_allocation.uuid_person` (`is_active = true`) — see [`agents_profile.md`](agents_profile.md).
- **Agents ↔ Payments (1:N):** `sk_agent` / `sk_partner` on `dw_agent_payments.fact_earnings` and `fact_partner_payments` — see [`agents_payments.md`](agents_payments.md).
- **Agents ↔ Performance (1:N listings):** `sk_user` on `id_ciq_user_sale` / `id_ciq_user_rent` in `datalake_listing_deduplication.valid_first_listing` — see [`agents_performance.md`](agents_performance.md).
- **Agents ↔ Programs (1:N PFA/PPA):** `preferred_fixed_agent_history` / `preferred_property_agent_relation_history` — see [`agents_programs.md`](agents_programs.md).
- **Agents ↔ Visits (1:N):** `dw_visit.fact_visits` / `dim_visit.sk_visitor` — see [`visits.md`](visits.md).
- **Agents ↛ Chatbot sessions:** Wall-E, Matthew, Sauron, Dominic/Matias are **not** field agents — see [`chatbot_sessions.md`](chatbot_sessions.md).

## Dos and Don'ts

**Do:**
- Bridge legacy `sk_agent`/`id_user` to the new Agent Domain identity through `id_user`, joining `dw_public.dim_agent` to `datalake_agent_accreditation.agent` (see Golden Query below) — never assume the two `sk_agent` columns share a value space.
- Translate legacy jargon ("Demand Agent", "CIQ-Only", "Independent Agent") to capability filters via the linked sub-domain docs, not literal column values.

**Don't:**
- Assume AI agents (Wall-E, Matthew, Sauron, Dominic/Matias) belong in this entity — see [`chatbot_sessions.md`](chatbot_sessions.md).
- Duplicate column-level detail here — each linked sub-domain doc is the source of truth for its own tables.

## Golden Queries

### Query 1 — Bridge legacy agent identity to the new Agent Domain

Resolves the legacy `dw_public.dim_agent` key to the canonical Agent Domain `id_agent`, for any analysis that starts from a legacy table and needs to join into the new accreditation/earnings stack.

```sql
SELECT
    legacy.sk_agent   AS legacy_sk_agent,
    legacy.id_user,
    agent.id_agent,
    agent.affiliation_type,
    agent.status
FROM dw_public.dim_agent AS legacy
JOIN datalake_agent_accreditation.agent AS agent
    ON legacy.id_user = agent.id_user
WHERE agent.status = 'ACTIVE';
```

> `id_user` is the stable bridge key between the legacy star schema and the new accreditation layer. See [`agents_accreditation.md`](agents_accreditation.md) for the full `agent` table and the identity-migration warning.
