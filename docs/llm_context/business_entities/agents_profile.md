# Agent Profile Classification

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** Define **who the agent is** and **what they do** in business terms — the official classification rules for agent profiles, plus the two adjacent domains that answer "which hub is this agent in" and "how is this agent performing for tiering": hub/NE allocation and tier performance metrics.
- **Scope:** Human field agents and hub staff in the Agents domain. **Not** AI chatbots (Wall-E, Matthew, Matias, etc.) — see [`chatbot_sessions.md`](chatbot_sessions.md).
- **Parent entity:** Identity, accreditation, earnings/payments, and the identity-migration warning live in [`agents.md`](agents.md) and its linked sub-domain docs. This document is the source of truth for agent profile classification, hub allocation, and tier performance metrics.
- **Status:** Implemented (ADR, Aug 3, 2026). Author: Anne Karoline Cardoso Macedo (Data Engineer @Agents).

> ⚠ **Three different "profile" concepts — do not mix them.** (1) **Business profile** (this doc) — who the agent is (`dw_agent.dim_agent.profile` + capability flags + hub/prospect context). (2) **Hub member role** — `datalake_hub_services.member_hub_allocation.profile` (`Visita`, `NEGOTIATION_EXECUTIVE`, …), also documented in this file. (3) **Business function** — what part of the deal they earn for (demand conversion, TQC/TQA, CIQ); see [`agents.md`](agents.md).

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Agente QuintoAndar** / **corretor 5A** | QuintoAndar Agent | Default accredited broker; `profile = 'AUTONOMOUS_BROKERAGE_AGENT'`. |
| **Agente de demanda venda** / **Demand Sale** | Demand Sale | Visit/conversion on For-Sale; `is_allow_demand_sale = true`. |
| **Agente de demanda aluguel** / **Demand Rent** | Demand Rent | Visit/conversion on For-Rent; `is_allow_demand_rent = true`. |
| **Agente 3P** / **parceiro REDE** | 3P | Third-party / partner-firm agent; `profile = 'REDE'` or `is_3p_partnership = true`. |
| **Embaixador** | Embaixador | Supply acquirer program; `profile = 'PRO_ACQUIRER'`. |
| **Vistoriador** / **Inspector** | Inspector | Property inspections; `profile = 'INSPECTOR'`. |
| **Fotógrafo** / **Photographer** | Photographer | Photo sessions; `profile = 'PHOTOGRAPHER'`. |
| **CIQ não-demanda aluguel** | Non-Demand Rent | Supply-only on Rent; no visit capability + prospect context RENT. |
| **CIQ não-demanda venda** | Non-Demand Sale | Supply-only on Sale; no visit capability + prospect context SALE. |
| **EN** / **Executivo de Negociação** | Negotiation Executive (EN) | Hub staff who negotiate offers until CCV; hub `profile = 'NEGOTIATION_EXECUTIVE'`. |
| **EA** / **Executivo Associado** | Associated Executive (EA) | Hub manager over multiple business units; hub `profile = 'ASSOCIATED_EXECUTIVE'`. |
| **Visita / Vistoria / SessãoFotos** | Hub operation types | `member_hub_allocation.profile` values — the work a member does in the hub, not the business profile above. |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Current agent identity + `profile` + capability flags | `dw_agent.dim_agent` |
| Point-in-time profile / capabilities (historical) | `dw_agent.fact_agent_daily` |
| Prospect `business_context_applied` (Non-Demand Rent/Sale) | `dw_agent.dim_prospect_agent` |
| Hub role / NE / EA / daily hub workload | `datalake_hub_services.member_hub_allocation` |
| Tier performance metrics feeding tier calculation | `datalake_tiers.agent_performance` |
| CIQ first-listing validation for tiers | `datalake_tiers.ciq_first_listing` |
| Enrich fallback (no DW needed for profile) | `datalake_agent_accreditation.agent` (see [`agents_accreditation.md`](agents_accreditation.md)) |

**Critical rules:**
- Evaluate business profiles in **priority order** — some agents match multiple rules (e.g. QuintoAndar Agent + Demand Sale). When unclear, return all matching profiles or ask.
- `member_hub_allocation.profile = 'Visita'` is a **hub operation type**, not the same column or value space as `dw_agent.dim_agent.profile` (business profile).
- `datalake_tiers.ciq_first_listing` vs `datalake_listing_deduplication.valid_first_listing` (see [`agents_performance.md`](agents_performance.md)): both validate a dedup-gated first listing, but `ciq_first_listing` is the CIQ-consultant / tiers scope (general rule: published ≥2 days, or signed contract within 60 days of first publication); `valid_first_listing` is the broader dedup/activation source.

## Classification rules (source of truth)

| Business profile | Rule | Source alias |
|------------------|------|--------------|
| **QuintoAndar Agent** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT'` | `agent` |
| **Demand Sale** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND agent.is_allow_demand_sale = TRUE` | `agent` |
| **Demand Rent** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND agent.is_allow_demand_rent = TRUE` | `agent` |
| **3P** | `agent.profile = 'REDE' OR agent.is_3p_partnership = TRUE` | `agent` |
| **Embaixador** | `agent.profile = 'PRO_ACQUIRER'` | `agent` |
| **Inspector** | `agent.profile = 'INSPECTOR'` | `agent` |
| **Photographer** | `agent.profile = 'PHOTOGRAPHER'` | `agent` |
| **Non-Demand Rent** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND agent.is_allow_visit = FALSE AND agent.is_allow_supply_acquisition = TRUE AND prospect.business_context_applied = 'RENT'` | `agent` + `prospect` |
| **Non-Demand Sale** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND agent.is_allow_visit = FALSE AND agent.is_allow_supply_acquisition = TRUE AND prospect.business_context_applied = 'SALE'` | `agent` + `prospect` |
| **Negotiation Executive (EN)** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND hub.profile = 'NEGOTIATION_EXECUTIVE'` | `agent` + `hub` |
| **Associated Executive (EA)** | `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' AND hub.profile = 'ASSOCIATED_EXECUTIVE'` | `agent` + `hub` |

> **Legacy jargon mapping:** "Demand Agent" → Demand Sale and/or Demand Rent (confirm business context). "CIQ-Only" → Non-Demand Rent or Non-Demand Sale. "Independent Agent" → QuintoAndar Agent with both demand and supply capabilities enabled.

### Auxiliary joins

- **`prospect`** — `dw_agent.dim_prospect_agent`, join `agent.uuid_person = prospect.uuid_person`. Required for Non-Demand Rent/Sale.
- **`hub`** — `datalake_hub_services.member_hub_allocation`, join `agent.uuid_person = hub.uuid_person`, filter `hub.is_active = true` and the latest day partition. Required for EN/EA.

---

## Hub / NE Allocation

**Table:** `datalake_hub_services.member_hub_allocation`. Grain: **one row per `(id_user, dt_reference)`**, partitioned `year/month/day`. Replaces the deprecated `agent_hub_alocation` (typo: one `l`) and `agent_hub_relation`.

| Topic | Fields |
|-------|--------|
| Member identity | `id_member_relationship`, `id_member_profile`, `id_user`, `id_main_user`, `id_agent`, `uuid_person`, `uuid_company` |
| Hub / region | `id_business_unit`, `hub_name`, `id_region`, `city_group`, `city_name`, `short_region_name` |
| Classification | `profile`, `agent_type`, `business_context`, `lead_types`, `is_active` |
| Parent member (NE / manager) | `id_parent_user`, `id_parent_main_user`, `id_parent_agent`, `user_parent_name`, `user_parent_email` |

> Filter `is_active = true` for current allocation. NE moved from dedicated `negotiation_executive_*` columns (old table) to **parent member** columns.

## Tier Performance Metrics

**Table:** `datalake_tiers.agent_performance` (EAV). Grain: **one row per `(id_user, id_agent, id_metric_period, metric_name)`**. All accredited agents × active periods are cross-joined; missing combos filled `metric_value = 0, is_valid = true`. Compound ratios (`BP2CCV`, `TP2CS`, `OS2CCV_BY`) capped at 1.0. Pivot on `metric_name` for wide views.

**Table:** `datalake_tiers.ciq_first_listing`. Grain: **one row per `id_house`** — CIQ-consultant first-listing validity verdict feeding tier calculation, with the general publication-or-contract compliance rule: the listing must remain published at least 2 days, or have a signed contract within 60 days of first publication.

| Topic | Fields |
|-------|--------|
| Keys | `id_house`, `id_user`, `id_agent`, `id_partner`, `uuid_person` |
| Validity verdict | `is_first_listing_valid`, `invalidation_reasons`, `is_valid_hybrid`, `is_valid_compliance_general_rule` |

---

## Dos and Don'ts

**Do:**

- Use **`dw_agent.dim_agent`** (or **`fact_agent_daily`** for history) as the primary `agent` source for all profile classification.
- Join **`member_hub_allocation`** when classifying EN/EA; filter `is_active = true` and latest day partition.
- Filter daily tables (`member_hub_allocation`) by integer `year = X AND month = X AND day = X`, not `dt_reference BETWEEN` (scans all partitions).
- Confirm whether the user means **business profile** (this doc), **hub operation type** (`Visita`/`Vistoria`), or **business function** (TQC/CIQ/conversion, see [`agents.md`](agents.md)) before writing SQL.

**Don't:**

- Treat `member_hub_allocation.profile = 'Visita'` as equivalent to `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT'` — different columns, different semantics.
- Use `datalake_hub_services.agent_hub_alocation` (deprecated, typo `alocation`) or `agent_hub_relation` (deprecated) — use `member_hub_allocation` with `is_active = true`.
- Classify AI chatbots with these rules — see [`chatbot_sessions.md`](chatbot_sessions.md).
- Assume profiles are mutually exclusive — an agent can be QuintoAndar Agent **and** Demand Sale **and** match hub allocation separately.

---

## Golden Queries

### Query 1 — Classify agents by business profile

Current-state snapshot using `dim_agent` only (profiles that do not need prospect/hub joins). Extend with LEFT JOINs to `dim_prospect_agent` and `member_hub_allocation` for Non-Demand and EN/EA rules.

```sql
SELECT
    agent.sk_agent,
    agent.uuid_person,
    agent.profile,
    agent.is_allow_demand_sale,
    agent.is_allow_demand_rent,
    agent.is_allow_visit,
    agent.is_allow_supply_acquisition,
    agent.is_3p_partnership,
    CASE
        WHEN agent.profile = 'INSPECTOR' THEN 'Inspector'
        WHEN agent.profile = 'PHOTOGRAPHER' THEN 'Photographer'
        WHEN agent.profile = 'PRO_ACQUIRER' THEN 'Embaixador'
        WHEN agent.profile = 'REDE' OR agent.is_3p_partnership = TRUE THEN '3P'
        WHEN agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT'
             AND agent.is_allow_demand_sale = TRUE THEN 'Demand Sale'
        WHEN agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT'
             AND agent.is_allow_demand_rent = TRUE THEN 'Demand Rent'
        WHEN agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT' THEN 'QuintoAndar Agent'
        ELSE 'Other'
    END AS business_profile
FROM dw_agent.dim_agent AS agent
WHERE agent.status = 'ACTIVE';
```

### Query 2 — Active agents per hub (latest day)

Daily workload snapshot — active members per hub by business context and profile.

```sql
SELECT
    mha.hub_name,
    mha.city_name,
    mha.business_context,
    mha.profile,
    COUNT(DISTINCT mha.id_user) AS number_agents
FROM datalake_hub_services.member_hub_allocation AS mha
WHERE mha.year      = YEAR(CURRENT_DATE)
  AND mha.month     = MONTH(CURRENT_DATE)
  AND mha.day       = DAY(CURRENT_DATE)
  AND mha.is_active = true
GROUP BY 1, 2, 3, 4
ORDER BY number_agents DESC;
```

> `YEAR`/`MONTH`/`DAY` follow Trino/Presto syntax. Partition columns are integers — never filter the daily tables with `dt_reference BETWEEN`.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-03 | Initial ADR — official business profile classification rules (Agents Data Team). |
