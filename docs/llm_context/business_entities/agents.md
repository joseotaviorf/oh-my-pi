# Agents

## Overview

- **Objective:** QuintoAndar field agents and their full operating lifecycle — accreditation, identity & capabilities, hub allocation, performance tiers, brokerage/revenue earnings, and Preferred Fixed/Property Agent assignment.
- **Asset status / lifecycle:** prospect (intends to create account) → accreditation (CRECI validation, contract signature) → first commercial event (first listing / TQC referral / PPA) → activated → tiered → paid (revenue share) → churned/inactive.
- **Typical actions / events:** sign-up, qualification steps, contract signature, region/hub allocation, visit and listing operations, brokerage/CIQ commissioning, tier assignment.
- **Common metrics:** active agents (monthly), CIQ-active agents, agents per hub, brokerage/revenue earned per agent, active PFA relations, new-agent activation rate.
- **Source systems:** EBDB (agent, prospect, qualification, contract), Hub Services (membership, NE hierarchy), Amplitude (sign-up funnel), BigAgent (earnings/tiers/incentives), Nazaré (payments), Airtable/GSheets (ops manual data).
- **Related entities:** for visit metrics see [`visits.md`](visits.md); for AI chatbots (Wall-E, Matthew, Sauron, Dominic/Matias) see [`chatbot_sessions.md`](chatbot_sessions.md) and [`matthew.md`](matthew.md) — those are **not** field agents.

> ⚠ **Two orthogonal axes — always pin down both before querying.** (1) **Operation type** = `profile` (what work the agent physically does); (2) **Business function** = which part of the deal the agent owns (what they earn for). Most tables mix everything unless filtered. Affiliation (`1P`/`3P`) is a third, independent axis.

### ⚠⚠ Layer priority — **always start with DW**

**Default rule for every analyst query in this domain: use `dw_*` tables first.** Enrich (`datalake_*`) and clean (`datalake_*_clean`) are upstream implementation layers — query them **only** when the DW table does not exist yet, or when you need a specific column intentionally not projected into the DW.

| Layer | Prefix | When to use |
|-------|--------|-------------|
| **DW (default)** | `dw_*` | **Always** — dashboards, KPIs, ad-hoc analysis, joins to other DW entities |
| Enrich | `datalake_*` | Fallback — field missing from DW, pipeline debugging, pre-DW exploratory work |
| Clean / raw | `datalake_*_clean`, `datalake_*_raw` | Engineering / lineage only — never the first choice for business questions |

**DW tables available today in this domain:**

| Topic | DW table(s) | Enrich fallback (only if needed) |
|-------|-------------|----------------------------------|
| BigAgent earnings, tiers & partner payments | `dw_agent_payments.fact_earnings`, `fact_partner_payments`, `dim_earning_sources`, `dim_tier`, `fact_partner_tier` | `datalake_big_agent.earnings`, `partner_tier`, `tier_rule`; enrich `datalake_agent_payments.partner_payments` |
| CIQ Compra de Carteira | `dw_ciq.fact_ciq_listing_purchase`, `fact_listing_purchase_duplicity` | `datalake_ciq.ciq_listing_purchase`, `listing_purchase_duplicity` |
| Daily agent state (new ID system) | `dw_agent.fact_agent_daily`, `dim_agent` | `datalake_agent_accreditation.agent` |
| Legacy `sk_agent ↔ id_user` bridge | `dw_public.dim_agent` | — |
| Visits | `dw_visit.fact_visits`, `fact_visit_schedules` | see [`visits.md`](visits.md) |

> Topics **without a DW table yet** (enrich is the only option): hub allocation (`member_hub_allocation`), monthly reports (`agent_status_by_month`, `agent_new_agent_activation_metrics`), For-Rent broker share (`brokerage_share_history`), PFA/PPA (`preferred_property_agent_relation_history`), tier performance EAV (`agent_performance`).

### Operation type (`profile`)

`Visita` (property visits — most common; usually what "agente" means), `Vistoria` (inspections), `VistoriaQuarteirizada` (outsourced visits/inspections), `SessaoFotos` (photographers), `CheckUpLar` (repairs). Default scope for CIQ/activation/brokerage questions is `Visita`, but confirm.

### Business function (the three that matter most)

These are the functions business teams mean by "demand agent", "TQC" / "TQA", and "CIQ". One agent can hold several at once; they are NOT mutually exclusive and are separate from `profile`.

| Function | Also called | What they own | Capability (`capability.type`) | Earns (in `fact_partner_payments`) |
|---|---|---|---|---|
| **Demand / conversion** | demand agent, visit agent | Conduct the visit **and convert** the deal | `DEMAND_VISIT_MANAGEMENT` (RENT/SALE) | `revenue_role = DEMAND`, `incentive_system` `DEMAND_CONVERSION_FS` (Sale) or `DEMAND_CONVERSION_FR` (Rent); `revenue_amount`, `revenue_percentage` |
| **Demand acquisition (Sale)** | **TQC** (Traz Quem Compra) | Bring / qualify the **buyer** lead (For-Sale) | `DEMAND_ACQUISITION` (rows in `agent_lead_referral` with `business_context = 'SALE'`) | `revenue_role = DEMAND`, `incentive_system = DEMAND_ACQUISITION_FS` (separate row, often alongside conversion); `revenue_amount`, `revenue_percentage` |
| **Demand acquisition (Rent)** | **TQA** (Traz Quem Aluga) | Bring / qualify the **tenant** lead (For-Rent) — rent counterpart of TQC | `DEMAND_ACQUISITION` (rows in `agent_lead_referral` with `business_context = 'RENT'`) | `revenue_role = DEMAND`, `incentive_system = DEMAND_ACQUISITION_FR`; splits from TQC by `business_context = 'RENT'` |
| **Supply acquisition** | **CIQ** | Register / bring the property (supply) | `SUPPLY_ACQUISITION`, `SUPPLY_CONVERSION_CONSULTANCY` | `revenue_role = SUPPLY`, `incentive_system` `SUPPLY_ACQUISITION_FS` (Sale) or `SUPPLY_ACQUISITION_FR` (Rent); `revenue_amount`, `revenue_percentage` |

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

DW / enrich schemas described here: **`datalake_agent_accreditation`**, **`datalake_agent_reports`**, **`datalake_hub_services`**, **`datalake_agent_payments`**, **`datalake_big_agent`**, **`dw_agent_payments`**, **`datalake_ebdb_agents`**, **`datalake_tiers`**, **`datalake_ciq`**, **`dw_ciq`**, **`datalake_brokerage`**, and the (stale) **`dw_agent`** star schema.

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
| **TQC (Traz Quem Compra)** | **Demand-acquisition function on Sale** — agent who brings/qualifies the buyer lead | Capability `DEMAND_ACQUISITION`; source `datalake_ebdb_clean.agent_lead_referral` with `business_context = 'SALE'`; `id_user_agent_lead_referral` in `datalake_sale_offer_flows.offer_specialists`; `revenue_percentage` on `DEMAND_ACQUISITION_*` rows in `dw_agent_payments.fact_partner_payments`. |
| **TQA (Traz Quem Aluga)** | **Demand-acquisition function on Rent** — agent who brings/qualifies the tenant lead. Rent counterpart of TQC. | Capability `DEMAND_ACQUISITION`; source `datalake_ebdb_clean.agent_lead_referral` with `business_context = 'RENT'`. |
| **CIQ (function)** | **Supply-acquisition function** — agent who registers/brings the property | Capability `SUPPLY_ACQUISITION` / `SUPPLY_CONVERSION_CONSULTANCY`; `revenue_role = SUPPLY`, `incentive_system` `SUPPLY_ACQUISITION_*`, `revenue_percentage`. Distinct from the CIQ *program* (next row). |
| **PPA (Preferred Property Agent)** | Agent fixed to a listing (agent brought the supply) | `preferred_property_agent_relation_history`. |
| **PFA (Preferred Fixed Agent)** | Agent fixed to a lead (usually first-visit; see `origin`) | Same table; reason in `origin`. |
| **BIG_AGENT** | Newer brokerage/earnings model | `revenue_source = 'BIG_AGENT'` in `dw_agent_payments.fact_partner_payments`; earning-level detail in `dw_agent_payments.fact_earnings`. |
| **Nazaré** | Legacy per-offer brokerage / payment system | `revenue_source = 'NAZARE'`. |
| **VBBA / VCBA** | Visits Booked / Completed Booked **By Agent** | `sk_author_creator = sk_user_agent` in `dw_visit.fact_visit_schedules` (+ `is_completed = 1` for VCBA). |
| **Hub / Business Unit** | Regional agent grouping | `hub_name`, `id_business_unit` in `member_hub_allocation`. |
| **EN / Negotiation Executive** | QA staff responsible for an agent's hub | NE = parent member (`id_parent_user`, `user_parent_*`) in `member_hub_allocation`; `id_negotiation_executive_user` in `agent`. |
| **Capability / capacidade** | Fine-grained permission | `capability.type + status` (raw source `datalake_ebdb_clean.capability`); for booleans use `agent.is_allow_*`. Prefer over legacy subtype jargon. |
| **Primeira listagem / first listing** | ⚠ "any first listing" vs "valid first listing" (dedup-gated) | Valid first listing gated by `datalake_listing_deduplication.valid_first_listing`; used for CIQ payment eligibility and activation. Default to valid for CIQ/activation, confirm. |
| **Valid First Listing** | A first listing that survives property **deduplication** — a re-listed / duplicated property does NOT count again | Custom QuintoAndar concept; lives in `datalake_listing_deduplication`. ⚠ Metric definition still evolving — see schema section. |
| **Compra de Carteira / CIQ listing purchase** | CIQ_FULL rent **listing-purchase** — eligibility, initial vs final pricing, portfolio loss | **DW:** `dw_ciq.fact_ciq_listing_purchase`. Enrich fallback: `datalake_ciq.ciq_listing_purchase` (initial pricing only). |
| **Perda de carteira / portfolio loss** | Relist still on market >90 days without a signed rent contract | **`dw_ciq.fact_ciq_listing_purchase.is_portfolio_loss`** only — not on enrich. |
| **Initial pricing segment** | Transition-rule speculation before duplicity / previous-paid overrides | `initial_pricing_type` / `initial_pricing_type_reason` on `datalake_ciq.ciq_listing_purchase` only. |
| **Final pricing segment** | Category after previous-paid and paid-similar-house rules | `pricing_type` / `pricing_type_reason` on `listing_purchase_pricing` / fact (not the enrich base columns). |
| **Re-Listing (rent version category)** | New rent listing cycle after a prior rental ended | `listing_category = 'Re-Listing'` on purchase rows (from `datalake_ebdb_listing.house_listing`). See [`house_and_listing.md`](house_and_listing.md). |

---

## Where to query what

> **Routing rule:** pick the **DW** row first. Use the enrich/clean fallback column only when the DW table is missing the column you need or does not exist for that topic.

| You need… | **Start here (DW)** | Fallback (enrich/clean — only when DW is insufficient) |
|-----------|---------------------|--------------------------------------------------------|
| BigAgent earnings, tiers, partner assignments | **`dw_agent_payments.fact_earnings`**, `dim_earning_sources`, `dim_tier`, `fact_partner_tier` | `datalake_big_agent.earnings`, `partner_tier`, `tier_rule` |
| Partner payments to agents and companies (Sale + Rent) | **`dw_agent_payments.fact_partner_payments`** | `datalake_agent_payments.partner_payments` |
| Sale offer context for a partner payment | **`dw_sale.fact_offers`**, `dw_sale.dim_offer` | — |
| Rent contract context for a partner payment | **`dw_rent.fact_contracts`**, `dw_rent.dim_contract` | — |
| BigAgent earning-source calculation audit trail | **`dw_agent_payments.fact_earning_calculation_log`** | `datalake_big_agent_clean.earning_sources_aud` |
| CIQ Compra de Carteira (pricing, portfolio loss, eligibility) | **`dw_ciq.fact_ciq_listing_purchase`** | `datalake_ciq.ciq_listing_purchase` (initial pricing only), `listing_purchase_pricing` |
| CIQ listing-purchase duplicity peers | **`dw_ciq.fact_listing_purchase_duplicity`** | `datalake_ciq.listing_purchase_duplicity` |
| Daily per-agent state snapshot (status, capabilities, profile) | **`dw_agent.fact_agent_daily`** | `datalake_agent_accreditation.agent` (identity only; no daily history) |
| Agent dimension (new ID system) | **`dw_agent.dim_agent`** | `datalake_agent_accreditation.agent` |
| Legacy `sk_agent ↔ id_user` bridge | **`dw_public.dim_agent`** | — |
| Visit funnel / completion metrics | **`dw_visit.fact_visits`**, `fact_visit_schedules` | see [`visits.md`](visits.md) |
| Canonical agent identity, capability flags (no DW daily grain) | — | `datalake_agent_accreditation.agent` |
| Fine-grained capabilities (per type, business context) | — | `datalake_ebdb_clean.capability` (+ `demand_visit_management_capability_settings`). Boolean rollups: `agent.is_allow_*`. |
| Prospect onboarding ops queue (CRECI / contract / signup / EN) | — | `datalake_agent_accreditation.prospect_step_validation` |
| Sign-up funnel blocking events (Amplitude) | — | `datalake_agent_accreditation.signup_profile_conflict` |
| Agent geo-region assignment history | — | `datalake_agent_accreditation.agent_major_region_code` |
| Agent status + CIQ (monthly snapshot) | — | `datalake_agent_reports.agent_status_by_month` |
| New-agent activation funnel (monthly cohort) | — | `datalake_agent_reports.agent_new_agent_activation_metrics` |
| Per-agent support tickets (monthly) | — | `datalake_agent_reports.agent_support_tickets_by_month` |
| Agent hub assignment, NE, region (daily) | — | `datalake_hub_services.member_hub_allocation` |
| Partner payments to agents and companies | **`dw_agent_payments.fact_partner_payments`** | `datalake_agent_payments.partner_payments` |
| For-Rent contract broker share (revision history) | — | `datalake_big_agent.brokerage_share_history` |
| Per-offer brokerage fee (Nazaré legacy) | — | `datalake_brokerage.partner_brokerage` |
| Valid first listing (dedup-gated) for CIQ / activation | — | `datalake_listing_deduplication.valid_first_listing` |
| CIQ first-listing validation for tiers (15-day rule) | — | `datalake_tiers.ciq_first_listing` |
| Property dedup analysis / duplicate detection | — | `datalake_listing_deduplication.listing_deduplication` |
| Performance metrics for tiering (EAV) | — | `datalake_tiers.agent_performance` |
| PFA/PPA relation per listing | — | `datalake_ebdb_agents.preferred_property_agent_relation_history` |
| PFA program eligibility | — | `datalake_ebdb_agents.preferred_property_agent_program_eligibility` |
| 3P agent type + contract history | — | `datalake_ebdb_agents.agent_3p_history` |
| ⚠ Historical visit-agent performance (STALE) | — | `dw_agent.fact_visit_agent_performance`, `datalake_visit_agent_performance.*` (pipeline stopped 2025-09-21) |

---

## `datalake_agent_accreditation`

**Purpose:** unified agent identity, capabilities, and accreditation/prospect funnel. Hub node for the domain.

> ⚠ **DW first for daily state:** use **`dw_agent.fact_agent_daily`** / **`dw_agent.dim_agent`** for per-day capability and status questions. Use enrich `agent` here for canonical `id_agent` identity, CRECI, and capability flags when you do not need daily history.

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

> ⚠ **DW first:** for partner payments, earnings, and tier questions, start at **`dw_agent_payments`** (see next section). The enrich tables below are upstream fallbacks or rent-contract share history.

Two distinct earning concepts — **do not conflate**:

### Partner payments — **`dw_agent_payments.fact_partner_payments`** (source of truth)

**Purpose:** unified partner payment lines paid to **agents** (`sk_person` / `sk_user`) and **companies** (`sk_company`) across Big Agent calculated earnings and Nazaré revenue-share participants. **Pipeline:** enrich `enrich_agent_payments.partner_payments` → DW `dw_agent_payments.fact_partner_payments`, incremental MERGE on `sk_partner_payment`, load window on `DATE(ts_updated)`, partitions `year/month/day` derived from `ts_created`.

Grain: **one row per `sk_partner_payment`** (= enrich `id_partner_payment`). A single Sale offer can have multiple rows (e.g. `DEMAND_CONVERSION_FS` + `DEMAND_ACQUISITION_FS` TQC + `SUPPLY_ACQUISITION_FS` CIQ; or side-by-side `BIG_AGENT` vs `NAZARE` rows for reconciliation). Person/company keys are resolved in the DW via `uuid_person` → `datalake_person.person_sks` and `uuid_company` → `datalake_company.company_sks`.

| Topic | Fields |
|-------|--------|
| Keys | `sk_partner_payment` (PK), `sk_earning` (Big Agent earning id when `revenue_source = 'BIG_AGENT'`), `sk_earning_source`, `sk_revenue_share`, `sk_house`, `sk_contract`, `sk_offer`, `sk_business_unit`, `sk_tier`, `sk_user`, `sk_person`, `sk_company` |
| Discriminators | `business_context` (`SALE` / `RENT`), `revenue_source` (`BIG_AGENT` / `NAZARE`), `revenue_role` (`DEMAND` / `SUPPLY`), `incentive_system`, `participant_role`, `revenue_receiver_type` (`AGENT` / `COMPANY`) |
| Amounts | `ticket_base_amount`, `brokerage_fee`, `brokerage_amount`, `revenue_amount`, `revenue_percentage`, `revenue_share_type`, `revenue_share_value` |
| Flags | `is_3p_lead_gen_offer`, `is_fifty_revenue_share`, `is_crcc_revenue_share`, `is_tier_revenue_share` |
| Tier context | `tier_name`, `dt_tier_reference` |
| Timing | `ts_created`, `ts_updated`, `ts_load`; partitions `year/month/day` from `ts_created` |

**Transaction context (join out for detail):**

| Context | Join from `fact_partner_payments` | Detail tables |
|---------|-----------------------------------|---------------|
| **Sale offer** | `sk_offer` | **`dw_sale.fact_offers`**, **`dw_sale.dim_offer`** — offer status, sale price, brokerage fee, buyer/owner keys, 3P flags |
| **Rent contract** | `sk_contract` | **`dw_rent.fact_contracts`**, **`dw_rent.dim_contract`** — contract status, rent amounts, listing linkage |

> **Double-count trap:** always filter `revenue_source` (and usually `incentive_system` / `revenue_role`) before any `SUM` — the table UNIONs Big Agent and Nazaré paths and can emit multiple rows per offer/contract. Enrich fallback: `datalake_agent_payments.partner_payments` (same grain; no `sk_*` resolution).

### `datalake_big_agent.brokerage_share_history` — For-Rent contract broker share

**Purpose (ADR 2026-06-19):** version-controlled source of truth for `agent_brokerage_share` (rent contracts), after migration off the deprecated EBDB `contract.agent_brokerage_share` column. **Pipeline:** `enrich_big_agent_incentives`, incremental MERGE on `(id_revision, id_contract)`, partitioned by `dt_load`.

Grain: **one row per `(id_revision, id_contract)`**. Columns: `id_revision`, `id_contract`, `agent_brokerage_share`, `ts_revision`, `dt_load`.

- Primary source: `datalake_big_agent_clean.new_earnings_aud` (`DEMAND_CONVERSION_FR`).
- Fallback (legacy contracts with no BigAgent earning source): `datalake_ebdb_clean.contract_aud`.

> **Revision granularity:** apply `ROW_NUMBER()`/`LAST_VALUE` to get the current share per contract — this is NOT one row per contract. The EBDB `contract.agent_brokerage_share` column is removed; do not read it.

---

## `dw_agent_payments` (Big Agent Incentives DW)

**Purpose:** Kimball DW projection of the Big Agent Incentives Engine — **the default entry point for all BigAgent earnings and tier analysis.** **Pipeline:** `dw_agent_payments` DAG, incremental MERGE, partitioned `year/month/day`.

> ⚠ **Name collision:** `datalake_agent_payments` (enrich — `partner_payments` upstream) ≠ **`dw_agent_payments`** (DW — earnings + partner payments star schema). Same domain word, different layer; prefer the DW tables for analysis.

**Upstream:** enrich `datalake_big_agent.*` and clean `datalake_big_agent_clean.*`. Person/company/cart keys are pre-resolved through **`datalake_person.person_sks`**, **`datalake_company.company_sks`**, and **`datalake_cart_system_clean.cart`** — prefer joining other DW entities through these `sk_*` columns rather than re-deriving from enrich.

### Layer routing (DW default)

| Need | **Use (DW)** | Enrich fallback (only if column missing) |
|------|--------------|------------------------------------------|
| Partner payments to agents and companies | **`fact_partner_payments`** | `datalake_agent_payments.partner_payments` |
| Earnings KPIs, dashboards, agent/tier joins | **`fact_earnings`** | `datalake_big_agent.earnings` |
| Earning source status / failure context | **`dim_earning_sources`** | `datalake_big_agent_clean.earning_sources` |
| Tier score rules | **`dim_tier`** | `datalake_big_agent.tier_rule` |
| Partner tier assignments | **`fact_partner_tier`** | `datalake_big_agent.partner_tier` |
| Calculation status audit trail | **`fact_earning_calculation_log`** | `earning_sources_aud` |
| Revenue share / invalidation / unresolved-earning **record ids** | join enrich on `sk_earning = id_earning` | `datalake_big_agent.earnings` |
| Sale offer detail for a payment row | **`dw_sale.fact_offers`**, `dw_sale.dim_offer` via `sk_offer` | — |
| Rent contract detail for a payment row | **`dw_rent.fact_contracts`**, `dw_rent.dim_contract` via `sk_contract` | — |

### Star schema

```
dim_earning_sources ──┐
dim_tier ─────────────┼──► fact_earnings ◄── fact_partner_tier
                      │
fact_partner_payments (partner payments; joins to dw_sale / dw_rent for transaction context)
                      │
fact_earning_calculation_log (operational; joins on sk_earning_source)
```

### `fact_earnings`

Grain: **one row per `sk_earning`** (BigAgent earning id), incremental on `ts_updated`. Excludes `invalidation_reason = 'PRODUCT_TESTING'`.

| Topic | Fields / notes |
|-------|----------------|
| Keys | `sk_earning` (PK), `sk_replacement_earning`, `sk_earning_source` |
| Domain context | `sk_contract`, `sk_sales_flow` — natural contract/sales-flow ids from the earning source (not full EBDB/sales DW dims) |
| Actor keys | `sk_author`, `sk_invalidation_author` — resolved to **`sk_person`** via `person_sks` (`id_author` / `id_invalidation_author` matched on `uuid_person`); null when the actor is SYSTEM |
| Receiver keys | `sk_person`, `sk_company` — partner receiver resolved from enrich `uuid_person` / `uuid_company` |
| Tier context | `sk_tier`, `sk_partner_tier`, `partner_tier_name`, `incentive_system`, `revenue_share_type` |
| Cart | `sk_cart` — resolved from `uuid_cart` when a matching cart exists |
| Amounts | `calculation_base_amount`, `revenue_amount`, `revenue_percentage` |
| Invalidation | `invalidation_reason`, `invalidation_description`, `ts_invalidated`, `is_invalid`, `is_invalid_for_recalculation_reason` (`RECALCULATED`), `is_invalid_for_amount_wrong_reason` (`WRONG_REVENUE_AMOUNT`), `is_replaced` |
| Unresolved queue | `has_unresolved_earning` (derived from `id_unresolved_earning IS NOT NULL`), `unresolved_earning_reason`, `ts_unresolved_earning_solved` — **no `sk_unresolved_earning` in the fact** |
| Flags | `is_calculated`, `is_rent_contract`, `is_sales_flow`, `is_manual_calculation`, `is_authored_by_system` |
| Timing | `dt_payment_due`, `ts_created`, `ts_updated`, `ts_load` |

> **Intentionally not in the fact:** `sk_revenue_share`, `sk_incentive_engine`, `sk_earning_invalidation` — operational lineage keys kept in enrich `datalake_big_agent.earnings`; join back when you need revenue-share or invalidation-record detail.

> **Author keys:** do not treat `sk_author` / `sk_invalidation_author` as raw BigAgent author ids — they are **person surrogate keys** (`sk_person`). Bridge to `id_user` through `datalake_person.person_sks`.

### `dim_earning_sources`

Grain: **one row per `sk_earning_source`**, incremental on `ts_updated`. Projects clean `earning_sources` with contract/sales-flow/cart resolution.

| Topic | Fields |
|-------|--------|
| Keys | `sk_earning_source` (PK), `sk_contract`, `sk_sales_flow`, `sk_cart`, `uuid_cart` |
| Context | `domain_type` (`RENT_CONTRACT` / `SALES_FLOW`), `currency`, `status`, `failure_reason` |
| Amounts | `base_amount`, `revenue_share_total_amount` |
| Timing | `dt_competence`, `ts_occurred`, `ts_created`, `ts_updated` |

### `dim_tier`

Grain: **one row per `sk_tier`**, incremental on `ts_updated`. Projects enrich `datalake_big_agent.tier_rule` — classifier/qualifier score rules expanded per incentive operation (CS, FL_FR, CCV, FL_FS, TQC).

| Topic | Fields |
|-------|--------|
| Keys | `sk_tier` (PK), `sk_business_unit` (hub id when incentive engine condition type is HUB) |
| Classification | `incentive_system`, `incentive_engine_external_condition_type`, `tier_name`, `tier_priority` |
| Score rules | `classifier_min_score`, `qualifier_min_score`, `classifier_resume`, `qualifier_resume`, plus per-operation max/min/multiplier columns |

### `fact_partner_tier`

Grain: **one row per `sk_partner_tier`** (partner tier assignment), incremental on `ts_updated`.

| Topic | Fields |
|-------|--------|
| Keys | `sk_partner_tier` (PK), `sk_new_partner_tier`, `sk_tier`, `sk_person`, `sk_company`, `sk_overwritten_by` |
| Context | `incentive_system`, `tier_name`, `overwritten_reason` |
| Validity | `is_valid`, `is_overwritten`, `is_overwritten_by_ops`, `dt_validity_started`, `dt_validity_ended`, `ts_overwritten` |

> Join `fact_earnings.sk_partner_tier` → `fact_partner_tier.sk_partner_tier` for the assignment valid at earning time; `partner_tier_name` on the fact is a denormalized snapshot.

### `fact_partner_payments`

Grain: **one row per `sk_partner_payment`** (= enrich `id_partner_payment`). Incremental load window: `DATE(ts_updated)` between `{load_start_date}` and `{load_end_date}`. Projects enrich `datalake_agent_payments.partner_payments` with `sk_person` / `sk_company` resolved via LEFT JOIN on `uuid_person` / `uuid_company` to **`datalake_person.person_sks`** and **`datalake_company.company_sks`**.

| Topic | Fields / notes |
|-------|----------------|
| Keys | `sk_partner_payment` (PK), `sk_earning` (non-null when `revenue_source = 'BIG_AGENT'`), `sk_earning_source`, `sk_revenue_share`, `sk_house`, `sk_contract`, `sk_offer`, `sk_business_unit`, `sk_tier`, `sk_user`, `sk_person`, `sk_company` |
| Classification | `business_context` (`SALE` / `RENT`), `revenue_source` (`BIG_AGENT` / `NAZARE`), `revenue_role` (`DEMAND` / `SUPPLY`), `incentive_system`, `participant_role`, `revenue_receiver_type` (`AGENT` / `COMPANY`), `tier_name` |
| Amounts | `ticket_base_amount`, `brokerage_fee` (% on ticket), `brokerage_amount`, `revenue_amount`, `revenue_percentage`, `revenue_share_type`, `revenue_share_value` |
| Flags | `is_3p_lead_gen_offer`, `is_fifty_revenue_share`, `is_crcc_revenue_share`, `is_tier_revenue_share` |
| Tier context | `dt_tier_reference` |
| Timing | `ts_created`, `ts_updated`, `ts_load`; partitions `year/month/day` from `ts_created` |

> **Primary source for partner payments:** use this fact for any question about amounts paid to agents or partner companies. Filter by `incentive_system` and `revenue_role` to isolate conversion vs TQC/TQA vs CIQ rows — each function is a separate payment line, not a wide column (`brokerage_percentage` / `tqc_percentage` / `ciq_percentage` do not exist on this fact). Join **`dw_sale.fact_offers`** / **`dw_sale.dim_offer`** on `sk_offer` for Sale context; join **`dw_rent.fact_contracts`** / **`dw_rent.dim_contract`** on `sk_contract` for Rent context. Bridge agents via `sk_person` / `sk_user` (not raw enrich ids).

### `fact_earning_calculation_log`

Grain: **one row per `(sk_earning_source, incentive_system, ts_started)`** — audit trail of `incentive_systems_calculation_status` changes from `earning_sources_aud`. Operational/debugging table, not a business KPI source.

| Topic | Fields |
|-------|--------|
| Keys | `sk_calculation_log` (PK), `sk_earning_source` |
| Status | `incentive_system`, `calculation_status`, `is_current_status` |
| Validity window | `ts_started`, `ts_ended` (SCD-style; `ts_ended` is `LEAD(ts_started) - 1 day`) |

---

## `datalake_ebdb_agents` (PFA / PPA)

**Purpose:** Preferred Fixed/Property Agent assignment. **Pipeline:** `enrich_ebdb_agents_pfa`.

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

**Purpose:** CIQ_FULL **rent listing-purchase** — which houses qualify for Compra de Carteira, Robin Hood payment state, commercial pricing (initial speculation → final after anti-repurchase rules), and **portfolio loss** (relist published >90 days without renting).

> ⚠ **DW first:** analyst queries **must** start at **`dw_ciq.fact_ciq_listing_purchase`**. Use `datalake_ciq.ciq_listing_purchase` only for `initial_pricing_type*` (pre-override speculation) or pipeline debugging.

**Pipelines:** `enrich_ciq_listing_purchase` → `datalake_ciq.*` → **`dw_ciq_listing_purchase`** → `dw_ciq.fact_ciq_listing_purchase` (+ `fact_listing_purchase_duplicity`).

**Grain (enrich & fact):** one row per **house listing version** in CIQ context (house × `sk_house_listing` × partner × CIQ user × consultant type), not one row per house.

| You need… | **Start here (DW)** | Enrich fallback |
|-----------|---------------------|-----------------|
| Dashboards / OKRs / portfolio loss / final pricing / payment | **`dw_ciq.fact_ciq_listing_purchase`** | — |
| Similar-house / Atlas duplicity peer rows | **`dw_ciq.fact_listing_purchase_duplicity`** | `datalake_ciq.listing_purchase_duplicity` |
| **Initial** pricing segment (pre-override speculation) | — | `datalake_ciq.ciq_listing_purchase` (`initial_pricing_type*`) |
| Final pricing, acquisition, payment, eligibility | **`dw_ciq.fact_ciq_listing_purchase`** | `datalake_ciq.listing_purchase_pricing` |

### Initial vs final pricing (do not conflate)

| Layer | Columns | Meaning |
|-------|---------|---------|
| Base enrich | `initial_pricing_type` / `initial_pricing_type_reason` | Transition-rule **speculation** (e.g. `new-listings`, `ongoing-listings`, `ongoing-rentals`, `hybrid`, `not-eligible`) from publish/contract timing. |
| Pricing enrich / fact | `pricing_type` / `pricing_type_reason` | **Final** segment after previous-paid and paid-similar-house overrides. |
| Pricing enrich / fact | `acquisition_type` / `purchase_value` / `payment_status` / `is_eligible` | Acquisition bucket (full-price / reduced-price / not-eligible), BRL tier, payment lifecycle, eligibility. |

> ⚠ **`payment_status` and `is_eligible` live on `listing_purchase_pricing` / the DW fact** — they are **not** on `ciq_listing_purchase` anymore.

### Anti-repurchase keys on the fact

| Key | Meaning |
|-----|---------|
| `sk_previous_listing_paid` | Another listing on the **same house** was already purchased; points at that prior paid capture (do not buy again). |
| `sk_similar_house_paid` | Another house with a **similar address** was already **paid** in Compra de Carteira; `sk_house` of that paid peer (do not buy the duplicate again). |
| `sk_listing_duplicity` | When address-parse or Atlas paid-dedup matched a peer, join `dw_ciq.fact_listing_purchase_duplicity` for peer detail. |

### Relist vs republication vs portfolio loss

| Signal | Column | Meaning |
|--------|--------|---------|
| Later listing version exists | `has_republication` | On **this** version: a subsequent `sk_house_listing` exists (ordered by version start). Does not by itself mean portfolio loss. |
| This version is a relist cycle | `listing_category = 'Re-Listing'` | Rent listing versioning label from `house_listing` — publication after a prior rental cycle. |
| Start of publish for this version | `ts_publicated` | Anchor for “new publish event” on this listing version (aligns with rent versioning; see [`house_and_listing.md`](house_and_listing.md)). |
| Days since that publish | `total_days_since_publish` | Calendar days from `ts_publicated` to load date for **every** listing version on enrich and fact (no Re-Listing filter in enrich). |
| **Portfolio loss (business rule)** | **`is_portfolio_loss`** | **DW only:** `Re-Listing` AND `listing_status` in (`PUBLISHED`, `PUBLICADO`) AND no signed rent contract on this version (`ts_contract_signed` null) AND `total_days_since_publish > 90`. |

> Do **not** use `total_days_since_house_inactived` for portfolio loss — it counts **inactive** listing-version days, not time on market since publish.

> **`sk_partner`** on the fact is the CIQ partner key (`id_partner` in enrich) for joins to partner-scoped tables.

### Other filters analysts often need

- **CIQ_FULL scope:** enrich rows use `house_consultant_history` with `consultant_type = 'CIQ_FULL'`; pricing filters `business_context = 'RENT'` and `consultant_type = 'CIQ_FULL'`.
- **Payment:** prefer fact/`listing_purchase_pricing` — `payment_status`, `is_paid`, `amount_paid`; fact merge updates matched rows only while `is_paid` is not true.
- **Duplicity flags on base enrich:** `has_similiar_house_by_address_parsed`, `has_similiar_house_by_atlas`; use `sk_listing_duplicity` / `sk_similar_house_paid` for paid-peer anti-repurchase.

---

## `dw_agent` (Agent-Domain star schema)

**Purpose:** DW projection of the new Agent Domain accreditation layer — **prefer `fact_agent_daily` over enrich `agent` for any per-day state question.** **Pipeline:** `dw_agent_accreditation` DAG. Built on the **new** ID system (`sk_agent`), but carries `sk_agent_data` for legacy bridging — see the identity-migration warning above.

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
- **Hub → partner payments:** `datalake_person.person_sks.id_user = agent.id_user` → `person_sks.sk_person = dw_agent_payments.fact_partner_payments.sk_person`; companies via `sk_company`. Filter `revenue_source` before aggregating.
- **Partner payment → Sale offer:** `fact_partner_payments.sk_offer` → **`dw_sale.fact_offers.sk_offer`** / **`dw_sale.dim_offer`** for offer status, pricing, and participant keys.
- **Partner payment → Rent contract:** `fact_partner_payments.sk_contract` → **`dw_rent.fact_contracts.sk_contract`** / **`dw_rent.dim_contract`** for contract status and rent terms.
- **Hub → BigAgent earnings (DW):** `datalake_person.person_sks.id_user = agent.id_user` → `person_sks.sk_person = dw_agent_payments.fact_earnings.sk_person` (receiver) or `.sk_author` (author).
- **Earnings fact → dimensions:** `fact_earnings.sk_earning_source` → `dim_earning_sources.sk_earning_source`; `sk_tier` → `dim_tier.sk_tier`; `sk_partner_tier` → `fact_partner_tier.sk_partner_tier`.
- **Earnings enrich detail:** `fact_earnings.sk_earning` = `datalake_big_agent.earnings.id_earning` for revenue-share / invalidation / unresolved-earning keys not projected in the fact.
- **Hub → Compra de Carteira:** `agent.id_partner = fact_ciq_listing_purchase.sk_partner` and/or `agent.id_user = fact_ciq_listing_purchase.sk_user` (grain is listing-version × partner, not one row per agent).
- **Identity bridge (legacy):** `dw_public.dim_agent.id_user = agent.id_user`; bridge legacy `sk_agent ↔ id_user` through `dw_public.dim_agent`. ⚠ This `sk_agent` is the **legacy** star-schema key — NOT the same as `dw_agent.*.sk_agent` (new). To cross legacy↔new, bridge through a table carrying both `sk_agent` and `sk_agent_data` (e.g. `dw_agent.fact_agent_daily`). See the identity-migration warning.
- **Visits:** agents link to `dw_visit.fact_visits` / `fact_visit_schedules` via `sk_agent`; see [`visits.md`](visits.md).
- **Support tickets:** `agent_support_tickets_by_month` → `dw_customer_support.fact_tickets`.

---

## Dos and don'ts

**Do:**

- **Always start with `dw_*` tables** when a DW projection exists for the topic (earnings → `dw_agent_payments`, Compra de Carteira → `dw_ciq`, daily agent state → `dw_agent`, visits → `dw_visit`). Drop to enrich/clean only for missing columns or topics without DW coverage.
- Confirm **both axes** before scoping: **operation type** (`profile`: `Visita`/`Vistoria`/…) and **business function** (demand/conversion vs demand-acquisition/TQC vs supply-acquisition/CIQ). Most tables mix everything.
- Confirm what "active agent", "activation", and "first listing" mean — each maps to a different table/filter (see Synonyms).
- Translate legacy jargon ("Demand Agent", "CIQ-Only", "Independent Agent") to capability/`agent_type_segment` filters, not literal column values.
- Use `datalake_agent_accreditation.agent` for canonical `id_agent` identity; for **daily state** prefer **`dw_agent.fact_agent_daily`**; bridge `sk_agent ↔ id_user` via `dw_public.dim_agent`.
- Filter `revenue_source` in **`fact_partner_payments`** before any aggregation (Big Agent vs Nazaré UNION).
- For **partner payments to agents and companies**, **always** query **`dw_agent_payments.fact_partner_payments`** first; enrich `datalake_agent_payments.partner_payments` only for pipeline debugging or columns not projected to DW.
- For **BigAgent earning-level** detail (invalidation, revenue-share record ids), join **`fact_partner_payments.sk_earning`** → **`fact_earnings.sk_earning`** or enrich `datalake_big_agent.earnings`.
- Resolve earning authors through **`sk_person`** (`sk_author`, `sk_invalidation_author`) — bridge to `id_user` via `datalake_person.person_sks`, not via raw BigAgent author ids.
- Apply `ROW_NUMBER()`/`LAST_VALUE` on `brokerage_share_history` to get the current share per contract.
- Filter `ts_relation_ended IS NULL` (active PFA) and `ts_status_ended IS NULL` (current eligibility).
- Filter daily tables by integer `year = X AND month = X AND day = X`, not `dt_reference BETWEEN` (scans all partitions).
- For `offer_flow_events` / `offer_flow_performance`, add `WHERE ts_event > DATE '2010-01-01'` (epoch-overflow min dates show as `1899-12-29`).
- For **CIQ portfolio loss**, use **`dw_ciq.fact_ciq_listing_purchase.is_portfolio_loss`** — do not re-derive from `has_republication` alone (that flag is on the **prior** cycle when a later version exists).
- For Compra de Carteira **pricing**, use **`pricing_type`** (final) on the fact/pricing enrich — not `initial_pricing_type` on the base enrich (that is pre-override speculation).
- Join **listing relist semantics** to [`house_and_listing.md`](house_and_listing.md) when explaining `listing_category` vs sale hybrid tables.

**Don't:**

- **Query enrich or clean when a DW table covers the same topic** — e.g. do not use `datalake_big_agent.earnings` for earnings KPIs (`dw_agent_payments.fact_earnings`), `datalake_ciq.ciq_listing_purchase` for portfolio loss (`dw_ciq.fact_ciq_listing_purchase`), or `datalake_agent_accreditation.agent` for daily capability history (`dw_agent.fact_agent_daily`).
- **Mix the two ID systems.** `sk_agent`/`id_agent` (new Agent Domain) ≠ `sk_agent_data`/`id_agent_data` (legacy `dadosAgent`). The column `sk_agent` exists in both `dw_public.dim_agent` (legacy) and `dw_agent.*` (new) with different value spaces — never join them directly; bridge through a table carrying both keys (`dw_agent.fact_agent_daily`).
- Confuse **`fact_partner_payments`** (unified partner payment lines — agents and companies) with **`brokerage_share_history`** (For-Rent contract broker share revision history) — different scopes, grains, and DAGs.
- Confuse **`datalake_agent_payments.partner_payments`** (enrich upstream) with **`dw_agent_payments.fact_partner_payments`** (DW source of truth for payments) — prefer the DW fact for analysis.
- Expect `sk_revenue_share`, `sk_incentive_engine`, or `sk_unresolved_earning` on **`dw_agent_payments.fact_earnings`** — use enrich `datalake_big_agent.earnings` or the `has_unresolved_earning` flag instead.
- Treat `sk_author` / `sk_invalidation_author` as BigAgent operational ids — they are **`sk_person`** values resolved through `person_sks`.
- Use `datalake_hub_services.agent_hub_alocation` (deprecated, typo `alocation`) or `agent_hub_relation` (deprecated) — use `member_hub_allocation` with `is_active = true`.
- Read EBDB `contract.agent_brokerage_share` (removed) or `dw_public.dim_agent.rede_partner` (deprecated).
- Use `dw_agent.fact_visit_agent_performance` or any `datalake_visit_agent_performance.*` for current data — pipeline stopped **2025-09-21**; historical only, no confirmed replacement as of 2026-06.
- Reference `dw_brokers.dim_brokers` (trailing `s`) — `DELTA_LAKE_INVALID_SCHEMA`; use `dw_public.dim_agent`.
- Treat `datalake_big_agent.house_consultant_history.consultant_type` (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) as stable — active RFC pending.
- Assume AI agents (Wall-E, Matthew, Sauron, Dominic/Matias) belong here — see [`chatbot_sessions.md`](chatbot_sessions.md).
- Use **`total_days_since_house_inactived`** as “days available without rent” for Compra de Carteira — use **`total_days_since_publish`** / **`is_portfolio_loss`** on `dw_ciq.fact_ciq_listing_purchase`.
- Expect **`is_portfolio_loss`**, final **`pricing_type`**, **`payment_status`**, or **`is_eligible`** on `datalake_ciq.ciq_listing_purchase` — portfolio loss is DW-only; final pricing/payment/eligibility live on **`listing_purchase_pricing`** / the fact. Base enrich has **`initial_pricing_type*`** only.
- Treat **`sk_similar_house_paid`** as “any similar address” — it is specifically the **already-paid** similar house (anti-repurchase).

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

### Partner payments by revenue source (BigAgent vs Nazaré)

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
GROUP BY 1, 2, 3       -- never SUM without filtering revenue_source
ORDER BY 1, 2, 3;
```

> Join **`dw_sale.fact_offers`** / **`dw_sale.dim_offer`** on `sk_offer` for offer-level attributes. For Rent rows, join **`dw_rent.fact_contracts`** / **`dw_rent.dim_contract`** on `sk_contract`.

### BigAgent earnings by incentive system (DW)

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

> Filter `has_unresolved_earning = false` for fully resolved earnings. Join **`dw_agent_payments.dim_earning_sources`** on `sk_earning_source` for source status — only join enrich `datalake_big_agent.earnings` when you need revenue-share or invalidation-record ids not in the fact.

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
> `listing_category = 'Re-Listing'` + `listing_status IN ('PUBLISHED', 'PUBLICADO')` + `ts_contract_signed IS NULL` + `total_days_since_publish > 90` on `datalake_ciq.ciq_listing_purchase`.
