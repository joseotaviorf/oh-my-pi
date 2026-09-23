# Agents — Performance (Visit Funnel, Demand Acquisition, Milestones, Supply & CIQ)

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

### Demand-side (visit funnel, TQC/TQA, milestones)

- **Objective:** Shared source of truth for agent visit funnel KPIs, TQC/TQA demand-acquisition conversion (with same-agent attribution), and first/last milestone timestamps — without reimplementing PFA, key-holder, VBBA, or referral revision logic in ad-hoc SQL.
- **Asset status / lifecycle:** visit created → completed/canceled → (sale) offer/agreement; referral invited → confirmed → visits/offers/contracts with optional same-agent handling; milestones materialize first/last event per agent and type.
- **Typical actions / events:** visit booking/completion, PFA/CRCC/VBBA attribution cuts, referral status revisions, TQC/TQA funnel stages.
- **Common metrics:** daily `total_visit*` (and `_pfa` / `_crcc` / `_vbba` cuts), same-agent visit/offer/agreement rates on referrals, `ts_first` on `TQC_VB_SAME_AGENT` / `TQA_VB_SAME_AGENT`.
- **Source systems:** visit product, PFA history, key-holder (CRCC) history, sale offers, referral audit, offer specialists (via `enrich_agent_performance` / `dw_agent_visit_funnel` / `dw_agent_milestone` DAGs).
- **Track 4 (supply acquisition in `agent_performance`):** under development — not documented here.

### Supply-side (valid first listing & CIQ Compra de Carteira)

- **Objective:** Two related concepts that gate agent commissions on supply: **Valid First Listing** (property dedup, so a re-listed property doesn't count as a new first listing) and **CIQ Listing Purchase / Compra de Carteira** (pricing, payment, and portfolio-loss outcomes for CIQ_FULL rent listings).
- **Asset status / lifecycle:** listing published → deduplicated against similar/prior houses → validated first listing → (Compra de Carteira track) priced → paid → portfolio-loss evaluated on relist.
- **Typical actions / events:** address parsing/dedup, first-listing validation, CIQ pricing (initial → final), payment, portfolio-loss flagging.
- **Common metrics:** valid first listings per period, Compra de Carteira paid amount, portfolio loss rate.
- **Source systems:** EBDB house/listing data, Atlas (similar-property detection).
- **Related entities:** for the tiers-specific `ciq_first_listing` variant of first-listing validity, see [`agents_profile.md`](agents_profile.md). For `listing_category` / rent versioning semantics, see [`house_and_listing.md`](house_and_listing.md). For visit product semantics, PFA/PPA, and raw TQC invites, see [`visits.md`](visits.md) and [`agents_programs.md`](agents_programs.md).

---

## TARS routing guide — visit funnel, TQC/TQA, milestones

Read this first for **demand-side** agent KPIs. Three independent grains live under `datalake_agent_performance` / `dw_agent_performance` — do not join them expecting one row per visit, referral, or agent.

| Track | Business question | Default table | Grain |
|-------|-------------------|---------------|-------|
| **1 — Visit funnel** | How many visits did an agent book, complete, or convert — overall, PFA, key-holder (CRCC), or VBBA? | `dw_agent_performance.agent_visit_funnel` | `uuid_person` + `date_ref` |
| **1 — Visit drill-down** | One visit, attribution flags, sale conversion on that visit | `datalake_agent_performance.visit_funnel_event` | `id_visit` |
| **2 — Demand acquisition** | Agent invited a buyer/tenant — did the lead progress, and did the **inviting** agent handle each step? | `datalake_agent_performance.fact_agent_demand_acquisition` | `id_referral` + `rev` |
| **3 — Milestones** | When did an agent first/last hit a **TQC/TQA** stage? | `dw_agent_performance.dim_agent_milestone` | `sk_user` + `milestone_type` |

**Scope (RENT / SALE):** Track 1 includes **both** rent and sale visit funnels (sale adds offer/agreement flags). Filter `business_context = 'SALE'` on `visit_funnel_event` for sale-only. Track 2: **TQC** = `business_context = 'SALE'`, **TQA** = `business_context = 'RENT'`. Track 3 validated types are TQC* / TQA* only.

**Replaces for current visit KPIs:** `dw_agent.fact_visit_agent_performance` and `datalake_visit_agent_performance.*` stopped updating **2025-09-21** — historical only. Use the demand-side sections below for post-migration visit KPIs, TQC/TQA conversion, and milestone timelines.

**Supply-side (valid first listing / Compra de Carteira):** different schemas and grains — see [`datalake_listing_deduplication`](#datalake_listing_deduplication-valid-first-listing) and [CIQ Listing Purchase](#ciq-listing-purchase-compra-de-carteira) below.

---

## Related Metric Entities

- None — no metric entity doc references the Agents domain as of 2026-08.
- Visit-grain dashboard metrics may overlap [`visit_funnel_dashboard.md`](../metric_entities/visit_funnel_dashboard.md) — prefer **agent-day** tables in Track 1 when the question is per-agent OKRs.

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **VBBA** | Visits booked by agent — booking agent ≠ last-associated agent | `uuid_person_agent_vbba`; DW metrics suffix `_vbba` |
| **VCBA** | Completed visits that were VBBA | Filter Track 1 on `is_vbba_visit` and `is_visit_completed` at visit grain |
| **PFA visit** | Visit where agent is also visitor's Preferred Fixed Agent | `is_pfa_visit`; suffix `_pfa` |
| **CRCC / key-holder visit** | Visit where agent held the house key at visit time | `is_crcc_visit`; suffix `_crcc` |
| **Last associated agent** | Agent credited for **overall** visit metrics | `uuid_person_last_associated_agent` |
| **TQC / TQA** | Sale / rent demand acquisition (invited lead) | Track 2 and validated `milestone_type` prefixes |
| **Same-agent attribution** | Inviting agent also handled the step | `is_visit_same_agent`, `is_offer_same_agent`, `is_agreement_same_agent`; `*_SAME_AGENT` milestone types |
| **Referral revision** | Status change on one `id_referral` | Grain includes `rev`; `valid_to IS NULL` = current version |
| **Valid First Listing** | A first listing that survives property deduplication — a re-listed/duplicated property does NOT count again | `datalake_listing_deduplication.valid_first_listing`. Metric definition still evolving. |
| **Primeira listagem / first listing** | ⚠ "any first listing" vs "valid first listing" (dedup-gated) | Default to valid for CIQ/activation, confirm with the user. |
| **Compra de Carteira / CIQ listing purchase** | CIQ_FULL rent listing-purchase — eligibility, pricing, portfolio loss | `dw_ciq.fact_ciq_listing_purchase`. |
| **Perda de carteira / portfolio loss** | Relist still on market >90 days without a signed rent contract, or rent CS on/after 2026-07-01 with a later non-canceled CCV on the same house | `is_portfolio_loss` / `portfolio_loss_reason` on the DW fact only. |
| **Re-Listing** | New rent listing cycle after a prior rental ended | `listing_category = 'Re-Listing'`. See [`house_and_listing.md`](house_and_listing.md). |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Daily visit KPIs per agent (dashboards, OKRs) | `dw_agent_performance.agent_visit_funnel` — **both** rent and sale (filter upstream at enrich if sale-only) |
| Visit-level funnel, flags, timestamps | `datalake_agent_performance.visit_funnel_event` — **both**; filter `business_context` |
| Referral journey, same-agent flags, first events | `datalake_agent_performance.fact_agent_demand_acquisition` — **SALE (TQC)** and **RENT (TQA)** via `business_context` |
| First/last TQC/TQA milestone per agent | `dw_agent_performance.dim_agent_milestone` — validated types `TQC*` / `TQA*` only |
| Agent-day spine (upstream to DW visit funnel) | `dw_agent.fact_agent_daily` |
| Agent attributes from `uuid_person` | `dw_public.dim_user` (join on `uuid_person`) |
| Agent attributes from `sk_user` / milestones | `dw_public.dim_user` (`sk_user` = `id_user`) |
| Raw TQC/TQA invite rows (not conversion funnel) | `datalake_ebdb_clean.agent_lead_referral` — see [`agents_programs.md`](agents_programs.md) |
| Legacy daily visit performance (stale) | `dw_agent.fact_visit_agent_performance` — **historical only** (stopped 2025-09-21) |
| Deduplicated, validated first-listing record | `datalake_listing_deduplication.valid_first_listing` |
| Address-normalized dedup analysis | `datalake_listing_deduplication.listing_deduplication` |
| CIQ Compra de Carteira — dashboards, portfolio loss, final pricing, payment | `dw_ciq.fact_ciq_listing_purchase` |
| Similar-house / Atlas duplicity peer rows | `dw_ciq.fact_listing_purchase_duplicity` |
| Initial pricing speculation (pre-override) | `datalake_ciq.ciq_listing_purchase` |

**Critical rules (demand-side / operational tracks):**

- **Three tracks, three grains** — never blend Track 1 visit counts with Track 2 referral rows or Track 3 milestone rows in one fact without explicit aggregation.
- **Attribution cuts on Track 1:** overall = last associated agent; PFA/CRCC = same person under extra rules; VBBA = **booking** agent (can differ). DW exposes each metric four ways: no suffix, `_pfa`, `_crcc`, `_vbba`.
- **Track 2 events** attach only while `referral_status` is `CONFIRMED` or `INACTIVE` and `ts_event` is between `valid_from` and `valid_to`. Same-agent on visit **completion** uses the **booking** agent (no separate completion-agent field).
- **Track 3:** only `TQC*` / `TQA*` types are validated. Other `milestone_type` values (`VB`, `VC`, `FL`, `FL_VALID`, `CS`, `CCV`, accreditation lifecycle types) are **placeholders** — not for dashboards, OKRs, or payouts until explicitly validated. `_SAME_AGENT` types are **subsets** of their base type — do not sum both in one funnel total.
- **`agent_visit_funnel` zero-visit rows:** `total_visit = 0` with other fields coalesced to 0 — agent active that day but no visits **created** that day; filter `total_visit > 0` for pure visit volume reports.
- **Pre-2026-06-17 referrals** in Track 2 are sale-only backfill (TQA did not exist yet).

**Critical rules (supply / CIQ):**

- **DW first:** analyst queries for Compra de Carteira must start at `dw_ciq.fact_ciq_listing_purchase`. Use `datalake_ciq.ciq_listing_purchase` only for `initial_pricing_type*` or pipeline debugging.
- `payment_status` and `is_eligible` live on `listing_purchase_pricing` / the DW fact — they are **not** on `ciq_listing_purchase` anymore.
- Grain of `datalake_ciq.ciq_listing_purchase`: **Rent arm** — one row per signed rent `id_contract` (`house_listing`; 1:1 with contract id in prod). **Sale arm** — one row per house with SALE `listing_business_context` and latest CCV (`id_offer` populated, `id_contract` / `id_house_listing` null, always `not-eligible` for Compra payment). Hybrid houses can have both a RENT and a SALE row; that is not a duplicate rent contract. CIQ partner/user comes from `house_listing_consultant` last CIQ on the listing (`is_last_ciq_on_listing = true`; same grain as FL Valid / `first_listing`). The DW fact follows that enrich grain after the pricing merge; filter `consultant_type` and use DW columns for final pricing.

---

## Track 1 — Visit funnel

### `datalake_agent_performance.visit_funnel_event`

Grain: **one row per `id_visit`**. Incremental load via `enrich_agent_performance`.

Pre-joins visit, PFA, key-holder, and sale-offer logic so consumers do not reimplement fan-out-prone joins. `dt_visit_created` drives DW `date_ref`; `dt_visit` is when the visit happens on the property.

| Content area | Key fields | Consumer notes |
|--------------|------------|----------------|
| Visit context | `id_visit`, `id_visitor`, `id_house`, `business_context`, `dt_visit_created`, `dt_visit` | Sale-only: `business_context = 'SALE'` |
| Agent attribution | `uuid_person_last_associated_agent`, `uuid_person_agent_vbba`, `uuid_person_fixed_agent` | Up to three different agents on one row |
| Outcome flags | `is_visit_canceled`, `is_visit_completed`, `is_visit_unsuccessful`, `is_visit_stalled`, `is_visit_not_finished`, `nbr_reschedule` | Mutually informative status slice; completed visits can still have offer flags |
| Attribution cuts | `is_pfa_visit`, `is_crcc_visit`, `is_vbba_visit` | Precomputed booleans — filter or understand DW suffix columns |
| Sale conversion | `is_offer_submitted`, `is_offer_accepted`, `is_agreement_signed` | Linked offers via `id_visit_external` **or** `id_visit_fifty_external`; **any** linked offer can set flag to 1 |
| Timestamps | `ts_visit_created`, `ts_visit_done`, `ts_offer_submitted`, `ts_sale_agreement_signed`, … | Time-between-stage analysis; sale-offer timestamps null on rent-only visits |

Use this table for **visit-level** detail (for example PFA visits that received an offer) or cuts not yet exposed in the DW rollup.

### `dw_agent_performance.agent_visit_funnel`

Grain: **one row per `uuid_person` + `date_ref`**. Incremental via `dw_agent_visit_funnel`. Left-joins agent-day spine from `fact_agent_daily`. Default table for dashboards and OKRs.

| Content area | Key fields | Consumer notes |
|--------------|------------|----------------|
| Keys | `uuid_person`, `date_ref`, `sk_agent_visit_funnel` | Join `uuid_person` → `dw_public.dim_user` for agent attributes |
| Volume funnel | `total_visit`, `total_reschedule`, `total_visit_canceled`, `total_visit_completed`, `total_visit_unsuccessful`, `total_visit_stalled`, `total_visit_not_finished` | Each metric in four cuts: overall, `_pfa`, `_crcc`, `_vbba` |
| Sale conversion funnel | `total_offer_submitted`, `total_offer_accepted`, `total_agreement_signed` | Same four-cut pattern; counts **visits** that reached each stage, not raw offer rows |
| Timing averages | `avg_hours_booked_to_completed`, `avg_hours_completed_to_offer_submitted` | Agent-day average hours between stages (completed / offered visits only) |
| Zero-visit rows | `total_visit = 0` with other fields coalesced to 0 | Agent active that day but no visits **created** that day |

Replaces legacy `total_schedule*` with visit-based `total_visit*`. Legacy DW visit funnel was sale-only; this table includes rent and sale unless filtered upstream at enrich.

### Attribution cuts (Track 1)

| Cut | Who gets credit | DW suffix |
|-----|-----------------|-----------|
| **Overall** | Last associated agent on the visit | *(none)* |
| **PFA** | Same agent, visit where they are also the visitor's Preferred Fixed Agent | `_pfa` |
| **CRCC** | Same agent, visit where they held the house key at visit time | `_crcc` |
| **VBBA** | **Booking agent** — can be a different person than last-associated | `_vbba` |

---

## Track 2 — Demand acquisition

### `datalake_agent_performance.fact_agent_demand_acquisition`

Grain: **one row per `id_referral` + `rev`**. Full reload via `enrich_agent_performance`. Feeds validated TQC/TQA rows in `dim_agent_milestone`.

Tracks the **agent-referred lead** journey: an agent invites someone (TQC buyer or TQA tenant), and the table records whether that person progressed and who handled each step. `rev` marks a change in status for that `id_referral`.

| Content area | Key fields | Consumer notes |
|--------------|------------|----------------|
| Referral identity | `id_referral`, `rev`, `id_lead`, `uuid_person_referring_agent` | `id_lead` = buyer (sale) or tenant prospect (rent) |
| Referral context | `business_context`, `origin` (`REFERRAL`, `SERVICE_LINK`, `SCHEDULING_LINK`), `referral_status` | Rows before 2026-06-17 are sale-only backfill |
| Revision window | `valid_from`, `valid_to`, `previous_status` | `valid_to IS NULL` = current version; use all `rev` rows for history |
| Progress summary | `has_any_visits`, `has_any_offers` | Quick funnel gates — any agent handled visit/offer |
| Same-agent attribution | `is_visit_same_agent`, `is_offer_same_agent`, `is_agreement_same_agent` | Compares **referring agent** vs agent on first event; `NULL` means step never happened |
| Sale lifecycle | `sale_first_events` struct | Dot notation, e.g. `sale_first_events.ts_visit_booked`; handling agent per event |
| Rent lifecycle | `rent_first_events` struct | Same pattern; rent contract = `ts_contract_signed` |
| Referring-agent-only actions | `invitation_agent_interactions` struct | Events the **inviting** agent personally performed |
| Offer specialist | `offer_specialist` struct | Sale offer specialist alignment; `has_mismatch` vs referring agent |

**Track 2 caveats:**

| Mistake | Reality |
|---------|---------|
| Visit volume KPIs | Wrong track — use Track 1 |
| Pre-2026-06-17 referrals | Stored as `SALE` only since TQA didn't exist |
| `NULL` on same-agent flags | Step did not happen — not "unknown agent" |
| Mixing revision rows | Current-state analysis needs `valid_to IS NULL` |

---

## Track 3 — Milestones

### `dw_agent_performance.dim_agent_milestone`

Grain: **one row per `sk_user` + `milestone_type`**. Incremental per type via `dw_agent_milestone`. Answers **when did this agent first / last hit event X?** — not "how many today".

| Content area | Key fields | Consumer notes |
|--------------|------------|----------------|
| Grain keys | `sk_user` (= `id_user`), `milestone_type`, `id_agent` | Join `sk_user` → `dw_public.dim_user`; `id_agent` is sticky accreditation id |
| Timestamps | `ts_first`, `ts_last` | `ts_first` on incremental loads may reflect first event in scan window until bootstrap |
| Entity pointers | `sk_entity_first`, `sk_entity_last`, `entity_type` | `entity_type` tells you what `sk_entity_*` refers to |
| Pipeline metadata | `ts_row_updated` | Last write time — not a business event |

**Validated `milestone_type` values (TQC / TQA)** — sourced from Track 2; credit to **referring agent**:

| Type | Stage |
|------|-------|
| `TQC` / `TQA` | Referral confirmed (sale / rent) |
| `TQC_VB` / `TQA_VB` | Referred lead booked a visit (any agent) |
| `TQC_VB_SAME_AGENT` / `TQA_VB_SAME_AGENT` | Visit booked by referring agent |
| `TQC_VC` / `TQA_VC` | Referred lead completed visit (any agent) |
| `TQC_VC_SAME_AGENT` / `TQA_VC_SAME_AGENT` | Completed where referring agent was booking agent |
| `TQC_CCV` / `TQC_CCV_SAME_AGENT` | Sale agreement signed (any / referring agent) |

**Placeholder types** — the table may also contain rows for `VB`, `VC`, `FL`, `FL_VALID`, `CS`, `CCV`, and accreditation lifecycle types. These pull from other sources (visit schedules, first listing, contracts) with definitions **not** signed off for operational reporting. Do not use in dashboards, OKRs, or payouts until validated and this document is updated.

**Track 3 caveats:**

| Mistake | Reality |
|---------|---------|
| Using placeholder `milestone_type` values | Not source of truth |
| `TQC_VB` + `TQC_VB_SAME_AGENT` in one sum | `_SAME_AGENT` ⊆ `TQC_VB` |
| `ts_first` for brand-new agents | Incremental window may miss global first until bootstrap |

---

## `datalake_listing_deduplication` (Valid First Listing)

Why it matters: the same physical property can be listed multiple times (re-listing, hybrid rent+sale, multiple agents). Counting each listing as a "first listing" would inflate activation and over-pay CIQ commissions.

**`valid_first_listing`** — one row per `id_house` (rent and sale side by side): `id_ciq_user_sale`, `id_ciq_user_rent`, `is_hybrid_house`, `house_listing_status`, `ts_first_listing_rent/sale`, `days_between_fl_to_cs`, `supply_source_rent/sale`.

**`listing_deduplication`** — one row per `id_house`, address-normalized dedup analysis over the full EBDB house universe: `id_address_parsed_short`, `is_duplicated`, `is_first_listing_in_duplicates`, `address_full`.

> ⚠ **`valid_first_listing` vs `ciq_first_listing` (tiers-specific, see [`agents_profile.md`](agents_profile.md)):** both validate a dedup-gated first listing, but this table is the broader dedup/activation source, while `ciq_first_listing` is the CIQ-consultant/tiers scope with a general compliance rule (published ≥2 days, or a signed contract within 60 days of first publication). For CIQ tier/commission questions, use `ciq_first_listing`.

## CIQ Listing Purchase (Compra de Carteira)

Pricing has two layers — do not conflate: **initial** (`initial_pricing_type` on base enrich — pre-override speculation) vs **final** (`pricing_type` on the fact/pricing enrich — after previous-paid and paid-similar-house overrides).

Anti-repurchase keys on the fact: `sk_previous_listing_paid` (same house already purchased), `sk_similar_house_paid` (similar-address house already **paid**), `sk_listing_duplicity` (join `fact_listing_purchase_duplicity` for peer detail).

**Portfolio loss** (`is_portfolio_loss` / `portfolio_loss_reason`, DW-only): exactly one of (1) `listing_category = 'Re-Listing'` AND `listing_status IN ('PUBLISHED','PUBLICADO')` AND no signed rent contract AND `total_days_since_publish > 90`, or (2) rent `ts_contract_signed >= 2026-07-01` AND a later non-canceled CCV on the same house. Rules are mutually exclusive per row (90d needs null CS; CCV needs CS).

---

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when the question asks for an **official**, **MBR**, or **OKR** number.

### Component / exploratory metrics

- **Daily visits per agent:** `SUM(total_visit)` (and `_pfa`, `_crcc`, `_vbba` as needed) on `agent_visit_funnel` with partition filters and `total_visit > 0` when appropriate.
- **PFA visit share:** `total_visit_pfa / total_visit` on `agent_visit_funnel` (agent-day).
- **TQC same-agent visit rate:** among `fact_agent_demand_acquisition` rows with `valid_to IS NULL`, `referral_status = 'CONFIRMED'`, `business_context = 'SALE'`, share where `is_visit_same_agent` is true.
- **Time to first same-agent TQC visit booked:** `ts_first` where `milestone_type = 'TQC_VB_SAME_AGENT'`.
- **Portfolio loss volume:** `COUNT(*)` on `dw_ciq.fact_ciq_listing_purchase` where `is_portfolio_loss = true`; split by `portfolio_loss_reason`.
- **Compra de Carteira paid amount:** `SUM(amount_paid)` on `dw_ciq.fact_ciq_listing_purchase` where `is_paid = true`.
- **Valid first listings:** `COUNT(DISTINCT id_house)` on `datalake_listing_deduplication.valid_first_listing`.

---

## Relationships with other entities

- **Visit funnel ↔ Daily agent state:** `agent_visit_funnel` built from `visit_funnel_event` + `dw_agent.fact_agent_daily` spine — see [`agents_accreditation.md`](agents_accreditation.md).
- **Demand acquisition ↔ Programs:** raw invites in `agent_lead_referral`; modeled journey in `fact_agent_demand_acquisition` — see [`agents_programs.md`](agents_programs.md).
- **Milestones ↔ Demand acquisition:** validated TQC/TQA types sourced from Track 2 referring agent.
- **Visit funnel ↔ Visits domain:** `visit_funnel_event.id_visit` aligns with visit product; deep visit scheduling semantics in [`visits.md`](visits.md).
- **Listing purchase → house:** `fact_ciq_listing_purchase.sk_house` / enrich `id_house` is the house grain; SALE rows are one CCV per house, RENT rows are one signed contract.
- **Listing purchase → partner / CIQ user:** `sk_partner` / `sk_user` join accreditation identity (`agent.id_partner`, `agent.id_user`); last CIQ is a LEFT JOIN so both can be null. See [`agents_accreditation.md`](agents_accreditation.md).
- **Listing purchase → sale offer:** SALE enrich `id_offer` / fact `sk_offer` is the latest non-canceled CCV; RENT rows leave it null.
- **Listing purchase → rent contract:** RENT `sk_contract` / `id_contract`; SALE rows leave it null.
- **Valid first listing → listing purchase:** `valid_first_listing.id_house` aligns with listing-purchase `id_house` for hybrid / first-listing order (`hybrid_creation_order`).

---

## Dos and Don'ts

**Do:**

- Route **daily agent visit KPIs** to Track 1 (`agent_visit_funnel` default, `visit_funnel_event` for drill-down).
- Route **referral conversion and same-agent attribution** to Track 2 with `valid_to IS NULL` for current referral version.
- Route **first/last TQC/TQA dates** to Track 3 with explicit `milestone_type` filter.
- Filter integer `year` / `month` / `day` partitions on `agent_visit_funnel` for daily snapshots.
- For **CIQ portfolio loss**, use `dw_ciq.fact_ciq_listing_purchase.is_portfolio_loss` — do not re-derive from `has_republication` alone (that flag is on the **prior** cycle when a later version exists).
- For Compra de Carteira pricing, use `pricing_type` (final) — not `initial_pricing_type` (pre-override speculation).

**Don't:**

- Use `dw_agent.fact_visit_agent_performance` or `datalake_visit_agent_performance.*` for **current** agent visit KPIs.
- Use Track 1 for referral conversion or Track 2 for daily visit volume.
- Treat `NULL` on same-agent flags as unknown — it means the step did not occur.
- Sum `TQC_VB` and `TQC_VB_SAME_AGENT` as separate funnel stages.
- Use placeholder `milestone_type` values for official reporting.
- Reimplement PFA/CRCC/VBBA or offer linkage in raw visit tables when `visit_funnel_event` already exposes flags.
- Use `total_days_since_house_inactived` as "days available without rent" for Compra de Carteira — use `total_days_since_publish` / `is_portfolio_loss`.
- Treat `sk_similar_house_paid` as "any similar address" — it is specifically the **already-paid** similar house (anti-repurchase).
- Treat `datalake_big_agent.house_consultant_history.consultant_type` (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) as stable — active RFC pending.

---

## Golden Queries

### Query 1 — Daily visits per agent (Track 1)

```sql
SELECT
    uuid_person,
    date_ref,
    total_visit,
    total_visit_pfa,
    total_visit_vbba
FROM dw_agent_performance.agent_visit_funnel
WHERE year = 2026
  AND month = 9
  AND day = 15
  AND total_visit > 0;
```

### Query 2 — TQC same-agent visit rate (Track 2)

```sql
SELECT
    uuid_person_referring_agent,
    COUNT(*) AS referrals,
    SUM(CASE WHEN is_visit_same_agent THEN 1 ELSE 0 END) AS same_agent_visits
FROM datalake_agent_performance.fact_agent_demand_acquisition
WHERE valid_to IS NULL
  AND business_context = 'SALE'
  AND referral_status = 'CONFIRMED'
GROUP BY 1;
```

### Query 3 — First same-agent TQC visit booked (Track 3)

```sql
SELECT
    sk_user,
    ts_first
FROM dw_agent_performance.dim_agent_milestone
WHERE milestone_type = 'TQC_VB_SAME_AGENT';
```

### Query 4 — CIQ portfolio loss (Compra de Carteira)

Current-state rows flagged by either portfolio-loss rule on the DW fact. Use `portfolio_loss_reason` to see which rule fired.

```sql
SELECT
    f.sk_house,
    f.sk_house_listing,
    f.sk_partner,
    f.listing_category,
    f.listing_status,
    f.total_days_since_publish,
    f.ts_publicated,
    f.is_paid,
    f.ts_contract_signed,
    f.is_portfolio_loss,
    f.portfolio_loss_reason
FROM dw_ciq.fact_ciq_listing_purchase AS f
WHERE f.is_portfolio_loss = true;
```

> For ad-hoc checks on enrich inputs only, the 90-day rule is `listing_category = 'Re-Listing'` + `listing_status IN ('PUBLISHED', 'PUBLICADO')` + `ts_contract_signed IS NULL` + `total_days_since_publish > 90` on `datalake_ciq.ciq_listing_purchase` — prefer the DW fact.
