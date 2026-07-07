# Agents

## Overview

- **Objective:** QuintoAndar field agents and their full operating lifecycle — accreditation, identity & capabilities, hub allocation, performance tiers, brokerage/revenue earnings, and Preferred Fixed/Property Agent assignment.
- **Asset status / lifecycle:** prospect (intends to create account) → accreditation (CRECI validation, contract signature) → first commercial event (first listing / TQC referral / PPA) → activated → tiered → paid (revenue share) → churned/inactive.
- **Typical actions / events:** sign-up, qualification steps, contract signature, region/hub allocation, visit and listing operations, brokerage/CIQ commissioning, tier assignment.
- **Common metrics:** active agents (monthly), CIQ-active agents, agents per hub, brokerage/revenue earned per agent, active PFA relations, new-agent activation rate.
- **Source systems:** EBDB (agent, prospect, qualification, contract), Hub Services (membership, NE hierarchy), Amplitude (sign-up funnel), BigAgent (earnings/tiers/incentives), Nazaré (payments), Airtable/GSheets (ops manual data).
- **Related entities:** for visit metrics see [`visits.md`](visits.md); for AI chatbots (Wall-E, Matthew, Sauron, Dominic/Matias) see [`chatbot_sessions.md`](chatbot_sessions.md) and [`matthew.md`](matthew.md) — those are **not** field agents.

> ⚠ **Two orthogonal axes — always pin down both before querying.** (1) **Operation type** = `profile` (what work the agent physically does); (2) **Business function** = which part of the deal the agent owns (what they earn for). Most tables mix everything unless filtered. Affiliation (`1P`/`3P`) is a third, independent axis.

### Operation type (`profile`)

`Visita` (property visits — most common; usually what "agente" means), `Vistoria` (inspections), `VistoriaQuarteirizada` (outsourced visits/inspections), `SessaoFotos` (photographers), `CheckUpLar` (repairs). Default scope for CIQ/activation/brokerage questions is `Visita`, but confirm.

### Business function (the three that matter most)

These are the functions business teams mean by "demand agent", "TQC", and "CIQ". One agent can hold several at once; they are NOT mutually exclusive and are separate from `profile`.

| Function | Also called | What they own | Capability (`capability.type`) | Earns (in `agent_revenue_share`) |
|---|---|---|---|---|
| **Demand / conversion** | demand agent, visit agent | Conduct the visit **and convert** the deal | `DEMAND_VISIT_MANAGEMENT` (RENT/SALE) | `revenue_role = DEMAND`, `brokerage_percentage`; BigAgent `DEMAND_CONVERSION_*` |
| **Demand acquisition** | **TQC** (Trás Quem Compra) | Bring / qualify the buyer lead | `DEMAND_ACQUISITION` | `tqc_percentage`, `has_tqc_revenue_share = true` (bonus on the `DEMAND` row); BigAgent `DEMAND_ACQUISITION_*` |
| **Supply acquisition** | **CIQ** | Register / bring the property (supply) | `SUPPLY_ACQUISITION`, `SUPPLY_CONVERSION_CONSULTANCY` | `revenue_role = SUPPLY`, `ciq_percentage`; BigAgent `SUPPLY_ACQUISITION_*` |

> "CIQ" is overloaded — it is both the affiliation **program** (Corretor Integrado QuintoAndar, `1P`) and this **supply-acquisition function**. Confirm which the user means. Likewise "demand agent" usually means the conversion function, but a TQC-only agent also acquires demand without converting.

### ⚠⚠ Identity migration (legacy ↔ Agent Domain) — READ BEFORE JOINING

QuintoAndar is **mid-migration** from legacy agent services to the new Agent Domain, so **two ID systems coexist in the lake** and are freely mixed across tables. **They are NOT interchangeable.**

| Key | System | Origin | Use |
|---|---|---|---|
| `sk_agent_data` / `id_agent_data` | **LEGACY** | `dadosAgent` service | Joins to legacy agent tables. |
| `sk_agent` / `id_agent` | **NEW (Agent Domain)** | accreditation (`datalake_agent_accreditation.agent`) | Joins to new accreditation/enrich tables. |

> **`sk_agent` (new) ≠ `sk_agent_data` (legacy)** — different agents, different hash sources. They map 1:1 only through a bridge row (e.g. `fact_agent_daily` / `dim_agent` carry both side by side).
>
> **Name collision:** the column `sk_agent` exists in BOTH `dw_public.dim_agent` (legacy star-schema key) and the new `dw_agent.*` tables (Agent-Domain key) — **same name, different value space. Never join `dw_public.dim_agent.sk_agent` directly to `dw_agent.fact_agent_daily.sk_agent`.**
>
> Some tables are still legacy, some are already on the new system — **check which ID system a table uses before joining it to another.** When in doubt, bridge through a table that carries both `sk_agent` and `sk_agent_data` (e.g. `dw_agent.fact_agent_daily`).

DW / enrich schemas described here: **`datalake_agent_accreditation`**, **`datalake_agent_reports`**, **`datalake_hub_services`**, **`datalake_agent_payments`**, **`datalake_big_agent`**, **`datalake_ebdb_agents`**, **`datalake_tiers`**, **`datalake_ciq`**, **`dw_ciq`**, **`datalake_brokerage`**, and the (stale) **`dw_agent`** star schema.

---

## Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Agente / corretor** | Field agent | Multi-type — see Overview warning. |
| **Agente de visita / Visita** | Visit agent | `profile = 'Visita'`; default scope for most business questions. |
| **Vistoria / Vistoriador** | Inspection agent | `profile = 'Vistoria'`. |
| **SessãoFotos / fotógrafo** | Photographer agent | `profile = 'SessaoFotos'`. |
| **Agente CIQ (program)** | Affiliation — enrolled in the CIQ (Corretor Integrado QuintoAndar) program | `ciq_status` in `agent_status_by_month`; affiliation `1P`. Overloaded — see "CIQ (function)" row and the business-function table in Overview. |
| **Agente 3P / parceiro** | Third-party / partner-firm agent | `affiliation_type = '3P'` in `agent`; `is_3p_agent = true` in `dw_public.dim_agent`. |
| **Demand Agent / agente de demanda** | Conversion function — conducts visits and converts | `profile = 'Visita'` + capability `DEMAND_VISIT_MANAGEMENT ENABLED`; `revenue_role = DEMAND`. See business-function table in Overview. |
| **CIQ-Only agent** | Agent whose only active business is CIQ | `DEMAND_ACQUISITION DISABLED` AND `SUPPLY_CONVERSION_CONSULTANCY ENABLED`; or `is_ciq_only` in `agent_new_agent_activation_metrics`. |
| **Independent Agent / agente independente** | Agent with both acquisition and demand | `DEMAND_ACQUISITION ENABLED` AND `affiliation_type = '1P'` AND `is_passive_lead_receiver = false`; or `is_independent_agent` in activation metrics. |
| **Ativação / activation** | ⚠ No single definition | `is_activated` in `agent_new_agent_activation_metrics` (first commercial event ≤60 days of registration), or first visit/listing/TQC/deal. Always confirm. |
| **Agente ativo / active agent** | ⚠ Ambiguous | account-available (`is_agent_active` in `dim_agent`), has-visits (`fact_visit_schedules`), operationally-eligible (combine flags), or app-active (Amplitude). Always confirm. |
| **TQC (Trás Quem Compra)** | **Demand-acquisition function** — agent who brings/qualifies the buyer lead | Capability `DEMAND_ACQUISITION`; `id_user_agent_lead_referral` in `datalake_sale_offer_flows.offer_specialists`; `tqc_percentage` / `has_tqc_revenue_share` in `agent_revenue_share`. |
| **CIQ (function)** | **Supply-acquisition function** — agent who registers/brings the property | Capability `SUPPLY_ACQUISITION` / `SUPPLY_CONVERSION_CONSULTANCY`; `revenue_role = SUPPLY`, `ciq_percentage`. Distinct from the CIQ *program* (next row). |
| **PPA (Preferred Property Agent)** | Agent fixed to a listing (agent brought the supply) | `preferred_property_agent_relation_history`. |
| **PFA (Preferred Fixed Agent)** | Agent fixed to a lead (usually first-visit; see `origin`) | Same table; reason in `origin`. |
| **BIG_AGENT** | Newer brokerage/earnings model | `revenue_source = 'BIG_AGENT'`. |
| **Nazaré** | Legacy per-offer brokerage / payment system | `revenue_source = 'NAZARE'`. |
| **VBBA / VCBA** | Visits Booked / Completed Booked **By Agent** | `sk_author_creator = sk_user_agent` in `dw_visit.fact_visit_schedules` (+ `is_completed = 1` for VCBA). |
| **Hub / Business Unit** | Regional agent grouping | `hub_name`, `id_business_unit` in `member_hub_allocation`. |
| **EN / Negotiation Executive** | QA staff responsible for an agent's hub | NE = parent member (`id_parent_user`, `user_parent_*`) in `member_hub_allocation`; `id_negotiation_executive_user` in `agent`. |
| **Capability / capacidade** | Fine-grained permission | `capability.type + status` (raw source `datalake_ebdb_clean.capability`); for booleans use `agent.is_allow_*`. Prefer over legacy subtype jargon. |
| **Primeira listagem / first listing** | ⚠ "any first listing" vs "valid first listing" (dedup-gated) | Valid first listing gated by `datalake_listing_deduplication.valid_first_listing`; used for CIQ payment eligibility and activation. Default to valid for CIQ/activation, confirm. |
| **Valid First Listing** | A first listing that survives property **deduplication** — a re-listed / duplicated property does NOT count again | Custom QuintoAndar concept; lives in `datalake_listing_deduplication`. ⚠ Metric definition still evolving — see schema section. |
| **Compra de Carteira / CIQ listing purchase** | CIQ_FULL rent **listing-purchase** fact — payment eligibility, pricing segment, portfolio loss | Analyst table: `dw_ciq.fact_ciq_listing_purchase`; enrich source: `datalake_ciq.ciq_listing_purchase`. Grain: house × listing version × partner × CIQ user. |
| **Perda de carteira / portfolio loss** | Relist still on market >90 days without a signed rent contract | `is_portfolio_loss = true` on `dw_ciq.fact_ciq_listing_purchase` only (not on enrich). |
| **Re-Listing (rent version category)** | New rent listing cycle after a prior rental ended | `listing_category = 'Re-Listing'` on purchase rows (from `datalake_ebdb_listing.house_listing`). See [`house_and_listing.md`](house_and_listing.md). |

---

## Where to query what

| You need… | Schema / table |
|-----------|----------------|
| Canonical agent identity, status, capability flags | `datalake_agent_accreditation.agent` |
| Fine-grained capabilities (per type, business context) | `datalake_ebdb_clean.capability` (+ `demand_visit_management_capability_settings` for business_context/passive-lead). Boolean rollups on `datalake_agent_accreditation.agent.is_allow_*`. |
| Prospect onboarding ops queue (CRECI / contract / signup / EN) | `datalake_agent_accreditation.prospect_step_validation` |
| Sign-up funnel blocking events (Amplitude) | `datalake_agent_accreditation.signup_profile_conflict` |
| Agent geo-region assignment history | `datalake_agent_accreditation.agent_major_region_code` |
| Agent status + CIQ (monthly snapshot) | `datalake_agent_reports.agent_status_by_month` |
| New-agent activation funnel (monthly cohort) | `datalake_agent_reports.agent_new_agent_activation_metrics` |
| Per-agent support tickets (monthly) | `datalake_agent_reports.agent_support_tickets_by_month` |
| Agent hub assignment, NE, region (daily) | `datalake_hub_services.member_hub_allocation` |
| For-Sale agent revenue share, BigAgent vs Nazaré | `datalake_agent_payments.agent_revenue_share` |
| For-Rent contract broker share (revision history) | `datalake_big_agent.brokerage_share_history` |
| Per-offer brokerage fee (Nazaré legacy) | `datalake_brokerage.partner_brokerage` |
| CIQ rent commission / listing-purchase (enrich) | `datalake_ciq.ciq_listing_purchase` |
| CIQ Compra de Carteira — analyst fact (pricing + **portfolio loss**) | `dw_ciq.fact_ciq_listing_purchase` |
| Listing-purchase acquisition tiers / duplicity pricing | `datalake_ciq.listing_purchase_pricing` (join on `id_listing_purchase` / `sk_listing_purchase`) |
| Valid first listing (dedup-gated) for CIQ / activation | `datalake_listing_deduplication.valid_first_listing` |
| **CIQ** first-listing validation for tiers (15-day rule, invalidation) | `datalake_tiers.ciq_first_listing` |
| Property dedup analysis / duplicate detection | `datalake_listing_deduplication.listing_deduplication` |
| Performance metrics for tiering (EAV) | `datalake_tiers.agent_performance` |
| PFA/PPA relation per listing | `datalake_ebdb_agents.preferred_property_agent_relation_history` |
| PFA program eligibility | `datalake_ebdb_agents.preferred_property_agent_program_eligibility` |
| 3P agent type + contract history | `datalake_ebdb_agents.agent_3p_history` |
| Daily per-agent state snapshot (status, capabilities, profile) — **reliable** | `dw_agent.fact_agent_daily` (NEW ID system; carries legacy `sk_agent_data`) |
| Legacy `sk_agent ↔ id_user` bridge (DW ↔ operational) | `dw_public.dim_agent` (⚠ LEGACY `sk_agent` — see identity-migration warning) |
| Visit funnel / completion metrics | `dw_visit.fact_visits` (see [`visits.md`](visits.md)) |
| ⚠ Historical visit-agent performance (STALE) | `dw_agent.fact_visit_agent_performance`, `datalake_visit_agent_performance.*` (pipeline stopped 2025-09-21) |

---

## `datalake_agent_accreditation`

**Purpose:** unified agent identity, capabilities, and accreditation/prospect funnel. Hub node for the domain.

**Pipeline:** `enrich_agent` DAG (full reload for most tables; `signup_profile_conflict` is incremental, partitioned `year/month/day`). Published 2026-06-19 (ADR: Instant Accreditation), consolidating EBDB + Hub Services + Amplitude.

### `agent`

Grain: **one row per `id_agent`** (canonical identity). `id_agent` is the cross-system join anchor for PFA, 3P, and capability tables. `id_agent` ≠ `id_user` (`id_user` is the platform user key for report/hub tables).

| Topic | Fields |
|-------|--------|
| Identity | `id_agent`, `id_agent_data`, `id_partner`, `id_user`, `id_negotiation_executive_user` |
| UUIDs | `uuid_company`, `uuid_agent`, `uuid_person` |
| CRECI | `creci`, `creci_uf` |
| Classification | `affiliation_type` (`1P`/`3P`), `status` (`ACTIVE`/`INACTIVE`), `company_product_name`, `profile` |
| Capability flags (fast filter) | `is_allow_supply_acquisition`, `is_allow_demand_acquisition`, `is_allow_visit`, `is_allow_demand_sale`, `is_allow_demand_rent`, `is_passive_lead_receiver` |
| Partnership | `is_1p_partnership`, `is_3p_partnership`, `is_reactivated` |
| Lifecycle timing | `days_in_current_status`, `ts_created`, `ts_last_status_changed`, `ts_updated` |

> Use `is_allow_*` for quick boolean capability checks on one table. For status-per-type / `business_context` detail there is no longer a published `agent_capability` table — query the raw source `datalake_ebdb_clean.capability` (join `demand_visit_management_capability_settings` for business_context and passive-lead).

### Capabilities (per type / business_context)

> ⚠ There is **no longer** a published `datalake_agent_accreditation.agent_capability` table — it was folded into `agent` (its logic now lives inline in the `agent` query). For per-type / business_context detail query the raw source `datalake_ebdb_clean.capability` (join `datalake_ebdb_clean.demand_visit_management_capability_settings` on `capability.id = ...id_capability` for `business_context` + `is_passive_lead_receiver`). For boolean rollups use `agent.is_allow_*`.

Grain of the raw source: **one row per `(id_agent, type, business_context)`**. `DEMAND_VISIT_MANAGEMENT` has two rows per agent (RENT + SALE); other types have null `business_context`.

| type | status values | business_context |
|---|---|---|
| `DEMAND_ACQUISITION` | ENABLED / DISABLED | null |
| `DEMAND_VISIT_MANAGEMENT` | ENABLED / DISABLED | RENT or SALE |
| `NEGOTIATION` | ENABLED | null |
| `SUPPLY_ACQUISITION` | ENABLED / DISABLED | null |
| `SUPPLY_CONVERSION_CONSULTANCY` | ENABLED / DISABLED | null |

### `prospect_step_validation`

Grain: **one row per actionable (prospect, step) state**. Full reload — no row-level history. Single ops-facing view unioning four workflows:

| Use case | `step_name` | `status_reason` |
|---|---|---|
| CRECI validation queue | `CRECI_VALIDATION` | `PENDING_VALIDATION` |
| Contract blocked | `CONTRACT_SIGNATURE` | `CONTRACT_<CANCELLED/DECLINED/AUTO_RESPONDED>` |
| Sign-up blocked | `SIGNUP_PROFILE_CONFLICT` | `ACTIVE_AGENT_EXISTS` / `INACTIVE_AGENT_EXISTS` / `PROSPECT_AGENT_PENDING_APPROVAL` |
| EN association (active agent, no NE) | `EN_ASSOCIATION` | `NOT_ATTRIBUTED` |

Columns: `id_prospect_agent`, `id_user`, `id_negotiation_executive_user`, `uuid_person`, `business_context_applied`, `agent_status`, `step_name`, `step_status`, `status_reason`, `ts_created`.

> Sibling tables in this DAG: `prospect_agent`, `qualification_step`, `contract_process`, `signup_profile_conflict` (Amplitude sign-up conflicts, incremental).

---

## `datalake_agent_reports`

**Purpose:** monthly agent lifecycle and activation snapshots for OKRs/KPIs. **Pipeline:** `enrich_agent_reports`, partitioned by `reference_month` (DATE, always first of month).

### `agent_status_by_month`

Grain: **one row per `(id_user, reference_month)`**. Carries two independent statuses: CIQ (`ciq_status`) and Demand (`agent_status`, CORRETOR_5A from audit).

| Topic | Fields |
|-------|--------|
| Keys | `id_user`, `id_agent`, `reference_month` |
| CIQ status | `ciq_status`, `ciq_days_in_status`, `ciq_status_start`, `ciq_status_end` |
| Demand status | `agent_status`, `agent_days_in_status`, `agent_status_start`, `agent_status_end`, `is_passive_lead_receiver` |

### `agent_new_agent_activation_metrics`

Grain: **one row per `(id_user, reference_month)`** for the new-agent cohort (registered ≤60 days before month-end). Cohort evaluated per month — supports backfills.

| Topic | Fields |
|-------|--------|
| Cohort timing | `dt_independent_agent_registered`, `ts_agent_created`, `ts_ciq_created`, `days_since_*` |
| Activation events | `ts_first_activation_tqc_referral`, `total_tqc_count`, `ts_valid_activation_first_listing`, `total_listings_count`, `total_ppa_count`, `ts_first_ppa_activation` |
| Activation flags | `is_activated`, `is_ciq_active_in_month`, `is_tqc_active_in_month`, `is_ppa_active_in_month`, `is_ciq_only`, `is_independent_agent` |
| Segmentation | `agent_type_segment`, `agent_business_context`, `name_city` |

> `agent_type_segment` is the modern replacement for legacy subtype jargon ("CIQ-Only", "Independent Agent").

---

## `datalake_hub_services`

**Purpose:** daily agent↔hub allocation and NE hierarchy. **Pipeline:** `enrich_hub_services`, partitioned `year/month/day`.

### `member_hub_allocation`

Grain: **one row per `(id_user, dt_reference)`**. Replaces the deprecated `agent_hub_alocation` (note the old typo: one `l`) and `agent_hub_relation`.

| Topic | Fields |
|-------|--------|
| Member identity | `id_member_relationship`, `id_member_profile`, `id_user`, `id_main_user`, `id_agent`, `uuid_person`, `uuid_company` |
| Hub / region | `id_business_unit`, `hub_name`, `id_region`, `city_group`, `city_name`, `short_region_name` |
| Classification | `profile`, `agent_type`, `business_context`, `lead_types`, `is_active` |
| Parent member (NE / manager) | `id_parent_user`, `id_parent_main_user`, `id_parent_agent`, `user_parent_name`, `user_parent_email`, … |
| Partition | `dt_reference`, `year`, `month`, `day` |

> Filter `is_active = true` for current allocation. NE moved from dedicated `negotiation_executive_*` columns (old table) to **parent member** columns. `member_hub_allocation` has a broader "member" scope (~1,100 more users/day) than the old visit-agent-only table.

---

## `datalake_agent_payments` / `datalake_big_agent` (earnings & brokerage)

Two distinct earning concepts — **do not conflate**:

### `datalake_agent_payments.agent_revenue_share` — For-Sale revenue share

**Purpose (ADR 2026-06-19):** reconciliation table surfacing BigAgent-calculated vs Nazaré-paid values side-by-side for **Sale** deals. **Pipeline:** `enrich_brokerage`, incremental, partitioned `year/month/day` on `dt_updated`.

Grain: **one row per `(id_user, id_house, id_offer, business_context, revenue_source, revenue_role)`** — the same agent appears twice per offer (one row per source) for direct comparison.

| Topic | Fields |
|-------|--------|
| Keys | `id_user`, `id_house`, `id_offer`, `uuid_person` |
| Discriminators | `business_context`, `revenue_source` (`BIG_AGENT` / `NAZARE`), `revenue_role` — maps to business function: `DEMAND` = conversion agent (base `brokerage_percentage` ± `tqc_percentage` demand-acquisition bonus) / `SUPPLY` = CIQ supply-acquisition agent (`ciq_percentage`) |
| Amounts | `revenue_amount` (gross BRL), `revenue_percentage` |
| Share breakdown | `brokerage_percentage` (base demand fee), `tqc_percentage` (TQC bonus), `ciq_percentage` (CIQ supply), `has_tqc_revenue_share` |
| Timing | `dt_created`, `dt_updated` |

- `BIG_AGENT` ← `datalake_big_agent.earnings` (status `CALCULATED`; `DEMAND_CONVERSION_FS`, `DEMAND_ACQUISITION_FS`, `SUPPLY_ACQUISITION_FS`).
- `NAZARE` ← `datalake_nazare_clean.revenue_share_by_participant` (non-invalidated).

> **Double-count trap:** always filter `revenue_source` before any `SUM`/percentage — the table UNIONs both systems for the same offer. `id_offer`/`id_house` may be NULL when the BigAgent→offer join chain is missing.

### `datalake_big_agent.brokerage_share_history` — For-Rent contract broker share

**Purpose (ADR 2026-06-19):** version-controlled source of truth for `agent_brokerage_share` (rent contracts), after migration off the deprecated EBDB `contract.agent_brokerage_share` column. **Pipeline:** `enrich_big_agent_incentives`, incremental MERGE on `(id_revision, id_contract)`, partitioned by `dt_load`.

Grain: **one row per `(id_revision, id_contract)`**. Columns: `id_revision`, `id_contract`, `agent_brokerage_share`, `ts_revision`, `dt_load`.

- Primary source: `datalake_big_agent_clean.new_earnings_aud` (`DEMAND_CONVERSION_FR`).
- Fallback (legacy contracts with no BigAgent earning source): `datalake_ebdb_clean.contract_aud`.

> **Revision granularity:** apply `ROW_NUMBER()`/`LAST_VALUE` to get the current share per contract — this is NOT one row per contract. The EBDB `contract.agent_brokerage_share` column is removed; do not read it.

---

## `datalake_ebdb_agents` (PFA / PPA)

**Purpose:** Preferred Fixed/Property Agent assignment. **Pipeline:** `enrich_ebdb_agents`.

### `preferred_property_agent_relation_history`

Grain: **one row per PFA/PPA relation revision**. Join on `id_house` / `id_related_agent`.

| Topic | Fields |
|-------|--------|
| Keys | `id_house`, `id_related_agent`, `business_context` |
| Reason | `origin` (why the relation was created) |
| Validity | `ts_relation_started`, `ts_relation_ended` |

> Filter `ts_relation_ended IS NULL` for active relations. `ts_relation_started` is **synthetic** (backfilled) for rows before **2025-06-03** — not a true creation timestamp. Eligibility lives in `preferred_property_agent_program_eligibility` (filter `ts_status_ended IS NULL`).

---

## `datalake_tiers` (performance for tiering)

**Purpose:** per-agent performance metrics feeding tier calculation; consumed downstream by the `agent_tier_metrics` Wonka job (`wonka.agent_tier_metrics` Delta + `{env}_wonka.agent_date_metric` Kafka). **Pipeline:** `enrich_tiers`, dataset-triggered daily (~11:00 UTC).

### `agent_performance` — EAV

Grain: **one row per `(id_user, id_agent, id_metric_period, metric_name)`**. All accredited agents × active periods are cross-joined; missing combos filled `metric_value = 0, is_valid = true`. Compound ratios (`BP2CCV`, `TP2CS`, `OS2CCV_BY`) capped at 1.0. Pivot on `metric_name` for wide views; confirm enum live via `SELECT DISTINCT metric_name … LIMIT 50`.

### `ciq_first_listing` — CIQ first-listing validation (for tiers)

Grain: **one row per `id_house`** — houses recommended by CIQ consultants (SALE and RENT), with the CIQ-specific first-listing **validity** verdict feeding tier calculation. Applies duplicate/hybrid rules and the **15-day publication-or-contract compliance rule**, with explicit invalidation reasons.

| Topic | Fields |
|-------|--------|
| Keys | `id_house`, `id_user`, `id_agent`, `id_partner`, `uuid_person`, `id_similar_previous_house`, `id_similar_first_house` |
| Validity verdict | `is_first_listing_valid`, `invalidation_reasons`, `is_valid_duplicated_previous_house`, `is_valid_duplicated_first_house`, `is_valid_hybrid`, `is_invalid_by_indica_ai`, `is_valid_compliance_general_rule` |
| Context | `business_context`, `consultant_type`, `house_listing_status`, `supply_source`, `supply_source_by_context`, `is_hybrid_house`, `hybrid_creation_order` |
| Compliance / timing | `is_signed_contract_within_60_days`, `dt_compliance_general_rule`, `dt_min_published_accumulated_days`, `ts_original_first_listing`, `ts_final_first_listing`, `ts_first_contract_signed`, `ts_last_depublication` |

> ⚠ **`ciq_first_listing` vs `valid_first_listing`:** both validate a dedup-gated first listing, but `datalake_tiers.ciq_first_listing` is the **CIQ-consultant / tiers** scope (use `is_first_listing_valid` + `invalidation_reasons`, 15-day rule), while `datalake_listing_deduplication.valid_first_listing` is the broader dedup/activation source. For CIQ tier and commission questions, use `ciq_first_listing`. Both definitions are still evolving — confirm the active rule.

---

## `datalake_listing_deduplication` (Valid First Listing)

**Purpose:** custom QuintoAndar concept — deduplicate properties so that a **re-listed or duplicated property is not counted as a new first listing**. Gates the **Valid First Listing** used for CIQ payment eligibility and agent activation. **Pipeline:** `enrich_listing_deduplication` DAG.

> ⚠ **Metric still evolving.** The exact "valid first listing" definition is being refined; treat the columns below as the current implementation, not a frozen contract. Confirm the active rule before using it in payment/OKR logic.

Why it matters: the same physical property can be listed multiple times (re-listing, hybrid rent+sale, multiple agents). Counting each listing as a "first listing" would inflate activation and over-pay CIQ commissions. This schema parses/normalizes addresses, detects duplicates, and emits one **validated** first-listing record per property.

### `valid_first_listing`

Grain: **one row per `id_house`** — the deduplicated, validated first-listing record (rent and sale side by side).

| Topic | Fields |
|-------|--------|
| Keys | `id_house`, `id_ciq_user_sale`, `id_ciq_user_rent`, `id_similar_previous_house`, `id_similar_first_house` |
| Validity / dedup | `is_hybrid_house`, `hybrid_creation_order`, `is_signed_cs_within_60_days`, `is_signed_ccv_within_60_days`, `is_indica_ai` |
| Listing status | `house_listing_status`, `last_house_listing_status_rent/sale`, `is_house_rented`, `is_house_sold`, `is_ongoing_rent_contract` |
| Timing windows | `ts_first_listing`, `ts_first_listing_rent/sale`, `days_between_fl_to_cs`, `days_between_fl_to_ccv`, `total_days_published_within_60_days_rent/sale` |
| Supply / consultant | `supply_source`, `supply_source_rent/sale`, `consultant_type_rent/sale` |

### `listing_deduplication`

Grain: **one row per `id_house`** — address-normalized dedup analysis over the full EBDB house universe. Identifies duplicates by comparing parsed short addresses.

| Topic | Fields |
|-------|--------|
| Keys | `id_house`, `id_address_parsed_short`, `id_similar_previous_house`, `id_similar_first_house` |
| Dedup verdict | `is_duplicated`, `is_first_listing_in_duplicates`, `first_listing_order` |
| Address | `address_full`, `address_parsed_short` |
| Registrant / supply | `id_user_listing_registrant_rent/sale`, `supply_source`, `supply_source_rent/sale` |

> Siblings: `first_listing` (CIQ-recommended houses with first-listing/publication timestamps) and `atlas_house_deduplication` (Atlas similar-property duplicity verdicts; `is_last_duplicity = true` for the current verdict).

---

## CIQ listing purchase (Compra de Carteira)

**Purpose:** CIQ_FULL **rent listing-purchase** — which houses qualify for the Compra de Carteira payment program, Robin Hood payment state, commercial **pricing segments** (transition rules), and **portfolio loss** (relist published >90 days without renting). **Pipelines:** `enrich_ciq` → `datalake_ciq.ciq_listing_purchase`; `dw_ciq_listing_purchase` → `dw_ciq.fact_ciq_listing_purchase` (joins enrich with `listing_purchase_pricing` for acquisition tiers).

**Grain (enrich & fact):** one row per **house listing version** in CIQ context (house × `sk_house_listing` × partner × CIQ user × consultant type), not one row per house.

| You need… | Where |
|-----------|--------|
| Full operational detail, all enrich columns | `datalake_ciq.ciq_listing_purchase` |
| Dashboards / OKRs / portfolio loss flag | **`dw_ciq.fact_ciq_listing_purchase`** |
| Acquisition bucket + duplicity pricing | `dw_ciq.fact_ciq_listing_purchase` (`acquisition_type`, `purchase_value` from pricing join) |

### Relist vs republication vs portfolio loss

| Signal | Column | Meaning |
|--------|--------|---------|
| Later listing version exists | `has_republication` | On **this** version: a subsequent `sk_house_listing` exists (ordered by version start). Does not by itself mean portfolio loss. |
| This version is a relist cycle | `listing_category = 'Re-Listing'` | Rent listing versioning label from `house_listing` — publication after a prior rental cycle. |
| Start of publish for this version | `ts_publicated` | Anchor for “new publish event” on this listing version (aligns with rent versioning; see [`house_and_listing.md`](house_and_listing.md)). |
| Days since that publish | `total_days_since_publish` | Calendar days from `ts_publicated` to load date for **every** listing version on enrich and fact (no Re-Listing filter in enrich). |
| **Portfolio loss (business rule)** | **`is_portfolio_loss`** | **DW only:** `Re-Listing` AND `listing_status` in (`PUBLISHED`, `publicado`) AND no signed rent contract on this version (`ts_contract_signed` null) AND `total_days_since_publish > 90`. |

> Do **not** use `total_days_since_house_inactived` for portfolio loss — it counts **inactive** listing-version days, not time on market since publish.

> **`sk_partner`** on the fact is the CIQ partner key (`id_partner` in enrich) for joins to partner-scoped tables.

### Other filters analysts often need

- **CIQ_FULL scope:** enrich rows are built from `house_consultant_history` with `consultant_type = 'CIQ_FULL'` and RENT business context in pricing rules.
- **Payment:** `payment_status`, `is_paid`, `amount_paid`; fact merge updates matched rows only while `is_paid` is not true.
- **Pricing segment:** `pricing_type` / `pricing_type_reason` (transition cohorts such as ongoing-listings, ongoing-rentals, new-listings).
- **Duplicity:** `has_similiar_house_by_address_parsed`, `has_similiar_house_by_atlas`; pricing join adds similar-house acquisition logic.

---

## `dw_agent` (Agent-Domain star schema)

**Purpose:** DW projection of the new Agent Domain accreditation layer. **Pipeline:** `dw_agent_accreditation` DAG. Built on the **new** ID system (`sk_agent`), but carries `sk_agent_data` for legacy bridging — see the identity-migration warning above.

> ⚠ Do not confuse `dw_agent` (new) with `dw_public.dim_agent` (legacy). Both have a column named `sk_agent`; the values are from different ID systems.

### `fact_agent_daily` — reliable daily agent snapshot

Grain: **one row per agent per `dt_ref` (daily)**, partitioned `year/month/day`. Each agent is expanded from creation through the load window using `aux_date`; activation and capability flags are **reconstructed from agent event-log history** (point-in-time accurate per day), and profile attributes are enriched from `agent_daily` when available for the same agent-day. This is the **reliable, current source for per-day agent state** — prefer it over the stale `fact_visit_agent_performance`.

> **Event timing:** the event-log intervals (`ts_started`/`ts_ended`) are keyed on **`ts_occurred`** — when the event actually happened — not `ts_created` (row insert time). For any as-of-date / status-history question, `ts_occurred` is the correct event clock.

| Topic | Fields |
|-------|--------|
| Keys (NEW system) | `sk_agent_daily` (grain PK), `sk_agent`, `sk_user`, `sk_partner` |
| Key (LEGACY bridge) | `sk_agent_data` — legacy `dadosAgent` id; **not** equal to `sk_agent` |
| UUIDs | `uuid_company`, `uuid_agent`, `uuid_person` |
| CRECI / classification | `creci`, `creci_uf`, `affiliation_type` (`1P`/`3P`), `profile` |
| State flags (point-in-time) | `is_agent_active`, `is_passive_lead_receiver`, `is_1p_partnership`, `is_3p_partnership` |
| Capability flags (business function) | `is_allow_supply_acquisition`, `is_allow_supply_conversion`, `is_allow_demand_visit`, `is_allow_demand_acquisition`, `is_allow_negotiation`, `is_allow_demand_sale`, `is_allow_demand_rent` |
| Timing | `dt_ref`, `days_in_current_status`, `ts_last_status_changed`, `ts_created` |

> The `is_allow_*` flags here are the per-day projection of the three business functions: `is_allow_demand_visit` (conversion), `is_allow_demand_acquisition` (TQC), `is_allow_supply_acquisition` / `is_allow_supply_conversion` (CIQ). Filter by `dt_ref` (or the `year/month/day` integer partitions) for a point-in-time view — no SCD window logic needed.

> Siblings in `dw_agent`: `dim_agent`, `dim_prospect_agent` (new-system projections of the enrich layer), and `fact_visit_agent_performance` (⚠ **STALE since 2025-09-21** — historical only).

---

## Relationships with other entities

- **Hub (`datalake_agent_accreditation.agent`) → reports:** `agent.id_user = agent_status_by_month.id_user` (1:N per month).
- **Hub → hub services:** `agent.id_user = member_hub_allocation.id_user` (1:N per day; filter `is_active = true`).
- **Hub → PFA:** `agent.id_agent = preferred_property_agent_relation_history.id_related_agent` (1:N per listing).
- **Hub → revenue:** `agent.id_user = agent_revenue_share.id_user` (filter `revenue_source` first).
- **Hub → Compra de Carteira:** `agent.id_partner = fact_ciq_listing_purchase.sk_partner` and/or `agent.id_user = fact_ciq_listing_purchase.sk_user` (grain is listing-version × partner, not one row per agent).
- **Identity bridge (legacy):** `dw_public.dim_agent.id_user = agent.id_user`; bridge legacy `sk_agent ↔ id_user` through `dw_public.dim_agent`. ⚠ This `sk_agent` is the **legacy** star-schema key — NOT the same as `dw_agent.*.sk_agent` (new). To cross legacy↔new, bridge through a table carrying both `sk_agent` and `sk_agent_data` (e.g. `dw_agent.fact_agent_daily`). See the identity-migration warning.
- **Visits:** agents link to `dw_visit.fact_visits` / `fact_visit_schedules` via `sk_agent`; see [`visits.md`](visits.md).
- **Support tickets:** `agent_support_tickets_by_month` → `dw_customer_support.fact_tickets`.

---

## Dos and don'ts

**Do:**

- Confirm **both axes** before scoping: **operation type** (`profile`: `Visita`/`Vistoria`/…) and **business function** (demand/conversion vs demand-acquisition/TQC vs supply-acquisition/CIQ). Most tables mix everything.
- Confirm what "active agent", "activation", and "first listing" mean — each maps to a different table/filter (see Synonyms).
- Translate legacy jargon ("Demand Agent", "CIQ-Only", "Independent Agent") to capability/`agent_type_segment` filters, not literal column values.
- Use `datalake_agent_accreditation.agent` as the canonical `id_agent` source; bridge `sk_agent ↔ id_user` via `dw_public.dim_agent`.
- Filter `revenue_source` in `agent_revenue_share` before any aggregation.
- Apply `ROW_NUMBER()`/`LAST_VALUE` on `brokerage_share_history` to get the current share per contract.
- Filter `ts_relation_ended IS NULL` (active PFA) and `ts_status_ended IS NULL` (current eligibility).
- Filter daily tables by integer `year = X AND month = X AND day = X`, not `dt_reference BETWEEN` (scans all partitions).
- For `offer_flow_events` / `offer_flow_performance`, add `WHERE ts_event > DATE '2010-01-01'` (epoch-overflow min dates show as `1899-12-29`).
- For **CIQ portfolio loss**, use **`dw_ciq.fact_ciq_listing_purchase.is_portfolio_loss`** — do not re-derive from `has_republication` alone (that flag is on the **prior** cycle when a later version exists).
- Join **listing relist semantics** to [`house_and_listing.md`](house_and_listing.md) when explaining `listing_category` vs sale hybrid tables.

**Don't:**

- **Mix the two ID systems.** `sk_agent`/`id_agent` (new Agent Domain) ≠ `sk_agent_data`/`id_agent_data` (legacy `dadosAgent`). The column `sk_agent` exists in both `dw_public.dim_agent` (legacy) and `dw_agent.*` (new) with different value spaces — never join them directly; bridge through a table carrying both keys (`dw_agent.fact_agent_daily`).
- Confuse **`agent_revenue_share`** (For-Sale revenue share, BigAgent vs Nazaré reconciliation) with **`brokerage_share_history`** (For-Rent contract broker share) — different scopes, grains, and DAGs.
- Use `datalake_hub_services.agent_hub_alocation` (deprecated, typo `alocation`) or `agent_hub_relation` (deprecated) — use `member_hub_allocation` with `is_active = true`.
- Read EBDB `contract.agent_brokerage_share` (removed) or `dw_public.dim_agent.rede_partner` (deprecated).
- Use `dw_agent.fact_visit_agent_performance` or any `datalake_visit_agent_performance.*` for current data — pipeline stopped **2025-09-21**; historical only, no confirmed replacement as of 2026-06.
- Reference `dw_brokers.dim_brokers` (trailing `s`) — `DELTA_LAKE_INVALID_SCHEMA`; use `dw_public.dim_agent`.
- Treat `datalake_big_agent.house_consultant_history.consultant_type` (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) as stable — active RFC pending.
- Assume AI agents (Wall-E, Matthew, Sauron, Dominic/Matias) belong here — see [`chatbot_sessions.md`](chatbot_sessions.md).
- Use **`total_days_since_house_inactived`** as “days available without rent” for Compra de Carteira — use **`total_days_since_publish`** / **`is_portfolio_loss`** on `dw_ciq.fact_ciq_listing_purchase`.
- Expect **`is_portfolio_loss`** on `datalake_ciq.ciq_listing_purchase` — it is materialized only on the **DW fact**.

---

## Golden query: Active agents per hub (latest day)

Daily workload snapshot — active members per hub by business context and profile, using `member_hub_allocation` (replacement for the deprecated `agent_hub_alocation`).

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

> **Note:** `YEAR`/`MONTH`/`DAY` follow Trino/Presto syntax. Partition columns are integers — never filter the daily tables with `dt_reference BETWEEN`.

### Reconciliation: BigAgent vs Nazaré revenue share (For-Sale)

```sql
SELECT
    ars.revenue_source,
    ars.revenue_role,
    COUNT(DISTINCT ars.id_offer)  AS offers,
    SUM(ars.revenue_amount)       AS total_amount
FROM datalake_agent_payments.agent_revenue_share AS ars
WHERE ars.year = 2026 AND ars.month = 6
GROUP BY 1, 2          -- never SUM without grouping/filtering revenue_source
ORDER BY 1, 2;
```

### CIQ portfolio loss (Compra de Carteira)

Current-state rows flagged by the business rule on the DW fact (relist published, no rent contract, >90 days since version publish).

```sql
SELECT
    f.sk_house,
    f.sk_house_listing,
    f.sk_partner,
    f.sk_user,
    f.listing_category,
    f.listing_status,
    f.total_days_since_publish,
    f.ts_publicated,
    f.is_portfolio_loss
FROM dw_ciq.fact_ciq_listing_purchase AS f
WHERE f.is_portfolio_loss = true;
```

> For ad-hoc checks on enrich inputs only, the same rule is  
> `listing_category = 'Re-Listing'` + `listing_status IN ('PUBLISHED', 'publicado')` + `ts_contract_signed IS NULL` + `total_days_since_publish > 90` on `datalake_ciq.ciq_listing_purchase`.
