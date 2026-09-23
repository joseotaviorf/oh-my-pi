# Agents — Programs (PFA / PPA / TQC / TQA)

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** Lead/listing-assignment programs an agent can be enrolled in — PFA (fixed to a lead), PPA (fixed to a listing), and the demand-acquisition functions TQC/TQA (bringing a buyer or tenant lead) — distinct from the agent's business profile or capabilities.
- **Asset status / lifecycle:** relation created → active (`ts_relation_ended IS NULL`) → ended.
- **Typical actions / events:** PFA/PPA assignment, eligibility check, lead referral (TQC/TQA).
- **Common metrics:** active PFA/PPA relations, TQC/TQA referral count.
- **Source systems:** EBDB (agent, lead referral, PFA/PPA relation history).
- **Related entities:** for the full business-function definition of TQC/TQA/CIQ, see [`agents.md`](agents.md). For payment lines on these functions, see [`agents_payments.md`](agents_payments.md).

---

## Related Metric Entities

- None — no metric entity doc references the Agents domain as of 2026-08.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **PPA (Preferred Property Agent)** | Agent fixed to a **listing** (agent brought the supply) | `preferred_property_agent_relation_history` — a **separate table from PFA**, despite the similar name. |
| **PFA (Preferred Fixed Agent)** | Agent fixed to a **lead/visitor** (usually first-visit) | `preferred_fixed_agent_history` — a **different table and pipeline** from PPA, not a shared one. |
| **TQC (Traz Quem Compra)** | Demand-acquisition function on Sale — agent who brings/qualifies the buyer lead | Capability `DEMAND_ACQUISITION`; `business_context = 'SALE'` in `agent_lead_referral`; `status` of referral  invite (pending, accepted, expired, or cancelled) in `agent_lead_referral` |
| **TQA (Traz Quem Aluga)** | Demand-acquisition function on Rent — rent counterpart of TQC | Capability `DEMAND_ACQUISITION`; `business_context = 'RENT'` in `agent_lead_referral`; `status` of referral  invite (pending, accepted, expired, or cancelled) in `agent_lead_referral` |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| PPA relation history (listing-side) | `datalake_ebdb_agents.preferred_property_agent_relation_history` |
| PPA program eligibility | `datalake_ebdb_agents.preferred_property_agent_program_eligibility` |
| PFA relation history (lead/visitor-side) | `datalake_ebdb_agents.preferred_fixed_agent_history` |
| TQC/TQA lead referral (raw invite) | `datalake_ebdb_clean.agent_lead_referral` |
| TQC/TQA referral funnel, same-agent conversion, first events | `datalake_agent_performance.fact_agent_demand_acquisition` (see [`agents_performance.md`](agents_performance.md)) |
| TQC/TQA first/last milestone timestamps | `dw_agent_performance.dim_agent_milestone` (see [`agents_performance.md`](agents_performance.md)) |
| TQC/TQA payment lines | `dw_agent_payments.fact_partner_payments` (see [`agents_payments.md`](agents_payments.md)) |

**Critical rules:**
- **PPA and PFA are two distinct tables and pipelines**, not one shared table split by a column — do not query one expecting the other's rows or columns.
- Filter `ts_relation_ended IS NULL` for active PPA relations, `ts_status_ended IS NULL` for current PPA eligibility, and `is_enabled = true` + `ts_status_ended IS NULL` for active PFA relations.
- `ts_relation_started` (PPA) is **synthetic** (backfilled) for rows created on **2025-06-03** (table creation date) — not a true creation timestamp; PFA has a separate genuine `ts_relation_created`.

## `preferred_property_agent_relation_history` (PPA)

Grain: **one row per PPA relation revision** (`related_as = 'PREFERRED_PROPERTY_AGENT'` in the source EBDB audit). Join on `id_house` / `id_related_agent`.

| Topic | Fields |
|-------|--------|
| Keys | `id_house_listing_relation` (PK), `id_house`, `id_listing_business_context`, `id_related_agent`, `id_user_related_agent`, `business_context` |
| Validity | `ts_relation_started`, `ts_relation_ended` |

> `ts_relation_started` has special backfill logic for rows created on 2025-06-03: it resolves to the first-listing date if published between program launch (2025-02-12) and table creation, or to 2025-02-12 itself if published earlier. There is **no `origin`/reason column on this table** — that column lives on the separate PFA table below.

## `preferred_fixed_agent_history` (PFA)

Grain: **one row per PFA status period** — a timeline of agent-visitor preferences with status changes, one row per period a specific agent was preferred for a visitor in a given region and business context.

| Topic | Fields |
|-------|--------|
| Keys | `id` (PK), `id_snapshot`, `id_user_visit_preferences`, `id_region`, `id_visitor`, `id_agent`, `id_user_agent` |
| Classification | `business_context`, `origin` (source of the preference relationship), `is_enabled` |
| Validity | `ts_relation_created`, `ts_status_started`, `ts_status_ended` |

> `id_agent` is the legacy `id_agent_data` key; use `id_user_agent` (resolved EBDB `user.id`) for joins to `dim_user` and visit facts.

## TQC / TQA

Identified via capability `DEMAND_ACQUISITION` and rows in `datalake_ebdb_clean.agent_lead_referral` (`business_context = 'SALE'` for TQC, `'RENT'` for TQA). For **conversion analytics** (progression, same-agent attribution, first event structs), use `datalake_agent_performance.fact_agent_demand_acquisition` — see [`agents_performance.md`](agents_performance.md). Payment lines land on `dw_agent_payments.fact_partner_payments` with `incentive_system = DEMAND_ACQUISITION_FS` / `DEMAND_ACQUISITION_FR`.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when the question asks for an **official**, **MBR**, or **OKR** number. None exist for this entity yet.

### Component / exploratory metrics

- **Active PPA relations:** `COUNT(DISTINCT id_house)` / `COUNT(DISTINCT id_related_agent)` on `datalake_ebdb_agents.preferred_property_agent_relation_history` where `ts_relation_ended IS NULL`.
- **PPA-eligible agents:** `COUNT(DISTINCT id_agent)` on `datalake_ebdb_agents.preferred_property_agent_program_eligibility` where `is_eligible = true` and `ts_status_ended IS NULL`.
- **Active PFA relations:** `COUNT(DISTINCT id_visitor)` on `datalake_ebdb_agents.preferred_fixed_agent_history` where `is_enabled = true` and `ts_status_ended IS NULL`.
- **TQC referrals:** `COUNT(*)` on `datalake_ebdb_clean.agent_lead_referral` where `business_context = 'SALE'`; split by `status` (pending, accepted, expired, cancelled).
- **TQA referrals:** same table where `business_context = 'RENT'`.
- **TQC/TQA payment lines:** `SUM(revenue_amount)` on `dw_agent_payments.fact_partner_payments` where `incentive_system IN ('DEMAND_ACQUISITION_FS', 'DEMAND_ACQUISITION_FR')` — see [`agents_payments.md`](agents_payments.md).

## Relationships with other entities

- **Programs ↔ Agent identity (1:N):** PPA joins on `id_related_agent` / `id_user_related_agent`; PFA joins on `id_user_agent` (**not** `id_agent`, which is the legacy `id_agent_data` key); PPA eligibility `id_agent` is also the **legacy** `id_agent_data` key. Bridge through [`agents_accreditation.md`](agents_accreditation.md) / the identity-migration warning in [`agents.md`](agents.md).
- **Programs ↔ House / listing (PPA, 1:N):** `preferred_property_agent_relation_history.id_house` / `id_listing_business_context` — one relation revision per house and business context.
- **Programs ↔ Visitor / lead (PFA, 1:N):** `preferred_fixed_agent_history.id_visitor`; TQC/TQA referrals join `agent_lead_referral.id_lead` to `dim_user.sk_user`.
- **Programs ↔ Payments (TQC/TQA, 1:N):** `dw_agent_payments.fact_partner_payments` with `incentive_system = DEMAND_ACQUISITION_FS` (Sale / TQC) or `DEMAND_ACQUISITION_FR` (Rent / TQA). See [`agents_payments.md`](agents_payments.md).
- **Programs ↔ Profile:** enrollment is independent of business profile — classify who the agent is in [`agents_profile.md`](agents_profile.md), then join the program tables above.

## Dos and Don'ts

**Do:**

- Query **PPA** (`preferred_property_agent_relation_history`) for listing-side assignment and **PFA** (`preferred_fixed_agent_history`) for lead/visitor-side assignment — they are separate tables with separate grains.
- Filter `ts_relation_ended IS NULL` (active PPA), `ts_status_ended IS NULL` (current PPA eligibility / current PFA status), and `is_enabled = true` (active PFA).
- Confirm `business_context` (`SALE` vs `RENT`) before counting TQC/TQA referrals — they use the same capability and table, split only by this column.

**Don't:**

- Assume PFA and PPA share one table — a query joining `preferred_property_agent_relation_history` expecting an `origin` or `is_enabled` column will fail; those live on `preferred_fixed_agent_history` only.
- Assume `ts_relation_started` (PPA) is a true creation timestamp for rows created on 2025-06-03 — it is backfilled.
- Use `agent_lead_referral` alone when the question is only the **raw invite** — for referral **funnel and same-agent metrics**, use `fact_agent_demand_acquisition` per [`agents_performance.md`](agents_performance.md).

---

## Golden Queries

### Query 1 — Active PPA relations by business context

```sql
SELECT
    r.business_context,
    COUNT(DISTINCT r.id_house)          AS active_houses,
    COUNT(DISTINCT r.id_related_agent)  AS active_agents
FROM datalake_ebdb_agents.preferred_property_agent_relation_history AS r
WHERE r.ts_relation_ended IS NULL
GROUP BY 1
ORDER BY active_houses DESC;
```

> Join `datalake_ebdb_agents.preferred_property_agent_program_eligibility` (filter `ts_status_ended IS NULL`) to check whether the agent is still eligible to hold the relation.

### Query 2 — Active PFA relations by origin

```sql
SELECT
    p.business_context,
    p.origin,
    COUNT(DISTINCT p.id_visitor) AS visitors_with_fixed_agent,
    COUNT(DISTINCT p.id_agent)   AS distinct_fixed_agents
FROM datalake_ebdb_agents.preferred_fixed_agent_history AS p
WHERE p.is_enabled = true
  AND p.ts_status_ended IS NULL
GROUP BY 1, 2
ORDER BY visitors_with_fixed_agent DESC;
```

> `id_agent` is the legacy `id_agent_data` key — join `id_user_agent` (not `id_agent`) to `dim_user` or visit facts.
