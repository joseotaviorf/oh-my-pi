# Agents — Payments & Earnings

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** BigAgent and Nazaré earnings, partner payments (agents and companies), tier assignments, and For-Rent broker share — the "how much did this agent get paid, and for what" domain.
- **Asset status / lifecycle:** earning calculated → tier assigned → payment line created (`fact_partner_payments`) → paid / invalidated / replaced.
- **Typical actions / events:** BigAgent earning calculation, tier assignment, partner payment generation, revenue-share reconciliation between BigAgent and Nazaré.
- **Common metrics:** total revenue paid by incentive system, earnings by tier, partner payment count by revenue source.
- **Source systems:** BigAgent (earnings/tiers/incentives), Nazaré (legacy per-offer brokerage/payments).
- **Related entities:** for the business-function definitions (demand conversion, TQC/TQA, CIQ) see [`agents.md`](agents.md). For PFA/PPA and TQC/TQA program mechanics, see [`agents_programs.md`](agents_programs.md).

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **BIG_AGENT** | Newer brokerage/earnings model | `revenue_source = 'BIG_AGENT'` in `fact_partner_payments`; earning-level detail in `fact_earnings`. |
| **Nazaré** | Legacy per-offer brokerage / payment system | `revenue_source = 'NAZARE'`. |
| **Tier** | Partner performance bracket that scales revenue share | `dim_tier` (rules), `fact_partner_tier` (assignment). |
| **Revenue role** | `DEMAND` vs `SUPPLY` side of a payment line | See the business-function table in [`agents.md`](agents.md). |
| **Incentive system** | The specific earning program a payment line belongs to (e.g. `DEMAND_CONVERSION_FS`, `SUPPLY_ACQUISITION_FR`) | One offer/contract can have multiple lines, one per incentive system. |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Partner payments to agents and companies (Sale + Rent) | `dw_agent_payments.fact_partner_payments` |
| Earnings KPIs, dashboards, agent/tier joins | `dw_agent_payments.fact_earnings` |
| Earning source status / failure context | `dw_agent_payments.dim_earning_sources` |
| Tier score rules | `dw_agent_payments.dim_tier` |
| Partner tier assignments | `dw_agent_payments.fact_partner_tier` |
| Calculation status audit trail | `dw_agent_payments.fact_earning_calculation_log` |
| For-Rent contract broker share (revision history) | `datalake_big_agent.brokerage_share_history` |
| Sale offer detail for a payment row | `dw_sale.fact_offers` (join on `sk_offer`) |
| Rent contract detail for a payment row | `dw_rent.fact_contracts` (join on `sk_contract`) |

**Critical rules:**
- **DW first:** always query `dw_agent_payments.fact_partner_payments` / `fact_earnings` before their enrich counterparts (`datalake_agent_payments.partner_payments`, `datalake_big_agent.earnings`) — enrich is only for pipeline debugging or a column not yet projected to DW.
- **Double-count trap:** always filter `revenue_source` (and usually `incentive_system` / `revenue_role`) before any `SUM` on `fact_partner_payments` — the table UNIONs Big Agent and Nazaré paths and can emit multiple rows per offer/contract.
- **Name collision:** `datalake_agent_payments` (enrich) ≠ `dw_agent_payments` (DW) — same domain word, different layer.

---

## `dw_agent_payments.fact_partner_payments`

Grain: **one row per `sk_partner_payment`**. A single Sale offer can have multiple rows (e.g. `DEMAND_CONVERSION_FS` + `DEMAND_ACQUISITION_FS` TQC + `SUPPLY_ACQUISITION_FS` CIQ; or side-by-side `BIG_AGENT` vs `NAZARE` rows for reconciliation).

| Topic | Fields |
|-------|--------|
| Keys | `sk_partner_payment` (PK), `sk_earning`, `sk_earning_source`, `sk_house`, `sk_contract`, `sk_offer`, `sk_business_unit`, `sk_tier`, `sk_user`, `sk_person`, `sk_company` |
| Discriminators | `business_context` (`SALE`/`RENT`), `revenue_source` (`BIG_AGENT`/`NAZARE`), `revenue_role` (`DEMAND`/`SUPPLY`), `incentive_system`, `revenue_receiver_type` (`AGENT`/`COMPANY`) |
| Amounts | `ticket_base_amount`, `brokerage_fee`, `brokerage_amount`, `revenue_amount`, `revenue_percentage` |
| Flags | `is_3p_lead_gen_offer`, `is_fifty_revenue_share`, `is_crcc_revenue_share`, `is_tier_revenue_share` |
| Timing | `ts_created`, `ts_updated`; partitions `year/month/day` from `ts_created` |

## `dw_agent_payments.fact_earnings`

Grain: **one row per `sk_earning`** (BigAgent earning id). Excludes `invalidation_reason = 'PRODUCT_TESTING'`.

| Topic | Fields |
|-------|--------|
| Keys | `sk_earning` (PK), `sk_replacement_earning`, `sk_earning_source` |
| Actor keys | `sk_author`, `sk_invalidation_author` — resolved to `sk_person` via `person_sks`; null when SYSTEM-authored |
| Tier context | `sk_tier`, `sk_partner_tier`, `partner_tier_name`, `incentive_system` |
| Amounts | `calculation_base_amount`, `revenue_amount`, `revenue_percentage` |
| Invalidation | `invalidation_reason`, `ts_invalidated`, `is_invalid`, `is_replaced` |
| Flags | `is_calculated`, `is_rent_contract`, `is_sales_flow`, `is_manual_calculation` |

> `sk_author` / `sk_invalidation_author` are **person surrogate keys** (`sk_person`), not raw BigAgent author ids — bridge to `id_user` through `datalake_person.person_sks`.

## `dw_agent_payments.dim_tier` / `fact_partner_tier`

`dim_tier` — one row per `sk_tier`: `incentive_system`, `tier_name`, `tier_priority`, `classifier_min_score`, `qualifier_min_score`. `fact_partner_tier` — one row per `sk_partner_tier` (assignment): `sk_tier`, `sk_person`, `sk_company`, `is_valid`, `dt_validity_started`, `dt_validity_ended`.

## `datalake_big_agent.brokerage_share_history` — For-Rent broker share

Grain: **one row per `(id_revision, id_contract)`**. Columns: `id_revision`, `id_contract`, `agent_brokerage_share`, `ts_revision`, `dt_load`. Apply `ROW_NUMBER()`/`LAST_VALUE` to get the current share per contract — this is NOT one row per contract. The EBDB `contract.agent_brokerage_share` column is removed; do not read it.

## Dos and Don'ts

**Do:**

- For **partner payments to agents and companies**, always query `dw_agent_payments.fact_partner_payments` first.
- Resolve earning authors through `sk_person` (`sk_author`, `sk_invalidation_author`) via `datalake_person.person_sks`, not raw BigAgent author ids.
- Filter `revenue_source` in `fact_partner_payments` before any aggregation (Big Agent vs Nazaré UNION).

**Don't:**

- Confuse `fact_partner_payments` (unified partner payment lines) with `brokerage_share_history` (For-Rent contract broker share revision history) — different scopes, grains, and DAGs.
- Expect `sk_revenue_share`, `sk_incentive_engine`, or `sk_unresolved_earning` on `fact_earnings` — use enrich `datalake_big_agent.earnings` or the `has_unresolved_earning` flag instead.
- Read EBDB `contract.agent_brokerage_share` (removed) or `dw_public.dim_agent.rede_partner` (deprecated).

---

## Golden Queries

### Query 1 — Partner payments by revenue source (BigAgent vs Nazaré)

```sql
SELECT
    fp.revenue_source,
    fp.revenue_role,
    fp.incentive_system,
    COUNT(DISTINCT fp.sk_offer)     AS offers,
    SUM(fp.revenue_amount)          AS total_amount
FROM dw_agent_payments.fact_partner_payments AS fp
WHERE fp.year = 2026
  AND fp.month = 6
  AND fp.business_context = 'SALE'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

> Join `dw_sale.fact_offers` on `sk_offer` for offer-level attributes. For Rent rows, join `dw_rent.fact_contracts` on `sk_contract`.

### Query 2 — BigAgent earnings by incentive system

```sql
SELECT
    fe.incentive_system,
    fe.is_calculated,
    fe.is_invalid,
    COUNT(*)              AS earnings,
    SUM(fe.revenue_amount) AS total_revenue
FROM dw_agent_payments.fact_earnings AS fe
WHERE fe.year = 2026
  AND fe.month = 6
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

> Filter `has_unresolved_earning = false` for fully resolved earnings. Join `dw_agent_payments.dim_earning_sources` on `sk_earning_source` for source status.
