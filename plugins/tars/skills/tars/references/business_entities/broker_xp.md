# Broker XP (Marketplace QuintoAndar)

## Overview

Broker XP is QuintoAndar's **Marketplace** operation — a B2B2C model where partner real-estate companies (imobiliárias) and autonomous agents transact through QuintoAndar's platform. The team is known internally as **3P Partners** / **Broker XP**; externally and to business stakeholders as **Marketplace**; legacy names still in use: **Rede** and **For Brokers**.

Three business models coexist under Marketplace:

1. **3P Supply** (TSI — Traga Seus Imóveis): partner brings the inventory, QuintoAndar brings the demand. Drilled in [`3p_supply.md`](./3p_supply.md).
2. **3P Demand** (TSC — Traga Seus Clientes): QuintoAndar has the house, partner brings the buyer/tenant. Drilled in [`3p_demand.md`](./3p_demand.md).
3. **3P Lead Gen** (CQA — Clientes QuintoAndar): QuintoAndar generates leads from its traffic and hands them off to partners. Drilled in [`3p_demand.md`](./3p_demand.md) (shares the demand-side funnel).

**Partner lifecycle.** An imobiliária is onboarded by the Marketplace commercial team (Hunting), registered in **Magic Link** (the tool that consumes the internal **Company** service), and must have at least one product active (Rede Sale or Rede Rent) to operate. Partner agents (3P agents) and broker admins are registered at the same time and become available in the Agents data model with the `third_party_agent` profile. The Broker model (`dw_brokers`) is the authoritative source of truth for partner identity and credentialing — it replaces the legacy `dw_company` / `dim_company_3p_partners` tables (see Dos and Don'ts for the full de/para).

**1P vs 3P.** Properties (`is_3p_supply = TRUE`) and demand (`is_3p_demand` / `is_3p_lead_gen = TRUE`) originating from the Marketplace are categorised as **3P**; everything else is **1P**. This is the primary routing key in cross-domain models (Houses, Listings, Visits, Offers, Buyer Prospects, Supply funnel, Agents) — see "Identifying 3P records in other entities" below.

## Glossary and Synonyms

- **Marketplace**, **3P Partners**, **Broker XP**, **Rede**, **rede de parceiros**, **For Brokers** → the same operation. **Rede** and **For Brokers** are legacy and only appear in column names / DAG names being migrated.
- **1P vs 3P** → origin of supply/demand. 1P = QuintoAndar-owned; 3P = brought in by the partner network.
- **Imobiliária**, **broker**, **parceiro** → partner real-estate company → `dw_brokers.dim_broker` (`sk_broker`).
- **3P Supply**, **TSI**, **Traga Seus Imóveis** → partner inventory model. Flag: `is_3p_supply = TRUE`.
- **3P Demand**, **TSC**, **Traga Seus Clientes** → partner-brought buyer/tenant. Flag: `is_3p_demand = TRUE`.
- **3P Lead Gen**, **CQA**, **Clientes QuintoAndar** → lead handoff model. Flag: `is_3p_lead_gen = TRUE`.
- **Magic Link**, **Company** → the partner registration tool (Magic Link) backed by the internal Company service. Source of truth for `core_brokers.brokers` and `dw_brokers.dim_broker`.
- **Account Manager**, **AM**, **dono da conta** → HubSpot owner currently assigned to the broker → `dim_broker.sk_person_account_manager`; history in `dim_broker_account_manager_history`. **Only HubSpot field still in use** — all other HubSpot-derived attributes are deprecated.
- **BSP** (Broker Supply Platform), **portal do parceiro** → partner portal where leads are submitted. Detailed in [`3p_supply.md`](./3p_supply.md).
- **3P agent**, **agente 3P**, **corretor da Rede**, **corretor parceiro** → autonomous broker working at an imobiliária → `dim_agent.agent_type = 'CORRETOR_REDE'` / `is_3p_agent = TRUE`.
- **Broker admin** → person who administers the broker registry in Magic Link → `dim_broker_profile_history.profile = 'company_admin'`.
- **Passive lead receiver** → a 3P agent enabled to operate in Lead Gen → `is_passive_lead_receiver = TRUE`.
- **Tier**, **programa** → commercial tier of a broker product → `dim_broker_products.tier_name`; history in `dim_broker_tier_history`.
- **Integrator partner**, **integrador** → external CRM/integration provider used by the broker → `dim_broker_products.integrator_partner`; history in `dim_broker_integrator_partner_history`.
- **Business context** → `SALE` or `RENT`. Carried in `dim_broker_products`, `dim_broker_regions`, `dim_broker_status_history`.
- **Buyer Prospect**, **NBP**, **RBP** → For Sale demand-side prospect classification (New / Recovery Buyer Prospect). Detailed in `dim_buyer_prospect_3p_history`; full demand-side coverage in [`3p_demand.md`](./3p_demand.md).
- **CCV** → Compromisso de Compra e Venda (For Sale closing event). Captured as a sale agreement in `dw_sale_offers.dim_sale_agreement`.
- **CRECI** → Brazilian real-estate brokerage license → `dim_broker.creci` (company) / `dim_agent.creci_number` (person).
- **Navent** → external listing ecosystem; `dim_broker_products.has_opt_in_navent` flags partner opt-in.

## Tables

The authoritative model is `dw_brokers` (DAG `dags/broker_xp/dw_brokers`). All eight dims carry `has_3p_access_control = TRUE` (row-level access governance for 3P data).

| You need... | Use this table |
|-------------|----------------|
| Current snapshot of a partner imobiliária (name, address, CRECI, CNPJ, activity flags, current Account Manager, active-people counts, last membership timestamps) | `dw_brokers.dim_broker` — PK `sk_broker`. Source for `is_3p_active_*`, `qt_active_agents`, `qt_active_agents_in_lead_gen`, `qt_active_broker_admins`, `has_active_agents_in_lead_gen`, `ts_last_*_membership_start/end`. |
| Products the partner is enrolled in (Rede Sale / Rede Rent), with fees, banking, tier, integrator at the current state | `dw_brokers.dim_broker_products` — PK `sk_broker_product`. One row per broker × product. Carries `business_context`, `commission`, `demand_fee`, `supply_fee`, `platform_fee`, `tier_name`, `integrator_partner`, `has_opt_in_navent`. |
| Operating regions declared by each broker product, enriched with city / state / country names | `dw_brokers.dim_broker_regions` — PK `sk_broker_region`. Bridge `broker_product × region`. |
| Time-line of partner activation / deactivation in the Rede (per business context when applicable) | `dw_brokers.dim_broker_status_history` — PK `sk_broker_status_history`. SCD2 with `version`, `is_current`, `ts_start`, `ts_end`. Includes `status_origin` (Hubspot or Company). |
| Time-line of Account Manager (HubSpot owner) assignment per broker | `dw_brokers.dim_broker_account_manager_history` — PK `sk_broker_account_manager_history`. SCD2 per `(sk_broker, sk_person_account_manager)`. |
| Time-line of people linked to the broker (3P agents and broker admins), with role and active period | `dw_brokers.dim_broker_profile_history` — PK `sk_broker_profile_history`. SCD2 per `(sk_person, profile)`. Flags `is_agent`, `is_broker_admin`, `is_active_profile`. |
| Time-line of commercial tier (program) per broker product | `dw_brokers.dim_broker_tier_history` — PK `sk_broker_tier_history`. SCD2 per `sk_broker_product`. |
| Time-line of integrator partner per broker product | `dw_brokers.dim_broker_integrator_partner_history` — PK `sk_broker_integrator_partner_history`. SCD2 per `sk_broker_product`. |
| 3P supply funnel (BSP → first listing) for partner-submitted properties | `dw_3p_supply.fact_lead_3p_flows` + `dw_3p_supply.dim_current_conversion_funnel` — full coverage in [`3p_supply.md`](./3p_supply.md). |
| 3P agents (corretores da Rede) — current snapshot | `dw_public.dim_agent` filtered by `is_3p_agent = TRUE` / `agent_type = 'CORRETOR_REDE'`. |
| 3P agents — historical revisions (SCD2) | `dw_agent.dim_agent_3p_history`. |
| Buyer prospect (For Sale 3P demand) NBP/RBP windows | `dw_sale.dim_buyer_prospect_3p_history`. Full demand-side coverage in [`3p_demand.md`](./3p_demand.md). |

**Critical rules:**
- **Sentinel `-1` for missing surrogate keys** in this domain (`sk_broker`, `sk_broker_product`, `sk_person_account_manager`, `sk_person`, etc.). Filter `<> -1` when you need real matches; never `COUNT` them as entities.
- **"Active now" — prefer the flags on `dim_broker` / `dim_broker_products`** (`is_3p_active_broker`, `is_3p_active_sale_broker`, `is_3p_active_rent_broker`) over reconstructing from `dim_broker_status_history`. These flags reflect product-level credentialing, not the generic registry status.
- **For status time-line** (when did broker X become active/inactive), use `dim_broker_status_history` with `is_current = TRUE` for the current row or `ts_start`/`ts_end` for arbitrary points. The same pattern applies to `account_manager`, `profile`, `tier`, and `integrator_partner` history tables.
- **Isolate Sale vs Rent** with `business_context = 'SALE'` / `'RENT'` on `dim_broker_products`, `dim_broker_regions`, `dim_broker_status_history`. The other history tables (account_manager, profile, tier, integrator_partner) are not scoped by business context — drop the filter when joining them.
- **`broker_status` on `dim_broker` / `dim_broker_status_history`** reflects the partner's status in the **Rede** (per product enrollment), not the generic Company registry status. The legacy `company_status` (deprecated) does not match this semantics.
- **`dim_broker` has no `company_name` column.** Use `broker_name` (legal name) or `broker_trade_name` (trade name). The legacy `dim_company_3p_partners.company_name` maps to `broker_name`.

### `dim_broker` — attribute groups

Current snapshot of the partner imobiliária (PK `sk_broker`). Sourced from `core_brokers.brokers`, enriched with the current HubSpot owner (mapped to a `sk_person`), active-people counts from `core_brokers.brokers_profile`, passive lead-gen agent counts from `datalake_ebdb_clean.agent_data`, and last membership transition timestamps from `datalake_brokers.broker_status_history`.

- **Identification** — `broker_name` (legal name) and `broker_trade_name` (trade name). Each has a normalised twin (`broker_name_tag` / `broker_trade_name_tag`) with accents and whitespace stripped (case preserved) — use them for **fuzzy match** against partner names coming from other sources (HubSpot, agent_data, listings). `broker_status` is the partner status in the Rede (not the generic Company registry status).
- **Credentials** — `creci` (Brazilian real-estate brokerage license, when reported) and `cnpj` (Brazilian company taxpayer id).
- **Address (6 fields)** — `broker_address`, `broker_number`, `broker_complement`, `broker_city`, `broker_state`, `broker_country`, `broker_zip_code`. This is the **headquarters address** declared in Magic Link. For **operating regions** of the broker (where it actually transacts), use `dim_broker_regions` instead — they often differ from headquarters.
- **Activity flags — registered vs active (2×3 matrix)** — three rows × two columns:
  - Rows = modality scope: overall (`*_broker`), Sale (`*_sale_broker`), Rent (`*_rent_broker`).
  - Columns = lifecycle stage: `is_3p_{rent|sale}_broker` ("ever registered for this modality") vs `is_3p_active_{rent|sale}_broker` ("currently credentialed for this modality"). The overall pair is `is_3p_rent_broker` / `is_3p_sale_broker` (any registration) vs `is_3p_active_broker` (at least one active product). A partner can be **registered but not active** (registered the product, never completed the activation flow), so always pick the **active** flags when you want operational filtering.
- **Aggregate people counts (snapshot)** — `qt_active_agents` (active `third_party_agent` profiles), `qt_active_agents_in_lead_gen` (active 3P agents flagged `is_passive_lead_receiver` in `agent_data` — i.e. Lead Gen-eligible), `qt_active_broker_admins` (active `company_admin` profiles). `has_active_agents_in_lead_gen` is the boolean derivation (`qt_active_agents_in_lead_gen > 0`). These are **not** split by `business_context` — use `dim_broker_profile_history` if you need that split.
- **Account Manager (snapshot)** — `sk_person_account_manager` is the current HubSpot owner mapped to `sk_person`; `-1` when there is no owner or the mapping fails. Full timeline in `dim_broker_account_manager_history`.
- **Lifecycle timestamps** — `ts_broker_created` / `ts_broker_updated` (registry create/update in Magic Link → core brokers), `ts_last_membership_start` / `ts_last_membership_end` (latest `ACTIVE` / latest current-`INACTIVE` in the status history, any product lane), plus per-product variants `ts_last_{rent|sale}_membership_start/end` (filtered to Rede Rent / Rede Sale).

### `dim_broker_products` — product, fees, banking

One row per broker × product (PK `sk_broker_product`). Sourced from `core_brokers.brokers_product`. Holds the **current state** of the product enrollment.

- **Product identity** — `sk_broker_product`, `sk_broker`, `product_name` (`Rede Sale`, `Rede Rent`, …), `business_context` (`SALE` / `RENT`), `business_segment` (broader classification from core, **distinct from `business_context`**), `product_status` (raw status from core; distinct from the activity flags below).
- **Fee structure (all rounded to 5 decimals)** — `commission` (commission rate paid to the partner), `demand_fee`, `supply_fee`, `platform_fee`. These are the **negotiated rates** stored on the product enrollment.
- **Banking (payout settlement)** — `bank`, `agency_number`, `account_number`, `account_type`. Used by downstream payout systems; treat as PII / sensitive when surfacing.
- **Tier and integrator (snapshot)** — `tier_name` (commercial tier / program) and `integrator_partner` (external CRM/integration provider, when applicable) hold the **current** values. For historical timelines use `dim_broker_tier_history` and `dim_broker_integrator_partner_history`. `integrator_partner_status` is the **status of the integration relationship**, distinct from `product_status`.
- **Activity flags (2×3 matrix mirrored at the product grain)** — same shape as on `dim_broker`: `is_3p_{rent|sale}_broker` vs `is_3p_active_{rent|sale}_broker` plus the overall `is_3p_active_broker`. When you have already filtered to a specific product (e.g. `business_context = 'SALE'`), the product-level active flag (`is_3p_active_sale_broker`) is functionally equivalent to filtering by `product_status` for the matched product.
- **Navent opt-in** — `has_opt_in_navent` (partner has opted into the Navent listing ecosystem).
- **Lifecycle timestamps** — `ts_product_created` / `ts_product_updated`.

### `dim_broker_regions` — geographic hierarchy

Bridge dimension between **broker products and their declared operating regions** (PK `sk_broker_region`). Sourced from the comma-separated `core_brokers.brokers_product.region_list`, exploded into one row per token, then joined to `core_region.region` for enrichment.

- **Grain** — 1 row per `(broker_product × region_token)`. Source `region_list` is `EXPLODE(SPLIT(region_list, ','))` and `sk_broker_region = CONCAT_WS(0, sk_broker_product, sk_region)`. Because the grain is at the **product**, the same broker can appear for the same region across Sale and Rent — always carry `business_context` in queries.
- **Region hierarchy** — `level` distinguishes the granularity of the region token: `Cidade`, `MacroRegiao`, `SubRegiao`. **A broker can declare regions at multiple levels simultaneously** (e.g. one product carries both a `Cidade` row for São Paulo and a `SubRegiao` row for "Zona Oeste SP"). When counting distinct brokers per state, filter to a single level (typically `level = 'Cidade'`) to avoid fanout double-counting.
- **Greater region grouping** — `greater_region` is the cross-region grouping label from the Region core model (e.g. "Grande SP", "Grande RJ"), useful for analyses that need to roll up multiple cities/sub-regions into the metropolitan area.
- **Geo enrichment** — `region_name`, `city_region_name`, `state_name`, `state_abbreviation`, `country_name`, `country_default_timezone`. Always available when the token resolves against `core_region.region` (rare misses produce `null` enrichment, in which case rely on `sk_region` alone).
- **Business context propagation** — `business_context` is propagated from the parent `dim_broker_products` row, so filtering Sale-only / Rent-only is direct on this dim without joining back to products.

### History dims — uniform SCD2 shape

The five history dims share an **identical mechanical pattern** — only the dimension being tracked changes:

| Dim | Tracks changes in | Grain (versioned by) | Origin column |
|---|---|---|---|
| `dim_broker_status_history` | `broker_status` (`ACTIVE` / `INACTIVE`) per `(broker, business_context)` | `(sk_broker, business_context)` | `status_origin` (`Hubspot` or `Company`) |
| `dim_broker_account_manager_history` | `sk_person_account_manager` (HubSpot owner) per broker | `(sk_broker)` — not split by `business_context` | — |
| `dim_broker_profile_history` | `profile_status` of each `(person, profile)` link to the broker | `(uuid_person, profile)` — not split by `business_context` | — |
| `dim_broker_tier_history` | `id_tier` / `tier_name` per broker product | `(sk_broker_product)` | — |
| `dim_broker_integrator_partner_history` | `uuid_integrator_partner` / `integrator_partner` per broker product | `(sk_broker_product)` | — |

All five carry the same columns for the SCD2 mechanics: `sk_*_history` (PK), `version` (sequential within the grain, ordered by transaction timestamp), `is_current` (TRUE for the latest revision), `ts_start` (when the revision became effective), `ts_end` (start of the next revision; `NULL` for the current row), `has_3p_access_control = TRUE`, `ts_load`. When querying:

- For **"what is true today"** → filter `is_current = TRUE` (or equivalently `ts_end IS NULL`).
- For **"what was true at moment T"** → filter `ts_start <= T AND (ts_end IS NULL OR ts_end > T)`.
- For **"how many transitions in period P"** → count rows where `ts_start` falls inside P (excluding the synthetic initial row when applicable).

`status_origin` on `dim_broker_status_history` is the **only origin column** in the set — it tracks whether the status transition came from the HubSpot pipeline (`Hubspot`) or the Company / Magic Link path (`Company`). The other four history dims have a single source by construction.

## Agents 3P (Corretores da Rede)

3P agents are the autonomous brokers that operate under an imobiliária in the Marketplace. An agent becomes 3P when registered in Magic Link with the `third_party_agent` profile (`dim_broker_profile_history.profile`), which propagates into the Agents data model.

**Identification flags (any of these confirms 3P):**
- `dim_agent.agent_type = 'CORRETOR_REDE'` (or `agent_type_main = 'CORRETOR_REDE'`).
- `dim_agent.is_3p_agent = TRUE` (derived from `agent_type`).
- `dim_agent_3p_history.is_3p_agent = TRUE` (always true in this dim — the table only contains 3P agents).
- `dim_agent.has_3p_member_profile_active = TRUE` (the person has an active `third_party_agent` profile in `brokers_profile`).

**Lead Gen eligibility** — a 3P agent enabled to receive passive leads (i.e. operate in the **3P Lead Gen** model) has `is_passive_lead_receiver = TRUE` (on both `dim_agent` and `dim_agent_3p_history`). Aggregated at the broker level, this materialises as `dim_broker.has_active_agents_in_lead_gen = TRUE` and `dim_broker.qt_active_agents_in_lead_gen > 0`.

**1P ↔ 3P transitions.** An agent can switch between 1P and 3P over time, but **never coexists in both states**. The current state is on `dim_agent`; the historical timeline (SCD2) is on `dim_agent_3p_history` — when the agent leaves 3P, the latest revision is closed (`ts_ended IS NOT NULL`, `is_current = FALSE`) and they may re-appear in 1P agents only.

**JOIN paths.**
- Broker → agents: `dim_broker.sk_broker = dim_agent.sk_broker` (filter `<> -1`).
- Broker → 3P agent history: `dim_broker.sk_broker = dim_agent_3p_history.sk_broker`.
- People linked at the broker registry (independent of the Agent model): `dim_broker.sk_broker = dim_broker_profile_history.sk_broker`.

The Agents domain itself (full coverage of `dw_public.dim_agent` beyond 3P) is out of scope for this entity doc — a dedicated Agents entity doc may be created later.

### `dim_agent` — attribute groups

Current snapshot of every agent (`dw_public.dim_agent`, PK `sk_agent`). Contains **all agents** (1P and 3P) — filter to 3P with `is_3p_agent = TRUE` or `agent_type = 'CORRETOR_REDE'`.

- **Identification** — `sk_agent`, `id_user`, `agent_code`, `creci_number` (CRECI of the natural person, distinct from `dim_broker.creci` of the company), `agent_profile` (operational profile such as `CAR_LONG_DISTANCE` / `BUS_LONG_DISTANCE` — describes how the agent operates, not the 3P/1P split), `agent_type` (**concatenated** list of agent types — an agent can be multi-type: e.g. `visit, inspection, photo session`), `agent_type_main` (primary classification, single value), `contract_name`.
- **Modality flags (orthogonal to 3P)** — `is_rent_agent` / `is_sale_agent` mark whether the agent operates on rentals / sales. They are independent of the 3P split: a 3P agent can be Sale-only, Rent-only, or both.
- **States** — `is_agent_active` (registry-level), `is_user_active` (associated user), `is_blocked` (user blocked), `is_service_link_active` (service link currently active). Use the **conjunction** of these when filtering "currently operational" — the registry can be active while the user is blocked, and vice-versa.
- **3P-specific flags** — `is_3p_agent` (`agent_type = 'CORRETOR_REDE'`), `is_passive_lead_receiver` (Lead Gen-eligible), `has_3p_member_profile_active` (canonical "active 3P agent now": ACTIVE `third_party_agent` `brokers_profile` row for the broker), `has_3p_member_profile_pending` (TRUE when the profile row is in `PENDING CONFIRMATION` or `PENDING INVITATION` — i.e. the agent is mid-onboarding).
- **Other modalities** — `is_affiliate_active`, `is_photographer_active`, `is_tenant` — orthogonal to 3P, useful for cross-role analyses.
- **Cross-domain bridges** — `sk_person`, `sk_user`, `sk_company` (legacy — prefer `sk_broker`), `sk_broker` (the 3P broker the agent operates under, matched by company UUID; `-1` when no broker row exists).
- **Lifecycle** — `ts_created`, `ts_updated`.

### `dim_agent_3p_history` — SCD2 mechanics

History of every 3P agent (`dw_agent.dim_agent_3p_history`). The table is **3P-only by construction** (`is_3p_agent = TRUE` on every row, `agent_type = 'CORRETOR_REDE'`).

- **Grain of uniqueness** — `(sk_agent, version)`, **not** `sk_agent_3p_history` alone. `sk_agent_3p_history = COALESCE(id_agent, 0, version)` and collapses to `id_agent` grain in practice; always pair with `version` when you need row-level uniqueness.
- **Per-revision flags** — `is_active` (whether the agent was active **as of this revision**), `is_passive_lead_receiver` (Lead Gen-eligible as of this revision), `is_deleted` (TRUE when the source operation was a delete), `is_current` (latest revision per agent).
- **Time interval** — `ts_started` (when this revision became effective), `ts_ended` (when superseded; `NULL` for the current revision).
- **Cross-domain bridges** — `sk_agent` (FK to `dim_agent`), `sk_user`, `sk_broker` (the 3P broker for this revision), `contract_name`.
- **Critical pattern — temporal overlap.** To answer "was agent X active 3P at moment T?" use `ts_started <= T AND (ts_ended IS NULL OR ts_ended > T) AND is_active = TRUE`. The same pattern extends to monthly buckets (see B.5 below).

### `dim_agent_region` — daily region allocation

Daily snapshot of which **macro-region codes** each agent is allocated to (`dw_public.dim_agent_region`). Sourced from `datalake_agenda_allocation.agent_region_group`.

- **Grain** — 1 row per `(sk_agent, day)`; the date is carried in `sk_regions_date`. The same agent can appear on consecutive days with different allocations.
- **Region columns** — `area` is the primary `region_code` (operations codes such as `SPO 02`, `RIO 01`, `BHZ 03`); `secondary_area` is the secondary `region_code` when the agent's coverage spans multiple operational codes; `regions` is the **comma-separated list of `sk_region`** the agent is allocated to (bridge into `dim_region` for full geo). The deprecated counterparts (`area_deprecated`, `secondary_area_deprecated`) hold the legacy `region_code_deprecated` values and should only be used for backfills.
- **Caveat — not 3P-specific.** This dimension covers **all agents** (1P and 3P). To restrict to 3P, JOIN to `dim_agent` (`sk_agent`) and filter `is_3p_agent = TRUE`, or to `dim_agent_3p_history` for the historical 3P state at the same date.

### `fact_visit_agent_performance` — daily agent performance summary

Daily aggregated performance per agent (`dw_agent.fact_visit_agent_performance`, PK `sk_agent_performance`). Sourced from `datalake_visit_agent_performance.agent_performance_daily_summary`.

- **Grain** — 1 row per `(sk_agent, dt_reference)`. Partitioned by `year` / `month` / `day` derived from `dt_reference`.
- **No `sk_broker` / `is_3p_agent` directly.** Bridge to 3P via `dim_agent` (`sk_agent → dim_agent.is_3p_agent`); bridge to the partner imobiliária via `dim_agent.sk_broker → dim_broker`. For historically-correct 3P attribution (e.g. agent moved between brokers), bridge via `dim_agent_3p_history` joining on `sk_agent` with `dt_reference` overlap on `(ts_started, ts_ended)`.
- **Region context** — `major_region_code` (agent's primary macro region, single value per row).
- **Modality context** — `is_rent_agent` / `is_sale_agent` (derived from business context on the source).
- **Schedule metrics** — `total_active_days`, `total_active_days_in_current_context`, `total_hours_available_by_contract`, `total_hours_allocation_available_by_schedule`. Note: `total_active_days` is **cumulative since the agent started**, not "active days on `dt_reference`".
- **Visit funnel** — `total_visit_booked`, `total_visit_booking_by_agent` (booked directly by the agent, not by the lead), `total_visit_completed`, `total_booking_stalled` (in limbo — neither confirmed nor canceled), `total_booking_cancellation_by_agent`, `total_visit_cancellation_by_agent`, `total_booking_no_show_by_agent`.
- **Offer-to-contract funnel** — `total_offer_submitted`, `total_offer_approved`, `total_document_sent`, `total_credit_approved`, `total_contract_signed`, `total_proposal_evaluation_started`.
- **Lead-to-stage metrics** — `total_leads` (distinct leads that interacted with the agent), `total_leads_with_three_or_more_confirmed_visits`, plus 8 `total_lead_to_*` columns mirroring each funnel stage (booking, booking-by-agent, completed, offer submitted/approved, doc sent, credit approved, contract signed, proposal evaluation started).
- **Cohort** — `total_leads_to_contract_signed_cohort_7_days` (leads that signed a contract within 7 days of the first visit booking).
- **Supply hint** — `total_supply_first_listing` (first listings the agent added — useful to cross with `3p_supply.md` agent-level analyses).
- **Performance availability flags** — `has_schedule_performance`, `has_offer_performance`, `has_lead_performance` — filter to TRUE before averaging the corresponding blocks to avoid diluting medians with rows that simply have no data.

### Canonical pattern — "active 3P agents per month"

The right source is `dim_agent_3p_history` (the SCD2 dim), **not** the snapshot count on `dim_broker.qt_active_agents` (which only reflects "now"). The default definition uses the **any-overlap** rule:

> An agent counts as active in month M if at least one revision of `dim_agent_3p_history` has `is_active = TRUE` and overlaps M, i.e. `ts_started <= EOM(M) AND (ts_ended IS NULL OR ts_ended > BOM(M))`.

In Trino, generate the monthly spine with `UNNEST(SEQUENCE(date 'YYYY-MM-01', current_date, INTERVAL '1' MONTH))` and join the spine to the history table on the overlap predicate. Count `DISTINCT sk_agent` per month. Add splits as needed:
- `is_passive_lead_receiver = TRUE` (per revision) for **Lead Gen-eligible** sub-population.
- `sk_broker` (per revision) for **per-imobiliária** breakdown.
- Bridge to `dim_agent.is_rent_agent` / `is_sale_agent` for **modality** breakdowns (modality is on `dim_agent` only, not on the history table).

A fully worked SQL example is in **Query 11** below. The alternative "active at end-of-month" definition (`ts_ended IS NULL OR ts_ended > EOM`) is stricter and excludes agents who left mid-month — use it when you need a strict point-in-time headcount instead of an "any time during the month" metric.

## Business Model on transactional records (Visits / Offers / Buyer Prospects)

The `business_model` field is the **routing key for identifying 3P transactions** in cross-domain models. It originates in `datalake_ebdb_clean.visit_business_model.business_model`, is processed by `dags/broker_xp/enrich_business_model` (`datalake_visit.visit_business_model`), and propagates to all Visit and Offer tables. From the same enrich come the broker surrogate keys for each side of the transaction:

- `sk_broker_supply` → broker on the supply side (owns the property). Populated when `business_model LIKE '%3P_SUPPLY%'`; `-1` otherwise.
- `sk_broker_demand` → broker on the demand side (brought the buyer/tenant). Populated when `business_model LIKE '%3P_DEMAND%' OR '%3P_LEAD_GEN%'`; `-1` otherwise.

Both columns JOIN with `dw_brokers.dim_broker.sk_broker`. A single transaction can have two different brokers (e.g. a 3P Supply broker and a separate 3P Demand broker), so **never assume `sk_broker_supply = sk_broker_demand`**.

**The 8 `business_model` combinations** observed today (the matrix consumed by analysts to identify 3P operations):

| business_model | is_3p_supply | is_3p_demand | is_3p_lead_gen | sk_broker_supply | sk_broker_demand |
|---|---|---|---|---|---|
| `BM_1P` | FALSE | FALSE | FALSE | -1 | -1 |
| `BM_3P_SUPPLY_1P_DEMAND_AGENT` | TRUE | FALSE | FALSE | filled (JOIN broker) | -1 |
| `BM_3P_DEMAND_1P_SUPPLY` | FALSE | TRUE | FALSE | -1 | filled (JOIN broker) |
| `BM_3P_DEMAND_3P_SUPPLY` | TRUE | TRUE | FALSE | filled (JOIN broker) | filled (JOIN broker) |
| `BM_3P_DEMAND_3P_SUPPLY_6P` | TRUE | TRUE | FALSE | filled (JOIN broker) | filled (JOIN broker) |
| `BM_3P_LEAD_GEN_1P_SUPPLY` | FALSE | FALSE | TRUE | -1 | filled (JOIN broker) |
| `BM_3P_LEAD_GEN_3P_SUPPLY` | TRUE | FALSE | TRUE | filled (JOIN broker) | filled (JOIN broker) |
| `BM_3P_LEAD_GEN_3P_SUPPLY_6P` | TRUE | FALSE | TRUE | filled (JOIN broker) | filled (JOIN broker) |

**How to identify 3P in queries:**
- For modality-agnostic 3P filtering, prefer the boolean flags (`is_3p_supply`, `is_3p_demand`, `is_3p_lead_gen`) — they encode the matrix above, so you don't need to enumerate `business_model` values.
- For modality-specific aggregations (e.g. "3P transactions where partner brought the buyer"), use the specific flag — `is_3p_demand` for Demand, `is_3p_lead_gen` for Lead Gen, `is_3p_supply` for Supply.
- For broker-level analysis, decide upfront whether you care about the **supply side** (`sk_broker_supply`) or **demand side** (`sk_broker_demand`) — they answer different business questions.

Detailed demand-side funnel (Visit → Offer → CCV), sub-stages, bridges, reasons / drop reasons, and NBP / RBP modelling are in [`3p_demand.md`](./3p_demand.md).

## Identifying 3P records in other entities

`sk_broker` and the `is_3p_*` flags propagate selectively across the warehouse. Use the table below to pick the right routing for each domain:

| Domain | Table | Filter / JOIN pattern |
|---|---|---|
| 3P supply funnel (lead → first listing) | `dw_3p_supply.fact_lead_3p_flows` | `sk_broker <> -1`; full coverage in [`3p_supply.md`](./3p_supply.md) |
| Supply (unified funnel across 1P / 3P / CIQ) | `dw_growth.obt_supply` | `acquisition_origin = 'rede'` (or `nm_supply_source = '3P'`) |
| Houses — information filling fact | `dw_house.fact_house_information_filling` | `sk_broker <> -1` (3P broker partner mapped from `sk_company`) |
| Listings (For Sale) — fact | `dw_sale_listings.fact_listings`, `dw_sale_listings.fact_listing_status` | `sk_broker <> -1` |
| Listings (For Sale) — dim | `dw_sale_listings.dim_listing` | `is_3p_supply = TRUE` (no `sk_broker` on this dim — bridge via `sk_house` to fact tables when broker-level analysis is required) |
| Listings (For Sale) — daily snapshot of published listings + demand | `dw_sale.fact_daily_ongoing_listing` | No `sk_broker` / `is_3p_*` — bridge `sk_house` to `dim_listing.is_3p_supply` or `fact_listings.sk_broker`; only counts events while listing is `PUBLISHED` |
| Search & LPV events (visibility / top of demand funnel) | `dw_public.fact_search_session_event` + `dw_public.dim_search_session_event_type` | No `sk_broker` / `is_3p_*` — bridge `sk_house` to `dim_listing.is_3p_supply` or `fact_listings.sk_broker`; split SSR vs Client Search via `search_rendering_type` |
| Listings (For Rent) — dim | `dw_listing.dim_house_listing` | `is_3p_supply = TRUE` (no `sk_broker` on this dim — bridge via `sk_house`) |
| Visits (For Sale) | `dw_sale_visits.fact_visits` | `is_3p_supply` / `is_3p_demand` / `is_3p_lead_gen`; broker via `sk_broker_supply` / `sk_broker_demand <> -1` |
| Visits (combined Sale + Rent) | `dw_visit.fact_visits` (`is_3p_*` flags planned to move to `dim_visit`), `dw_visit.dim_visit` (`is_visit_3p_*` flags + `business_model`) | Same pattern as above; for For Sale prefer `dw_sale_visits` |
| Offers / CCV (For Sale) | `dw_sale_offers.fact_offers`, `dw_sale_offers.dim_offer`, `dw_sale_offers.dim_sale_agreement` | `is_3p_supply` / `is_3p_demand` / `is_3p_lead_gen`; broker via `sk_broker_supply` / `sk_broker_demand <> -1` |
| Buyer Prospects (For Sale, NBP/RBP) | `dw_sale.dim_buyer_prospect_3p_history` | Table is 3P-only by construction; `sk_broker` refers to the **demand-side** broker; `demand_type IN ('3P_DEMAND', '3P_LEAD_GEN')` |
| Visit business model source | `datalake_visit.visit_business_model` (enrich) | Source of `business_model`, `sk_broker_supply`, `sk_broker_demand`, `is_3p_*` flags propagated downstream |
| Agents — current snapshot | `dw_public.dim_agent` | `is_3p_agent = TRUE` / `agent_type = 'CORRETOR_REDE'`; broker via `sk_broker <> -1` |
| Agents — history | `dw_agent.dim_agent_3p_history` | Table is 3P-only by construction; broker via `sk_broker` |

**Caveats:**
- For Sale: prefer `dw_sale_visits` / `dw_sale_offers` / `dw_sale_listings` (Sale-specific paths) over the combined legacy paths in `dw_visit` / `dw_listing`.
- Listing dims (`dim_listing`, `dim_house_listing`) carry the `is_3p_supply` flag but **not** `sk_broker`; for broker-level Listing analysis bridge through `sk_house` to a fact that does (`dw_sale_listings.fact_listings`, `dw_house.fact_house_information_filling`).
- `fact_daily_ongoing_listing` and `fact_search_session_event` carry **neither** `sk_broker` nor the `is_3p_*` flags — both require a `sk_house` bridge to a listing dim/fact to identify the 3P scope. They are the canonical sources for, respectively, daily demand metrics of published listings and search-visibility / LPV events; see the next section for the full pattern.

## Listings — Visibility and Demand on 3P Supply

The Marketplace's supply lifecycle does not end at "listing published". Once a 3P listing is on the main system, three orthogonal warehouse views describe how the listing performs from there:

1. **Listing version and status timeline** — what the listing is and how its publication state evolves over time.
2. **Daily snapshot of published listings** — pre-aggregated demand metrics per `(house, day)` while the listing is `PUBLISHED`.
3. **Search and Listing Page Viewed events** — granular event grain capturing how the listing shows up in search results (SSR vs Client Search) and how users land on the listing page.

The first view exposes `sk_broker` directly. The other two **do not** — they require a `sk_house` bridge to `dim_listing.is_3p_supply` (3P-only filter) or `fact_listings.sk_broker` (broker-level attribution).

### Listing version and status timeline

- **`dw_sale_listings.fact_listings`** — 1 row per **listing version** (`sk_sale_listing`; version 0 = editing, version 1 = published). Joined to `sk_house` to a house's listing history. Carries `sk_broker` directly (`-1` when not 3P) plus the rich set of "days_first_publication_to_*" metrics: `_first_sale_flow`, `_first_booking`, `_visit_completed`, `_first_offer_submitted`, `_first_offer_accepted`, `_first_sale_agreement_signed`, `_house_registry_ended`. Plus pre-aggregated demand totals: `total_listings_visit_completed`, `total_listings_offer_submited`, `total_listings_offer_accepted`. Plus `days_as_published` and the publication / depublication date keys (`sk_first_publication_date`, `sk_last_publication_date`, `sk_first_depublication_date`, `sk_last_depublication_date`).
- **`dw_sale_listings.fact_listing_status`** — 1 row per **status transition** of a listing version. Carries `sk_broker`. Two categorical history columns:
  - `status_history` ∈ `EDITING`, `OPTED_OUT`, `PUBLISHED`, `SUSPENDED`, `UNPUBLISHED`.
  - `status_closing_history` ∈ `CCV_CANCELED`, `CCV_SIGNED`, `SALE_COMPLETED`.
  - Plus `status_change_reason` / `status_change_reason_detail` (free text / coded) and `is_last_status = TRUE` to snapshot the current state of each listing.

Use `fact_listings` for *outcome and timing per listing*; use `fact_listing_status` for *what state the listing is in (or was in) over time*.

### Daily snapshot of published listings — `fact_daily_ongoing_listing`

- **Grain**: 1 row per `(sk_house, sk_snapshot_date)`. **Only rows for listings whose status was `PUBLISHED` at the snapshot day** appear in the table; if the listing was unpublished on day X, that day is absent for that house.
- **Identifiers**: `sk_house`, `sk_sale_listing`, `sk_region`, **`sk_company`** (legacy — do not use as broker key), `sk_sale_price_segment`. **No `sk_broker`. No `is_3p_*` flags.**
- **Snapshot facts**: `sale_price` (price at end of day), `sk_sale_price_segment`.
- **Daily demand metrics (pre-aggregated)**:
  - Visibility: `qt_search_result_page_viewed`, `qt_listing_page_viewed`.
  - Funnel: `qt_visits_booked`, `qt_visits_completed`, `qt_offers_submitted`, `qt_offers_accepted`, `qt_sale_agreements_created`, `qt_sale_agreements_signed`.
- **How to identify 3P listings here**: bridge `sk_house → dw_sale_listings.dim_listing.is_3p_supply = TRUE` (3P flag without broker), or `sk_house → dw_sale_listings.fact_listings.sk_broker <> -1` (broker-level). The legacy `sk_company` on `fact_daily_ongoing_listing` should **not** be used as the broker identifier.
- **Truncation caveat (critical)**. The metrics in this table are **scoped to days the listing was published**. Events on unpublished days exist in the source warehouse but are absent here. The own metadata notes this explicitly: *"if you add up the metrics from this table such as visit booked or visit completed, they might not be equal to the total that actually happened. This is because some events happen when the listing is unpublished, so the rows will not appear in this table. To see all ForSale demand events, please use the table `dw_sale.fact_sale_demand_event`."*

### Search and Listing Page Viewed events — `fact_search_session_event`

The DAG lives under `dags/3p_partners/dw_search_session_event` — it is Marketplace-owned by construction, even though the resulting tables are in the `dw_public` schema (visible to all consumers).

- **Grain**: 1 row per `(house, event)`. A single SSR search that returned 30 houses produces 30 rows. Today the table covers only **two `event_type` values**: `Search` and `Listing Page Viewed`.
- **Identifiers**: `sk_event` (PK), `sk_event_type` (→ `dim_search_session_event_type`), `sk_amplitude` (anonymous user), `sk_user` (logged user → `dw_public.dim_user`), `sk_house`, `sk_house_region`, **`sk_company`** (legacy — do not use as broker key), `sk_session`, `sk_search`, `sk_event_date`, `nr_session_for_user_on_day`, `ts_event`.
- **Session semantics**. A `sk_session` opens after 5 minutes of inactivity or a change in `business_context`. `sk_search` identifies the search query that produced the event (generated by Amplitude).
- **How to identify 3P listings here**: bridge `sk_house → dw_sale_listings.dim_listing.is_3p_supply = TRUE` (3P-only) or `sk_house → dw_sale_listings.fact_listings.sk_broker <> -1` (broker-level). As in `fact_daily_ongoing_listing`, `sk_company` is the legacy key — not the broker identifier.
- **`dim_search_session_event_type`** — every row is a combination of: `event_type` (`Search` / `Listing Page Viewed`), `business_context` (`sale` / `rent` / `unknown`), `search_rendering_type`, `search_location_type` (`city` / `neighborhood` / `coordinates` / `street` / `poi` / `unknown` / `N/A`), `platform`, `utm_source`, `utm_medium`, `base_referrer_url` (normalised host — strips scheme, `www.`, and path), `search_view_mode`, `search_sort_order`.

#### SSR vs Client Search — what changes for 3P analysis

`search_rendering_type` splits search events into two regimes with different implications for ranking and exposure analytics:

- **`Server-Side Rendering (SSR)`** — originated from `170698_search_page_viewed_events`. Happens when the user **arrives at the search page from outside** (homepage, Google, direct link, push). The server returns the **first 11 results** and the **pclick (ranking ML model) has no effect** — these results follow the server-default ordering. Use SSR for:
  - *Organic / entrypoint exposure* analyses (how often a 3P listing appears as part of the top-11 default).
  - *Pure share-of-visibility* per neighbourhood / region (no ranking bias).
  - **Do not** use SSR to evaluate ranking-model performance — pclick is bypassed by construction.
- **`Client Search`** — originated from `170698_search_results_page_viewed_events`. Happens when the user **interacts with the search page** (moves the map, applies a filter, changes the searched location / neighbourhood, switches sort, paginates). The pclick **does act** on the ordering. Use Client Search for:
  - Ranking-model performance (CTR-per-position, A/B testing of ranking features).
  - Conversion-by-rank analyses, listing-quality vs ranking diagnostics.
  - 1P-vs-3P exposure under the active ranking regime.

For 3P-specific analyses, the two regimes answer different business questions:
- *"Is the ranking model favouring or hurting 3P listings?"* → split by `search_rendering_type = 'Client Search'`.
- *"Are 3P listings appearing as much as 1P in default (post-link / google-arrival) exposure?"* → use `Server-Side Rendering (SSR)`.

Mixing the two without splitting hides which effect (server default vs ranking) is driving any divergence between 1P and 3P visibility.

#### Pitfalls specific to `fact_search_session_event`

- **Fanout on Search events** — a single SSR search returns ~11 houses → 11 rows. `COUNT(*) WHERE event_type = 'Search'` counts house-impressions, not searches. For "how many searches happened" use `COUNT(DISTINCT sk_search)` or `COUNT(DISTINCT sk_session)`.
- **`sk_user` vs `sk_amplitude`** — `sk_user` is populated only for logged users; anonymous traffic is keyed solely by `sk_amplitude`. For "distinct visitors" pick one based on the analysis scope.
- **`business_context = 'unknown'`** is a real category, not data quality — events where the user had not yet picked a modality. Decide upfront whether to include or filter it.

## Key Metrics

- **Active 3P brokers** — `COUNT(DISTINCT sk_broker) WHERE is_3p_active_broker = TRUE` on `dim_broker`. Per modality: `is_3p_active_sale_broker` / `is_3p_active_rent_broker`.
- **Active 3P agents per broker** — `dim_broker.qt_active_agents` (no business-context split on this column).
- **Active broker admins per broker** — `dim_broker.qt_active_broker_admins`.
- **Lead-Gen-enabled brokers** — `COUNT(DISTINCT sk_broker) WHERE has_active_agents_in_lead_gen = TRUE` on `dim_broker`; underlying volume of agents in `qt_active_agents_in_lead_gen`.
- **Tier distribution** — `COUNT(*) GROUP BY tier_name` on `dim_broker_products` (current state) or on `dim_broker_tier_history` with `is_current = TRUE`.
- **Time since last activation** — `DATE_DIFF('day', CAST(ts_last_membership_start AS DATE), CURRENT_DATE)` on `dim_broker`; per modality use `ts_last_sale_membership_start` / `ts_last_rent_membership_start`.
- **3P supply volume per broker** — JOIN `dim_broker` ↔ `dw_3p_supply.fact_lead_3p_flows` on `sk_broker`. For funnel-stage breakdown (Opportunity, First Listing, etc.) follow [`3p_supply.md`](./3p_supply.md).
- **3P transactions per broker (Visits / Offers)** — `COUNT(*) WHERE is_3p_supply OR is_3p_demand OR is_3p_lead_gen` on `dw_sale_visits.fact_visits` / `dw_sale_offers.fact_offers`, grouped by `sk_broker_supply` or `sk_broker_demand` as required.
- **L2FL** and other supply-funnel conversion metrics: see [`3p_supply.md`](./3p_supply.md) — not duplicated here.

## Relationships with Other Entities

### 3P Supply (1:N — one broker has many leads/listings in the supply funnel)

- `dim_broker.sk_broker = dw_3p_supply.fact_lead_3p_flows.sk_broker` (filter `<> -1` on both).
- Full coverage of BSP, conversion funnel, opportunities, L2FL: [`3p_supply.md`](./3p_supply.md).

### Supply — unified funnel (1:N)

- `dim_broker.sk_broker = dw_3p_supply.fact_lead_3p_flows.sk_broker`, then bridge to `dw_growth.obt_supply` via `sk_house` (filter `acquisition_origin = 'rede'`).

### Houses (1:N)

- `dim_broker.sk_broker = dw_house.fact_house_information_filling.sk_broker` (filter `<> -1`).
- `dw_house.dim_house` does **not** carry `sk_broker` or `is_3p_supply` — use the fact above or bridge through `dw_3p_supply.fact_lead_3p_flows.sk_house`.

### Listings — For Sale (1:N)

- `dim_broker.sk_broker = dw_sale_listings.fact_listings.sk_broker` / `dw_sale_listings.fact_listing_status.sk_broker` (filter `<> -1`).
- For Sale **dim** (`dim_listing`) has `is_3p_supply` only — bridge through `sk_house` to a fact when broker key is needed.

### Listings — For Rent (1:N)

- `dw_listing.dim_house_listing.is_3p_supply = TRUE` identifies 3P, but the dim has no `sk_broker`. Bridge via `sk_house` to `dw_house.fact_house_information_filling`.

### Daily Ongoing Listings — For Sale (1:N per day, only-while-published)

- `dim_broker.sk_broker = dw_sale_listings.fact_listings.sk_broker`, then bridge to `dw_sale.fact_daily_ongoing_listing` via `sk_house`. Alternative 3P-only filter (no broker key required): bridge `sk_house` to `dw_sale_listings.dim_listing.is_3p_supply = TRUE`.
- The table is the canonical source for pre-aggregated daily demand metrics (search results, LPV, bookings, visits, offers, CCVs) for 3P listings.
- **Truncation caveat** (also in the "Listings — Visibility and Demand on 3P Supply" section): the metrics count only the days the listing was `PUBLISHED`. For unconditional totals route to `dw_sale.fact_sale_demand_event` or the stage-specific facts (`fact_visits`, `fact_offers`).

### Search and LPV Events (N:N per house × event, with fanout on Search)

- Bridge `dw_public.fact_search_session_event.sk_house = dw_sale_listings.dim_listing.sk_house`, then filter `dim_listing.is_3p_supply = TRUE` for 3P-only; alternatively bridge to `dw_sale_listings.fact_listings.sk_broker <> -1` to attribute per broker.
- JOIN `dw_public.dim_search_session_event_type` on `sk_event_type` to split events by `event_type` (`Search` / `Listing Page Viewed`), `search_rendering_type` (SSR / Client Search), `business_context`, `search_location_type`, `platform`, and UTM / referrer.
- **Fanout warning**: 1 row per house in each search event; SSR searches return ~11 houses each. Use `COUNT(DISTINCT sk_search)` or `COUNT(DISTINCT sk_session)` for "distinct searches / sessions" rather than `COUNT(*)`.
- For the SSR vs Client Search distinction and its impact on ranking-vs-exposure analytics, see the "Listings — Visibility and Demand on 3P Supply" section.

### Recs (N:N via listing visibility and downstream demand)

- Recommendation exposures live in `datalake_search.recs_impressions_processed` and can be connected by house grain to listing visibility analyses in this entity (`sk_house` on Marketplace/search-side tables).
- Use the recs entity doc for recommendation-specific routing, attribution windows, and metric-table usage: [`recs.md`](./recs.md).
- When comparing recs visibility against search visibility, keep grain explicit: recs is impression-level by recset/listing, while search tables fan out by search result events.

### Visits (1:N — two paths: supply broker and demand broker)

- `dim_broker.sk_broker = dw_sale_visits.fact_visits.sk_broker_supply` or `... = .sk_broker_demand` (filter `<> -1`).
- For the modality-combined legacy path use `dw_visit.fact_visits` / `dw_visit.dim_visit` (note: the `is_3p_*` flags on `dw_visit.fact_visits` will be moved to `dw_visit.dim_visit`; both locations work today, but new analyses should target the dim path).
- Full demand-side coverage in [`3p_demand.md`](./3p_demand.md).

### Offers and CCV — For Sale (1:N — two paths)

- `dim_broker.sk_broker = dw_sale_offers.fact_offers.sk_broker_supply` or `... = .sk_broker_demand` (filter `<> -1`).
- Sale agreement (CCV) attributes on `dw_sale_offers.dim_sale_agreement` (`is_3p_supply`, `is_3p_demand`, `is_3p_lead_gen`, `business_model`).

### Buyer Prospects — For Sale (1:N)

- `dim_broker.sk_broker = dw_sale.dim_buyer_prospect_3p_history.sk_broker` (demand-side broker by construction).
- Use `demand_type` to split `3P_DEMAND` vs `3P_LEAD_GEN` flow; `version` / `is_current` for SCD2 navigation.

### Agents (1:N — one broker has many 3P agents)

- `dim_broker.sk_broker = dw_public.dim_agent.sk_broker` (filter `<> -1`, and `is_3p_agent = TRUE` to keep 3P only).
- `dim_broker.sk_broker = dw_agent.dim_agent_3p_history.sk_broker` (table is 3P-only by construction).
- People view from the broker registry: `dim_broker_profile_history` (`profile = 'third_party_agent'`); this is the canonical source for "people linked to the broker", while `dim_agent_*` is the Agents-domain mirror.

### Person — Account Manager (N:1)

- `dim_broker.sk_person_account_manager` → Person dimension. Full history on `dim_broker_account_manager_history` (filter `is_current = TRUE` for the active assignment).

### Region (N:N per product)

- `dim_broker_regions` is the bridge: one row per `(broker_product, region)` token from the partner's declared `region_list`. JOIN to a region dimension via `sk_region`.

## Dos and Don'ts

**Do:**
- Always filter `sk_broker <> -1` when listing or counting real partner imobiliárias.
- For "active now" questions, prefer `dim_broker.is_3p_active_broker` (or `is_3p_active_sale_broker` / `is_3p_active_rent_broker`) over reconstructing from history tables — these flags reflect product-level credentialing.
- Use `dim_broker_status_history` (with `is_current = TRUE` or explicit `ts_start`/`ts_end`) for time-line questions — when did broker X become active, how long has it been active, etc. Same SCD2 pattern for `account_manager`, `profile`, `tier`, `integrator_partner` history tables.
- Filter `business_context = 'SALE'` / `'RENT'` on `dim_broker_products`, `dim_broker_regions`, `dim_broker_status_history` for modality-specific analyses.
- On Visit/Offer tables, **always** filter on `business_model` or the `is_3p_*` flags to scope to Marketplace transactions. A transaction can carry two different brokers (`sk_broker_supply` vs `sk_broker_demand`) — decide upfront which side answers the business question.
- To identify 3P agents, JOIN `dim_agent` to `dim_broker` on `sk_broker` and validate `is_3p_agent = TRUE` (or `agent_type = 'CORRETOR_REDE'`).
- For the supply funnel (lead → first listing), route directly to [`3p_supply.md`](./3p_supply.md) — the metrics, recipes (L2FL, valid-lead), and pitfalls are documented there.
- For HubSpot Account Manager information, use `dim_broker.sk_person_account_manager` (current) or `dim_broker_account_manager_history` (history). This is the **only** HubSpot-derived attribute still in scope.
- For visibility and Listing-Page-Viewed analytics of 3P listings, start on `dw_public.fact_search_session_event` and bridge `sk_house` to `dw_sale_listings.dim_listing.is_3p_supply` (fast 3P filter) or `dw_sale_listings.fact_listings.sk_broker` (broker-level). Always split by `dim_search_session_event_type.search_rendering_type` — the pclick / ranking ML model acts on Client Search only.
- For pre-aggregated daily demand metrics on published 3P listings (search results, LPV, bookings, visits, offers, CCVs per day), prefer `dw_sale.fact_daily_ongoing_listing` and bridge via `sk_house` to identify 3P. It saves the manual aggregation per stage; just remember the truncation caveat (next bullet).
- For publication / unpublication / suspension / closing timelines per 3P listing, use `dw_sale_listings.fact_listing_status` — `sk_broker` is on the table, `is_last_status = TRUE` snapshots the current state, and `status_history` + `status_closing_history` give the categorical journey.

**Don't:**
- Don't use any legacy table or DAG (see de/para below). The DW migration is in progress — TARS must never suggest them.
- Don't use `sk_company` to identify imobiliárias in the Marketplace context — use `sk_broker`. `sk_company` is the legacy join key on the deprecated `dw_company` schema.
- Don't read `company_status` or any HubSpot-derived attribute (cluster, tag, member status, tier) — only `sk_person_account_manager` is still valid from HubSpot.
- Don't use `dim_broker_products.tier_name` as a historical timeline — that column reflects the **current** state. For history, use `dim_broker_tier_history`.
- Don't assume `broker_status` on `dim_broker_status_history` is the same as the legacy `company_status`. The new model reflects credentialing **per product** in the Rede, not the generic Company registry.
- Don't anchor new analyses on the `is_3p_*` flags of `dw_visit.fact_visits` — they will be moved to `dw_visit.dim_visit` (where the equivalents `is_visit_3p_supply` / `is_visit_3p_demand` / `is_visit_3p_lead_gen` already exist). The columns are not being deprecated; both locations work today, but new code should target the dim. For For Sale, `dw_sale_visits.fact_visits` is unaffected — prefer it.
- Don't assume an agent can be 1P and 3P simultaneously — they alternate over time, never coexist. Use `dim_agent_3p_history.is_current = TRUE` (or `ts_ended IS NULL`) to identify the current state.
- Don't aggregate `sk_broker_supply` and `sk_broker_demand` together in Visits/Offers without de-duplicating — the same transaction can contribute to both columns.
- Don't `COUNT(DISTINCT sk_broker_product)` on `dim_broker_regions` expecting it to match `dim_broker_products` — `dim_broker_regions` fans out one row per region in the product's `region_list`.
- Don't use the `dim_buyer_prospect_3p_history.sk_broker` as a supply-side broker — it is the **demand-side** broker by construction.
- Don't use `dw_sale.fact_daily_ongoing_listing` for absolute totals of bookings / visits / offers / CCVs — the table only counts events on days the listing was `PUBLISHED`. Events while unpublished are missing. For unconditional totals route to `dw_sale.fact_sale_demand_event` or the stage-specific facts (`fact_visits`, `fact_offers`).
- Don't `COUNT(DISTINCT sk_house)` on `dw_public.fact_search_session_event` expecting "listings searched" without modelling the fanout — a single SSR search returns ~11 houses (11+ rows). For "distinct searches" use `COUNT(DISTINCT sk_search)`; for "distinct sessions" use `COUNT(DISTINCT sk_session)`.
- Don't mix `Server-Side Rendering (SSR)` and `Client Search` events in ranking-performance analyses — the pclick / ranking ML model is bypassed by construction on SSR (server-default ordering of the first 11 results). Split by `search_rendering_type` upfront.
- Don't use `sk_company` (legacy) on either `fact_daily_ongoing_listing` or `fact_search_session_event` as the broker identifier in the Marketplace context — always bridge via `sk_house` to the listing dim/fact for the correct broker / 3P attribution.

### De/Para — legacy DAG/table → current

| Legacy | Current |
|---|---|
| `dw_company.*` / `dim_company_3p_partners` | `dw_brokers.dim_broker` (+ history dims for status / tier / account manager / profile / integrator) |
| `dw_company.dim_company` | `dw_brokers.dim_broker` |
| `enrich_company` | `enrich_brokers` |
| `enrich_hubspot_events` | `enrich_brokers` (HubSpot only flows in for Account Manager) |
| `dw_rede_supply` | `dw_3p_supply` |
| `enrich_rede_supply` | `enrich_3p_supply` |
| `enrich_brokers_supply_processor` | `enrich_3p_supply` |
| `dags/3p_partners/enrich_rede_house_history` | (removed — use `datalake_ebdb_listing.house` for current 3P attribution; bridge supply via `dw_3p_supply.fact_lead_3p_flows.sk_house` for funnel/ts analytics) |
| `sk_company` (as broker identifier) | `sk_broker` |
| `hubspot_member_category` (HubSpot tier) | `dim_broker_products.tier_name` / `dim_broker_tier_history` |
| `is_active_company_rede_partner` | `dim_broker.is_3p_active_broker` |
| `is_flagged_as_leadgen_in_hubspot` | `dim_broker.has_active_agents_in_lead_gen` |

## Golden Queries

### Query 1 — Active 3P brokers by product, business context, and state

Lists currently active partners along with their main product and operating state. Uses the current-state flags on `dim_broker` / `dim_broker_products`, joined to one region per product for geographic context.

```sql
WITH active_brokers AS (
    SELECT
        b.sk_broker,
        b.broker_name,
        b.broker_trade_name,
        b.broker_city,
        b.broker_state,
        b.is_3p_active_sale_broker,
        b.is_3p_active_rent_broker
    FROM dw_brokers.dim_broker AS b
    WHERE b.is_3p_active_broker = TRUE
),
products AS (
    SELECT
        p.sk_broker,
        p.product_name,
        p.business_context,
        p.tier_name,
        p.integrator_partner
    FROM dw_brokers.dim_broker_products AS p
    WHERE p.is_3p_active_broker = TRUE
)
SELECT
    ab.sk_broker,
    ab.broker_name,
    ab.broker_trade_name,
    ab.broker_state,
    p.business_context,
    p.product_name,
    p.tier_name,
    p.integrator_partner
FROM active_brokers AS ab
INNER JOIN products AS p ON ab.sk_broker = p.sk_broker
ORDER BY ab.broker_state, ab.broker_name, p.business_context
```

### Query 2 — Status timeline: recent (de)activations per business context

Recent transitions to or from `ACTIVE` in the Rede, per business context. Use `is_current = TRUE` for the currently-effective row of each `(sk_broker, business_context)` pair.

```sql
SELECT
    s.sk_broker,
    b.broker_name,
    s.business_context,
    s.broker_status,
    s.status_origin,
    s.version,
    s.is_current,
    s.ts_start,
    s.ts_end
FROM dw_brokers.dim_broker_status_history AS s
INNER JOIN dw_brokers.dim_broker AS b ON s.sk_broker = b.sk_broker
ORDER BY s.sk_broker, s.business_context, s.ts_start
```

### Query 3 — Current Account Manager + number of past handovers

Joins the current snapshot (`dim_broker.sk_person_account_manager`) with the count of historical assignments to surface the handover frequency. Filter `<> -1` to exclude unmapped brokers.

```sql
WITH am_counts AS (
    SELECT
        sk_broker,
        COUNT(*) AS total_assignments,
        MIN(ts_start) AS ts_first_assignment
    FROM dw_brokers.dim_broker_account_manager_history
    WHERE sk_person_account_manager <> -1
    GROUP BY sk_broker
)
SELECT
    b.sk_broker,
    b.broker_name,
    b.sk_person_account_manager,
    am.total_assignments,
    am.ts_first_assignment
FROM dw_brokers.dim_broker AS b
LEFT JOIN am_counts AS am ON b.sk_broker = am.sk_broker
WHERE b.is_3p_active_broker = TRUE
  AND b.sk_person_account_manager <> -1
ORDER BY am.total_assignments DESC NULLS LAST
```

### Query 4 — Active agents and admins per broker, from the broker registry

Counts active people on `dim_broker_profile_history` (the canonical "who is linked to the broker" source). The snapshot also lives pre-computed on `dim_broker` (`qt_active_agents` / `qt_active_broker_admins`), but querying the history table is the right move when you also need names or split by `sk_person`.

```sql
SELECT
    p.sk_broker,
    b.broker_name,
    COUNT(*) FILTER (WHERE p.is_agent AND p.is_active_profile) AS active_agents,
    COUNT(*) FILTER (WHERE p.is_broker_admin AND p.is_active_profile) AS active_admins
FROM dw_brokers.dim_broker_profile_history AS p
INNER JOIN dw_brokers.dim_broker AS b ON p.sk_broker = b.sk_broker
WHERE p.is_current = TRUE
  AND b.is_3p_active_broker = TRUE
GROUP BY p.sk_broker, b.broker_name
ORDER BY active_agents DESC
```

### Query 5 — Tier evolution per broker product

Time-line of tier (program) changes for each broker product. Join `dim_broker_products` for product/business_context context and `dim_broker` for the broker name.

```sql
SELECT
    t.sk_broker,
    b.broker_name,
    t.sk_broker_product,
    p.product_name,
    p.business_context,
    t.version,
    t.id_tier,
    t.tier_name,
    t.is_current,
    t.ts_start,
    t.ts_end
FROM dw_brokers.dim_broker_tier_history AS t
INNER JOIN dw_brokers.dim_broker AS b ON t.sk_broker = b.sk_broker
INNER JOIN dw_brokers.dim_broker_products AS p ON t.sk_broker_product = p.sk_broker_product
WHERE b.is_3p_active_broker = TRUE
ORDER BY t.sk_broker, t.sk_broker_product, t.version
```

### Query 6 — Active brokers cross-referenced with their current 3P agents

Joins the broker registry to the Agents domain. The example uses `dim_agent_3p_history` (3P-only by construction) for the SCD2 current revision; an equivalent join can be done on `dim_agent` with `is_3p_agent = TRUE`.

```sql
SELECT
    b.sk_broker,
    b.broker_name,
    b.qt_active_agents,
    COUNT(DISTINCT a.sk_agent) AS observed_active_agents_in_dw_agent
FROM dw_brokers.dim_broker AS b
LEFT JOIN dw_agent.dim_agent_3p_history AS a
    ON a.sk_broker = b.sk_broker
   AND a.is_current = TRUE
   AND a.is_active = TRUE
WHERE b.is_3p_active_broker = TRUE
GROUP BY b.sk_broker, b.broker_name, b.qt_active_agents
ORDER BY observed_active_agents_in_dw_agent DESC
```

### Query 7 — 3P supply volume per broker (high-level)

Counts of leads in the 3P supply funnel per partner broker. For funnel-stage breakdown (Opportunity, First Listing, etc.) and L2FL routing, follow [`3p_supply.md`](./3p_supply.md).

```sql
SELECT
    f.sk_broker,
    b.broker_name,
    f.business_context,
    COUNT(DISTINCT f.sk_lead_3p_flow) AS total_leads,
    COUNT(DISTINCT CASE WHEN f.ts_first_listing IS NOT NULL THEN f.sk_lead_3p_flow END) AS first_listings,
    COUNT(DISTINCT CASE WHEN f.is_opportunity = TRUE THEN f.sk_lead_3p_flow END) AS opportunities
FROM dw_3p_supply.fact_lead_3p_flows AS f
INNER JOIN dw_brokers.dim_broker AS b ON f.sk_broker = b.sk_broker
WHERE f.sk_broker <> -1
GROUP BY f.sk_broker, b.broker_name, f.business_context
ORDER BY total_leads DESC
```

### Query 8 — 3P transactions (Visits and Offers) per broker, by side

Aggregates 3P For Sale visits and offers per broker, split between supply-side and demand-side roles. Notice the `UNION ALL` pattern to attribute one transaction to two brokers without double-counting via `GROUP BY`.

```sql
WITH visits_supply AS (
    SELECT sk_broker_supply AS sk_broker,
           'visit'   AS event_type,
           'supply'  AS broker_side,
           COUNT(*)  AS event_count
    FROM dw_sale_visits.fact_visits
    WHERE is_3p_supply = TRUE
      AND sk_broker_supply <> -1
    GROUP BY sk_broker_supply
),
visits_demand AS (
    SELECT sk_broker_demand AS sk_broker,
           'visit'   AS event_type,
           'demand'  AS broker_side,
           COUNT(*)  AS event_count
    FROM dw_sale_visits.fact_visits
    WHERE (is_3p_demand = TRUE OR is_3p_lead_gen = TRUE)
      AND sk_broker_demand <> -1
    GROUP BY sk_broker_demand
),
offers_supply AS (
    SELECT sk_broker_supply AS sk_broker,
           'offer'   AS event_type,
           'supply'  AS broker_side,
           COUNT(*)  AS event_count
    FROM dw_sale_offers.fact_offers
    WHERE is_3p_supply = TRUE
      AND sk_broker_supply <> -1
    GROUP BY sk_broker_supply
),
offers_demand AS (
    SELECT sk_broker_demand AS sk_broker,
           'offer'   AS event_type,
           'demand'  AS broker_side,
           COUNT(*)  AS event_count
    FROM dw_sale_offers.fact_offers
    WHERE (is_3p_demand = TRUE OR is_3p_lead_gen = TRUE)
      AND sk_broker_demand <> -1
    GROUP BY sk_broker_demand
),
unioned AS (
    SELECT * FROM visits_supply
    UNION ALL SELECT * FROM visits_demand
    UNION ALL SELECT * FROM offers_supply
    UNION ALL SELECT * FROM offers_demand
)
SELECT
    u.sk_broker,
    b.broker_name,
    u.event_type,
    u.broker_side,
    SUM(u.event_count) AS event_count
FROM unioned AS u
INNER JOIN dw_brokers.dim_broker AS b ON u.sk_broker = b.sk_broker
GROUP BY u.sk_broker, b.broker_name, u.event_type, u.broker_side
ORDER BY b.broker_name, u.event_type, u.broker_side
```

### Query 9 — Monthly visibility-to-CCV funnel per 3P broker

Aggregates daily snapshot metrics from `fact_daily_ongoing_listing` per month × broker. Bridges `sk_house → fact_listings.sk_broker` to attribute each published-day to the correct partner. Derives 3 conversion ratios (LPV / Search, VC / LPV, CCV / VC) so analysts see the visibility-to-closing path on 3P inventory in a single shot. **Remember the truncation caveat**: this is *visibility and demand on days the listing was published*, not absolute funnel totals — for the latter use `fact_sale_demand_event`.

```sql
WITH listings_3p AS (
    SELECT
        fl.sk_house,
        fl.sk_broker
    FROM dw_sale_listings.fact_listings AS fl
    WHERE fl.sk_broker <> -1
),
daily_3p AS (
    SELECT
        l.sk_broker,
        DATE_TRUNC('month', CAST(d.sk_snapshot_date AS DATE)) AS month,
        SUM(d.qt_search_result_page_viewed)  AS search_results_views,
        SUM(d.qt_listing_page_viewed)        AS listing_page_views,
        SUM(d.qt_visits_booked)              AS visits_booked,
        SUM(d.qt_visits_completed)           AS visits_completed,
        SUM(d.qt_offers_submitted)           AS offers_submitted,
        SUM(d.qt_offers_accepted)            AS offers_accepted,
        SUM(d.qt_sale_agreements_created)    AS ccv_created,
        SUM(d.qt_sale_agreements_signed)     AS ccv_signed,
        COUNT(DISTINCT d.sk_house)           AS distinct_published_listings,
        COUNT(*)                             AS published_listing_days
    FROM dw_sale.fact_daily_ongoing_listing AS d
    INNER JOIN listings_3p AS l ON d.sk_house = l.sk_house
    GROUP BY l.sk_broker, DATE_TRUNC('month', CAST(d.sk_snapshot_date AS DATE))
)
SELECT
    da.sk_broker,
    b.broker_name,
    da.month,
    da.distinct_published_listings,
    da.published_listing_days,
    da.search_results_views,
    da.listing_page_views,
    da.visits_booked,
    da.visits_completed,
    da.offers_submitted,
    da.offers_accepted,
    da.ccv_signed,
    CAST(da.listing_page_views AS DOUBLE) / NULLIF(da.search_results_views, 0)  AS lpv_per_search_result,
    CAST(da.visits_completed   AS DOUBLE) / NULLIF(da.listing_page_views, 0)    AS vc_per_lpv,
    CAST(da.ccv_signed         AS DOUBLE) / NULLIF(da.visits_completed, 0)      AS ccv_per_vc
FROM daily_3p AS da
INNER JOIN dw_brokers.dim_broker AS b ON da.sk_broker = b.sk_broker
ORDER BY da.month DESC, da.ccv_signed DESC NULLS LAST
```

### Query 10 — Traffic origin (UTM / platform / referrer) of LPV on 3P listings

Splits Listing-Page-Viewed events on 3P listings by acquisition channel — `platform`, `utm_source`, `utm_medium`, normalised `base_referrer_url`. Uses `fact_search_session_event` filtered to `event_type = 'Listing Page Viewed'` and `business_context = 'sale'`. Bridges `sk_house → dim_listing.is_3p_supply` for the 3P-only filter and then `→ fact_listings.sk_broker` to attribute per partner. Returns the top channel combinations per broker; cap with a `HAVING COUNT(*) >= N` if the partner has too long a tail.

```sql
WITH listings_3p AS (
    SELECT
        fl.sk_house,
        fl.sk_broker
    FROM dw_sale_listings.fact_listings AS fl
    INNER JOIN dw_sale_listings.dim_listing AS dl ON fl.sk_house = dl.sk_house
    WHERE fl.sk_broker <> -1
      AND dl.is_3p_supply = TRUE
),
lpv_3p AS (
    SELECT
        l.sk_broker,
        t.platform,
        t.utm_source,
        t.utm_medium,
        t.base_referrer_url,
        t.search_rendering_type,
        COUNT(*)                       AS lpv_count,
        COUNT(DISTINCT e.sk_session)   AS distinct_sessions,
        COUNT(DISTINCT e.sk_amplitude) AS distinct_visitors
    FROM dw_public.fact_search_session_event AS e
    INNER JOIN dw_public.dim_search_session_event_type AS t ON e.sk_event_type = t.sk_event_type
    INNER JOIN listings_3p AS l ON e.sk_house = l.sk_house
    WHERE t.event_type = 'Listing Page Viewed'
      AND t.business_context = 'sale'
    GROUP BY l.sk_broker, t.platform, t.utm_source, t.utm_medium, t.base_referrer_url, t.search_rendering_type
)
SELECT
    lpv.sk_broker,
    b.broker_name,
    lpv.platform,
    lpv.utm_source,
    lpv.utm_medium,
    lpv.base_referrer_url,
    lpv.search_rendering_type,
    lpv.lpv_count,
    lpv.distinct_sessions,
    lpv.distinct_visitors
FROM lpv_3p AS lpv
INNER JOIN dw_brokers.dim_broker AS b ON lpv.sk_broker = b.sk_broker
WHERE lpv.lpv_count >= 50
ORDER BY b.broker_name, lpv.lpv_count DESC
```

### Query 11 — Active 3P agents per month (any-overlap)

Counts distinct 3P agents active in each calendar month using the SCD2 history. A revision counts when `is_active = TRUE` and its `(ts_started, ts_ended)` interval overlaps any day of the month (any-overlap rule). The same query also splits by Lead Gen eligibility (`is_passive_lead_receiver`) — to break down by broker, replace `GROUP BY month` with `GROUP BY month, sk_broker` and join `dw_brokers.dim_broker` for the name.

```sql
WITH monthly_spine AS (
    SELECT month_start
    FROM UNNEST(
        SEQUENCE(date '2023-01-01', current_date, interval '1' month)
    ) AS t (month_start)
),
spine_bounds AS (
    SELECT
        month_start,
        date_add('day', -1, date_add('month', 1, month_start)) AS month_end
    FROM monthly_spine
),
active_revisions AS (
    SELECT
        s.month_start,
        s.month_end,
        h.sk_agent,
        h.sk_broker,
        h.is_passive_lead_receiver
    FROM spine_bounds AS s
    INNER JOIN dw_agent.dim_agent_3p_history AS h
        ON h.is_active = TRUE
       AND CAST(h.ts_started AS DATE) <= s.month_end
       AND (h.ts_ended IS NULL OR CAST(h.ts_ended AS DATE) > s.month_start)
)
SELECT
    month_start,
    COUNT(DISTINCT sk_agent)                                                            AS active_3p_agents,
    COUNT(DISTINCT sk_agent) FILTER (WHERE is_passive_lead_receiver = TRUE)             AS active_lead_gen_agents,
    COUNT(DISTINCT sk_agent) FILTER (WHERE is_passive_lead_receiver = FALSE OR is_passive_lead_receiver IS NULL) AS active_non_lead_gen_agents,
    COUNT(DISTINCT sk_broker) FILTER (WHERE sk_broker <> -1)                            AS active_brokers_with_agents
FROM active_revisions
GROUP BY month_start
ORDER BY month_start
```

### Query 12 — Active brokers distribution by state × business_context (regions)

Distribution of currently-active 3P brokers across states and business contexts, using `dim_broker_regions` enriched with the geographic hierarchy. The `level = 'Cidade'` filter avoids fanout when a broker declares both Cidade and SubRegiao tokens for the same area; switch to `level = 'MacroRegiao'` or `level = 'SubRegiao'` for higher / finer aggregations. `state_abbreviation` is preferred over `state_name` for compact reporting.

```sql
WITH city_regions AS (
    SELECT
        r.sk_broker,
        r.business_context,
        r.state_abbreviation,
        r.state_name
    FROM dw_brokers.dim_broker_regions AS r
    WHERE r.level = 'Cidade'
),
active_products AS (
    SELECT
        p.sk_broker,
        p.business_context
    FROM dw_brokers.dim_broker_products AS p
    WHERE p.is_3p_active_broker = TRUE
)
SELECT
    cr.state_abbreviation,
    cr.business_context,
    COUNT(DISTINCT cr.sk_broker) AS active_brokers
FROM city_regions AS cr
INNER JOIN active_products AS ap
    ON ap.sk_broker        = cr.sk_broker
   AND ap.business_context = cr.business_context
WHERE cr.state_abbreviation IS NOT NULL
GROUP BY cr.state_abbreviation, cr.business_context
ORDER BY cr.state_abbreviation, cr.business_context
```

### Query 13 — Tier distribution per state and business_context

3-way cross-tab of active brokers by `state_abbreviation × business_context × tier_name`. Uses `dim_broker_tier_history` filtered to `is_current = TRUE` so the tier reflects the **current** commercial program (history of tier transitions is in Query 5). Bridges `sk_broker_product` between products, regions, and tier to keep the modality correctly attributed.

```sql
WITH active_products AS (
    SELECT
        p.sk_broker_product,
        p.sk_broker,
        p.business_context
    FROM dw_brokers.dim_broker_products AS p
    WHERE p.is_3p_active_broker = TRUE
),
current_tier AS (
    SELECT
        t.sk_broker_product,
        t.tier_name
    FROM dw_brokers.dim_broker_tier_history AS t
    WHERE t.is_current = TRUE
),
city_regions AS (
    SELECT DISTINCT
        r.sk_broker,
        r.business_context,
        r.state_abbreviation
    FROM dw_brokers.dim_broker_regions AS r
    WHERE r.level = 'Cidade'
      AND r.state_abbreviation IS NOT NULL
)
SELECT
    cr.state_abbreviation,
    ap.business_context,
    COALESCE(ct.tier_name, '(no tier)') AS tier_name,
    COUNT(DISTINCT ap.sk_broker)        AS active_brokers
FROM active_products AS ap
LEFT JOIN current_tier AS ct ON ct.sk_broker_product = ap.sk_broker_product
INNER JOIN city_regions AS cr
    ON cr.sk_broker        = ap.sk_broker
   AND cr.business_context = ap.business_context
GROUP BY cr.state_abbreviation, ap.business_context, COALESCE(ct.tier_name, '(no tier)')
ORDER BY cr.state_abbreviation, ap.business_context, active_brokers DESC
```

### Query 14 — Integrator partner adoption per state

Share of integrator partners (external CRMs) per state and business context. Uses `dim_broker_integrator_partner_history.is_current = TRUE` to capture the **current** integrator assignment per product. The window `over (PARTITION BY state, business_context)` produces the share inside each cell, which is what's typically asked when comparing integrator concentration regionally.

```sql
WITH active_products AS (
    SELECT
        p.sk_broker_product,
        p.sk_broker,
        p.business_context
    FROM dw_brokers.dim_broker_products AS p
    WHERE p.is_3p_active_broker = TRUE
),
current_integrator AS (
    SELECT
        i.sk_broker_product,
        COALESCE(i.integrator_partner, '(no integrator)') AS integrator_partner
    FROM dw_brokers.dim_broker_integrator_partner_history AS i
    WHERE i.is_current = TRUE
),
city_regions AS (
    SELECT DISTINCT
        r.sk_broker,
        r.business_context,
        r.state_abbreviation
    FROM dw_brokers.dim_broker_regions AS r
    WHERE r.level = 'Cidade'
      AND r.state_abbreviation IS NOT NULL
),
agg AS (
    SELECT
        cr.state_abbreviation,
        ap.business_context,
        ci.integrator_partner,
        COUNT(DISTINCT ap.sk_broker) AS active_brokers
    FROM active_products AS ap
    LEFT JOIN current_integrator AS ci ON ci.sk_broker_product = ap.sk_broker_product
    INNER JOIN city_regions AS cr
        ON cr.sk_broker        = ap.sk_broker
       AND cr.business_context = ap.business_context
    GROUP BY cr.state_abbreviation, ap.business_context, ci.integrator_partner
)
SELECT
    state_abbreviation,
    business_context,
    integrator_partner,
    active_brokers,
    CAST(active_brokers AS DOUBLE)
        / SUM(active_brokers) OVER (PARTITION BY state_abbreviation, business_context) AS share_within_state_bc
FROM agg
ORDER BY state_abbreviation, business_context, active_brokers DESC
```

### Query 15 — 3P agent performance benchmarks per broker (monthly)

Monthly performance benchmarks at the partner-imobiliária grain. Aggregates `fact_visit_agent_performance` (daily per agent) into monthly sums, filters to 3P agents via `dim_agent.is_3p_agent`, and groups by `sk_broker`. Use the `has_*_performance` flags on the source to restrict the average denominators to rows where the metric is actually populated.

```sql
WITH agents_3p AS (
    SELECT
        a.sk_agent,
        a.sk_broker
    FROM dw_public.dim_agent AS a
    WHERE a.is_3p_agent = TRUE
      AND a.sk_broker  <> -1
),
monthly_perf AS (
    SELECT
        ag.sk_broker,
        DATE_TRUNC('month', CAST(f.dt_reference AS DATE)) AS month,
        COUNT(DISTINCT f.sk_agent)                                AS active_3p_agents_with_data,
        SUM(f.total_visit_booked)                                 AS total_visit_booked,
        SUM(f.total_visit_completed)                              AS total_visit_completed,
        SUM(f.total_booking_stalled)                              AS total_booking_stalled,
        SUM(f.total_offer_submitted)                              AS total_offer_submitted,
        SUM(f.total_offer_approved)                               AS total_offer_approved,
        SUM(f.total_contract_signed)                              AS total_contract_signed,
        SUM(f.total_leads)                                        AS total_leads,
        SUM(f.total_lead_to_visit_completed)                      AS total_lead_to_visit_completed,
        SUM(f.total_lead_to_contract_signed)                      AS total_lead_to_contract_signed,
        SUM(f.total_leads_to_contract_signed_cohort_7_days)       AS total_leads_to_contract_signed_cohort_7_days,
        SUM(f.total_supply_first_listing)                         AS total_supply_first_listing
    FROM dw_agent.fact_visit_agent_performance AS f
    INNER JOIN agents_3p AS ag ON ag.sk_agent = f.sk_agent
    GROUP BY ag.sk_broker, DATE_TRUNC('month', CAST(f.dt_reference AS DATE))
)
SELECT
    mp.sk_broker,
    b.broker_name,
    mp.month,
    mp.active_3p_agents_with_data,
    mp.total_visit_booked,
    mp.total_visit_completed,
    mp.total_offer_submitted,
    mp.total_contract_signed,
    mp.total_supply_first_listing,
    CAST(mp.total_visit_completed   AS DOUBLE) / NULLIF(mp.total_visit_booked, 0)    AS visit_completion_rate,
    CAST(mp.total_offer_submitted   AS DOUBLE) / NULLIF(mp.total_visit_completed, 0) AS offer_per_visit_completed,
    CAST(mp.total_contract_signed   AS DOUBLE) / NULLIF(mp.total_offer_approved, 0)  AS contract_per_offer_approved,
    CAST(mp.total_visit_completed   AS DOUBLE) / NULLIF(mp.active_3p_agents_with_data, 0) AS avg_visit_completed_per_agent,
    CAST(mp.total_contract_signed   AS DOUBLE) / NULLIF(mp.active_3p_agents_with_data, 0) AS avg_contract_signed_per_agent
FROM monthly_perf AS mp
INNER JOIN dw_brokers.dim_broker AS b ON b.sk_broker = mp.sk_broker
WHERE mp.active_3p_agents_with_data > 0
ORDER BY mp.month DESC, mp.total_contract_signed DESC NULLS LAST
```
