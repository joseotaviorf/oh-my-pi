# Agents — Identity & Accreditation

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** Canonical agent identity, capabilities, the prospect/accreditation funnel, and the daily/monthly snapshots that answer "what state was this agent in on date X".
- **Asset status / lifecycle:** prospect → CRECI validation → contract signature → accredited (`agent.status = 'ACTIVE'`) → activated (first commercial event) → churned/inactive.
- **Typical actions / events:** sign-up, qualification steps, contract signature, CRECI validation, EN association, activation.
- **Common metrics:** active agents (monthly), new-agent activation rate, days-in-status.
- **Source systems:** EBDB (agent, prospect, qualification, contract), Amplitude (sign-up funnel). Consolidated 2026-06-19 (ADR: Instant Accreditation).
- **Related entities:** for the identity-migration warning (legacy vs new ID systems) and business-function definitions, see [`agents.md`](agents.md). For business profile classification, see [`agents_profile.md`](agents_profile.md).

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Prospect** | A person who intends to become an agent, pre-accreditation | `datalake_agent_accreditation.prospect_step_validation` / `prospect_agent`. |
| **Instant Accreditation** | 2026-06-19 ADR consolidating EBDB + Hub Services + Amplitude into one `agent` table | Replaced several legacy accreditation sources. |
| **Ativação / activation** | ⚠ No single definition | `is_activated` in `agent_new_agent_activation_metrics` (first commercial event ≤60 days of registration), or first visit/listing/TQC/deal. Always confirm. |
| **Agente ativo / active agent** | ⚠ Ambiguous | account-available (`is_agent_active` in `dim_agent`), has-visits, or app-active (Amplitude). Always confirm. |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Canonical `id_agent` identity, CRECI, capability flags | `datalake_agent_accreditation.agent` |
| Point-in-time / daily capability and status history | `dw_agent.fact_agent_daily` |
| Fine-grained capability status (per type, business context) | `datalake_ebdb_clean.capability` |
| CRECI validation / contract / sign-up ops queue | `datalake_agent_accreditation.prospect_step_validation` |
| Monthly status snapshot (CIQ + Demand) | `datalake_agent_reports.agent_status_by_month` |
| New-agent activation funnel (monthly cohort) | `datalake_agent_reports.agent_new_agent_activation_metrics` |

**Critical rules:**
- **DW first for daily state:** use `dw_agent.fact_agent_daily` for per-day capability/status questions; use enrich `agent` only for canonical identity or columns not projected to DW.
- There is **no longer** a published `agent_capability` table — its logic is folded into `agent`. For per-type detail, query the raw source `datalake_ebdb_clean.capability`; for `business_context` (RENT/SALE), join `demand_visit_management_capability_settings` on `id_capability` — that column does not exist on `capability` itself.
- `fact_agent_daily` event-log intervals are keyed on `ts_occurred` (when the event happened), not `ts_created` (row insert time).

---

## `datalake_agent_accreditation.agent`

Grain: **one row per `id_agent`** (canonical identity). `id_agent` is the cross-system join anchor for PFA, 3P, and capability tables. `id_agent` ≠ `id_user` (`id_user` is the platform user key for report/hub tables). **Pipeline:** `enrich_agent` DAG, full reload for most tables.

| Topic | Fields |
|-------|--------|
| Identity | `id_agent`, `id_agent_data`, `id_partner`, `id_user`, `id_negotiation_executive_user` |
| UUIDs | `uuid_company`, `uuid_agent`, `uuid_person` |
| CRECI | `creci`, `creci_uf` |
| Classification | `affiliation_type` (`1P`/`3P`), `status` (`ACTIVE`/`INACTIVE`), `company_product_name`, `profile` |
| Capability flags (fast filter) | `is_allow_supply_acquisition`, `is_allow_demand_acquisition`, `is_allow_visit`, `is_allow_demand_sale`, `is_allow_demand_rent`, `is_passive_lead_receiver` |
| Partnership | `is_1p_partnership`, `is_3p_partnership`, `is_reactivated` |
| Lifecycle timing | `days_in_current_status`, `ts_created`, `ts_last_status_changed`, `ts_updated` |

**Capabilities (per type):** grain of the raw source `datalake_ebdb_clean.capability` is one row per `(id_agent, type)` — columns `id`, `id_agent`, `type`, `status`, `ts_created`, `ts_updated`; there is **no `business_context` column on `capability` itself**. `business_context` (and `is_passive_lead_receiver`) live on the separate `datalake_ebdb_clean.demand_visit_management_capability_settings` table, joined via `capability.id = settings.id_capability` — only rows where `type = 'DEMAND_VISIT_MANAGEMENT'` have a matching settings row (RENT and/or SALE); other capability types have no `business_context` at all. Types on `capability`: `DEMAND_ACQUISITION`, `DEMAND_VISIT_MANAGEMENT`, `NEGOTIATION`, `SUPPLY_ACQUISITION`, `SUPPLY_CONVERSION_CONSULTANCY` — each `ENABLED`/`DISABLED`.

**`prospect_step_validation`** — one row per actionable (prospect, step) state, full reload. Unions four workflows: CRECI validation queue (`step_name = 'CRECI_VALIDATION'`), contract blocked (`CONTRACT_SIGNATURE`), sign-up blocked (`SIGNUP_PROFILE_CONFLICT`), EN association (`EN_ASSOCIATION`). Columns: `id_prospect_agent`, `id_user`, `id_negotiation_executive_user`, `uuid_person`, `business_context_applied`, `agent_status`, `step_name`, `step_status`, `status_reason`, `ts_created`.

## `dw_agent.fact_agent_daily`

Grain: **one row per agent per `dt_ref` (daily)**, partitioned `year/month/day`. Activation and capability flags are reconstructed from the agent event-log history (point-in-time accurate per day). This is the reliable, current source for per-day agent state.

| Topic | Fields |
|-------|--------|
| Keys (NEW system) | `sk_agent_daily` (grain PK), `sk_agent`, `sk_user`, `sk_partner` |
| Key (LEGACY bridge) | `sk_agent_data` — legacy `dadosAgent` id; **not** equal to `sk_agent` |
| UUIDs | `uuid_company`, `uuid_agent`, `uuid_person` |
| CRECI / classification | `creci`, `creci_uf`, `affiliation_type` (`1P`/`3P`), `profile` |
| State flags (point-in-time) | `is_agent_active`, `is_passive_lead_receiver`, `is_1p_partnership`, `is_3p_partnership` |
| Capability flags (business function) | `is_allow_supply_acquisition`, `is_allow_supply_conversion`, `is_allow_demand_visit`, `is_allow_demand_acquisition`, `is_allow_negotiation`, `is_allow_demand_sale`, `is_allow_demand_rent` |
| Timing | `dt_ref`, `days_in_current_status`, `ts_last_status_changed`, `ts_created` |

> Siblings in `dw_agent`: `dim_agent`, `dim_prospect_agent`, and `fact_visit_agent_performance` (⚠ **STALE since 2025-09-21** — historical only, no confirmed replacement as of 2026-06).

## `datalake_agent_reports` (monthly snapshots)

**`agent_status_by_month`** — one row per `(id_user, reference_month)`. Two independent statuses: `ciq_status` and `agent_status` (Demand, CORRETOR_5A from audit).

**`agent_new_agent_activation_metrics`** — one row per `(id_user, reference_month)` for the new-agent cohort (registered ≤60 days before month-end). Key columns: `is_activated`, `is_ciq_active_in_month`, `is_tqc_active_in_month`, `is_ppa_active_in_month`, `agent_type_segment` (modern replacement for legacy subtype jargon), `agent_business_context`.

## Dos and Don'ts

**Do:**

- Use `datalake_agent_accreditation.agent` for canonical `id_agent` identity; for **daily state** prefer `dw_agent.fact_agent_daily`.
- Translate legacy jargon ("Demand Agent", "CIQ-Only", "Independent Agent") to `agent_type_segment` / capability filters, not literal column values.
- Filter monthly report tables by `reference_month` (always first day of month).

**Don't:**

- Use `dw_agent.fact_visit_agent_performance` or any `datalake_visit_agent_performance.*` for current data — pipeline stopped **2025-09-21**; historical only.
- Mix `sk_agent`/`id_agent` (new) with `sk_agent_data`/`id_agent_data` (legacy) — see the identity-migration warning in [`agents.md`](agents.md).
- Expect a published `datalake_agent_accreditation.agent_capability` table — it was folded into `agent`; query raw `datalake_ebdb_clean.capability` for per-type detail.

---

## Golden Queries

### Query 1 — New agents activated this month

Activation cohort for the current month, using the modern `agent_type_segment` in place of legacy subtype jargon ("CIQ-Only", "Independent Agent").

```sql
SELECT
    a.agent_type_segment,
    a.agent_business_context,
    COUNT(DISTINCT a.id_user)                                   AS agents_in_cohort,
    SUM(CASE WHEN a.is_activated THEN 1 ELSE 0 END)             AS agents_activated
FROM datalake_agent_reports.agent_new_agent_activation_metrics AS a
WHERE a.reference_month = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY 1, 2
ORDER BY agents_activated DESC;
```

> `reference_month` is always the first day of the month. Join `datalake_agent_accreditation.agent` on `id_user` for CRECI or capability detail on the same cohort.
