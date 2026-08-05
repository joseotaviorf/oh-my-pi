# Agent Profile Classification

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** Define **who the agent is** and **what they do** in business terms — the official classification rules for agent profiles used in analytics, dashboards, and ad-hoc queries.
- **Scope:** Human field agents and hub staff in the Agents domain. **Not** AI chatbots (Wall-E, Matthew, Matias, etc.) — see [`chatbot_sessions.md`](chatbot_sessions.md).
- **Parent entity:** Full table catalog, earnings, hubs, identity migration, and golden queries live in [`agents.md`](agents.md). **This document is the source of truth whenever the question is about agent profile classification.**
- **Status:** Implemented (ADR, Aug 3, 2026). Author: Anne Karoline Cardoso Macedo (Data Engineer @Agents).

> ⚠ **Three different "profile" concepts — do not mix them.** (1) **Business profile** (this doc) — who the agent is (`dw_agent.dim_agent.profile` + capability flags + hub/prospect context). (2) **Hub member role** — `datalake_hub_services.member_hub_allocation.profile` (`Visita`, `NEGOTIATION_EXECUTIVE`, …). (3) **Business function** — what part of the deal they earn for (demand conversion, TQC/TQA, CIQ); see the business-function table in [`agents.md`](agents.md).

---

## Glossary and Synonyms

| Term | Business profile | Notes |
|------|------------------|-------|
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

---

## Classification rules (source of truth)

Evaluate profiles in **priority order** when a user asks for a single label — some agents match multiple rules (e.g. QuintoAndar Agent + Demand Sale). For reporting, use the rule that matches the user's intent; when unclear, return all matching profiles or ask.

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

> **Legacy jargon mapping:** "Demand Agent" → Demand Sale and/or Demand Rent (confirm business context). "CIQ-Only" → Non-Demand Rent or Non-Demand Sale (confirm via `prospect.business_context_applied`). "Independent Agent" → QuintoAndar Agent with both demand and supply capabilities enabled — see capability flags on `agent` and [`agents.md`](agents.md) business-function table.

---

## Tables

| You need… | **Start here (DW)** | Notes |
|-----------|---------------------|-------|
| Current agent identity + `profile` + capability flags | **`dw_agent.dim_agent`** | Alias as `agent` in classification rules. |
| Point-in-time profile / capabilities (historical) | **`dw_agent.fact_agent_daily`** | Filter `dt_ref` (or `year`/`month`/`day` partitions). Same columns as `dim_agent` for classification. |
| Prospect `business_context_applied` (Non-Demand Rent/Sale) | **`dw_agent.dim_prospect_agent`** | Join `agent.uuid_person = prospect.uuid_person`. |
| Hub role EN / EA | **`datalake_hub_services.member_hub_allocation`** | Join `agent.uuid_person = hub.uuid_person`; filter `is_active = true` and latest `dt_reference` for current state. |
| Enrich fallback (no DW needed for profile) | `datalake_agent_accreditation.agent` | Same `profile` and `is_allow_*` columns; prefer DW for consistency with other agent joins. |

> For earnings, tiers, visits, hubs, and identity bridging, route through [`agents.md`](agents.md) — do not duplicate that catalog here.

---

## Primary dataset — `agent`

**Tables:** `dw_agent.dim_agent` or `dw_agent.fact_agent_daily` (alias **`agent`**).

| Topic | Fields used in classification |
|-------|--------------------------------|
| Profile type | `profile` — `AUTONOMOUS_BROKERAGE_AGENT`, `REDE`, `PRO_ACQUIRER`, `INSPECTOR`, `PHOTOGRAPHER`, … |
| Demand capabilities | `is_allow_demand_sale`, `is_allow_demand_rent`, `is_allow_visit` |
| Supply capability | `is_allow_supply_acquisition` |
| Partnership | `is_3p_partnership` |
| Join keys | `uuid_person`, `sk_agent`, `id_user` |

`fact_agent_daily` reconstructs capability flags from the agent event log per `dt_ref` — use it when the question is "what profile did this agent have on date X?".

---

## Auxiliary dataset — `prospect`

**Table:** `dw_agent.dim_prospect_agent` (alias **`prospect`**).

**Join:**

```sql
agent.uuid_person = prospect.uuid_person
```

**Required for:** **Non-Demand Rent** and **Non-Demand Sale** — distinguished by `prospect.business_context_applied` (`'RENT'` / `'SALE'`).

> One `uuid_person` may have prospect history; for accreditation context prefer rows where the person converted to agent or filter to the latest prospect record when multiple exist.

---

## Auxiliary dataset — `hub`

**Table:** `datalake_hub_services.member_hub_allocation` (alias **`hub`**).

**Join:**

```sql
agent.uuid_person = hub.uuid_person
```

**Required for:** **Negotiation Executive (EN)** and **Associated Executive (EA)** — `hub.profile IN ('NEGOTIATION_EXECUTIVE', 'ASSOCIATED_EXECUTIVE')`.

> Filter `hub.is_active = true` and the latest partition (`year`/`month`/`day` = today) for current hub role. EN/EA are hub **staff roles**, not visit-agent operation types — do not confuse with `hub.profile = 'Visita'` (visit workload), documented in [`agents.md`](agents.md).

---

## Relationship to other axes

| Axis | Where it lives | When to use |
|------|----------------|-------------|
| **Business profile** (this doc) | `dw_agent.dim_agent.profile` + rules above | "Who is this agent?" / "What type of agent?" / dashboard segmentation |
| **Business function** (earnings) | `is_allow_*` + `datalake_ebdb_clean.capability` | "What do they earn for?" — TQC, TQA, CIQ, conversion; see [`agents.md`](agents.md) |
| **Hub operation type** | `member_hub_allocation.profile` (`Visita`, `Vistoria`, …) | Daily workload / hub allocation — not the same as `agent.profile` |
| **Affiliation** | `affiliation_type` (`1P`/`3P`) | Program membership — orthogonal to profile rules |

---

## Dos and Don'ts

**Do:**

- Use **`dw_agent.dim_agent`** (or **`fact_agent_daily`** for history) as the primary `agent` source for all profile classification.
- Join **`dim_prospect_agent`** when classifying Non-Demand Rent/Sale.
- Join **`member_hub_allocation`** when classifying EN/EA; filter `is_active = true` and latest day partition.
- Confirm whether the user means **business profile** (this doc), **hub operation type** (`Visita`/`Vistoria`), or **business function** (TQC/CIQ/conversion) before writing SQL.
- Map legacy terms ("Demand Agent", "CIQ-Only", "Independent Agent") to the rules table or capability flags — see [`agents.md`](agents.md) Synonyms.

**Don't:**

- Treat `member_hub_allocation.profile = 'Visita'` as equivalent to `agent.profile = 'AUTONOMOUS_BROKERAGE_AGENT'` — different columns, different semantics.
- Classify AI chatbots with these rules — see [`chatbot_sessions.md`](chatbot_sessions.md).
- Use enrich `agent` when DW is available for profile questions — prefer `dw_agent.dim_agent` for join consistency.
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

> The `CASE` above is illustrative for the most common single-label questions. **Non-Demand Rent/Sale** and **EN/EA** require the auxiliary joins documented above — do not infer them from `dim_agent` alone.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-03 | Initial ADR — official business profile classification rules (Agents Data Team). |
