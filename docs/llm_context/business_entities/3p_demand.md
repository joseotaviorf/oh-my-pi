# 3P Demand

## Overview

3P Demand is the **demand-side** sub-funnel of QuintoAndar's Marketplace (Broker XP) — the journey of a buyer / tenant brought into the platform by a partner imobiliária. Two business models live under it:

- **3P Demand** (**TSC — Traga Seus Clientes**): the partner brings the buyer and the partner's 3P agent works the funnel through to closing. Flag: `is_3p_demand = TRUE`.
- **3P Lead Gen** (**CQA — Clientes QuintoAndar**): QuintoAndar generates the lead from its own traffic and hands it off to a partner's passive-lead-receiver agent. Flag: `is_3p_lead_gen = TRUE`.

This entity drills **For Sale** (Visit → Offer → CCV) where the data model is rich and 3P attribution is consistent across the stack. For Rent is covered in the appendix — the warehouse currently exposes 3P Demand attribution only via the combined Visit / Booking layers, not via the Rent offer or rent-flow facts.

**Entry rule.** A buyer becomes a 3P **Buyer Prospect** only after **at least one scheduled visit (booking)** materialises the prospect window. The window itself lives in `dw_sale.dim_buyer_prospect_3p_history` and is the **top of funnel** of every 3P Demand analysis — without it, you are reading downstream Visit / Offer aggregates, not a prospect-anchored funnel.

**Pre-booking visibility is out of scope here.** Everything that happens *before* the first booking on a 3P listing — search-result exposure, Listing Page Viewed events, daily-published demand snapshots, listing publication / unpublication timeline — is covered in [`broker_xp.md`](./broker_xp.md), section *"Listings — Visibility and Demand on 3P Supply"*. The 3P Demand funnel modelled here picks up at the **Buyer Prospect Window** (Top of Funnel), which is materialised by the first booking; the visibility funnel that feeds it lives upstream in that doc.

For the umbrella view of Marketplace, broker modelling, agents 3P, business-model matrix, and cross-entity 3P identification, see [`broker_xp.md`](./broker_xp.md). For the supply-side counterpart (3P partner inventory from BSP to first listing), see [`3p_supply.md`](./3p_supply.md). This entity is the demand sub-funnel of the same Marketplace.

## Default scope rule — three flags by default

**When the user asks for "3P Demand indicators" without specifying a subset, the default analytical scope spans the three Marketplace flags:**

```sql
is_3p_demand = TRUE OR is_3p_lead_gen = TRUE OR is_3p_supply = TRUE
```

Operationally, the team treats the 3P Demand funnel as **any Marketplace-touched transaction** — whether the partner brought the buyer (`is_3p_demand` / TSC), QuintoAndar handed off a 1P-sourced lead to the partner (`is_3p_lead_gen` / CQA), or the listing itself is from a partner and the demand was worked by a 1P agent (`is_3p_supply` / `BM_3P_SUPPLY_1P_DEMAND_AGENT`). Restricting to only `is_3p_demand OR is_3p_lead_gen` (i.e. dropping `is_3p_supply`) excludes the supply-only configurations and **underestimates** every demand-funnel headline metric (visits, offers, CCVs).

### When to broaden vs. narrow

- **Default (broaden)** — apply the three-flag `OR` whenever the question is phrased generically: "% de visitas 3P", "CCVs do 3P", "funil de demanda 3P do mês". No further qualification means all three.
- **Narrow only when the user is explicit** — "só Lead Gen", "apenas TSC / 3P Demand", "excluir is_3p_supply", "comparar Demand vs Lead Gen": apply only the requested flag(s).
- **Two-flag legacy default (`is_3p_demand OR is_3p_lead_gen`) is the strict demand-broker side** — keep it only when the question requires attribution to the demand-side broker that brought the buyer. See structural exceptions below.

### Structural exceptions — when the broad scope does not apply mechanically

Two analyses cannot mechanically include `is_3p_supply`-only rows, even under the default scope:

1. **Buyer Prospect Window analyses** (`dw_sale.dim_buyer_prospect_3p_history`). The table is constructed only from demand-side events — `demand_type ∈ {'3P_DEMAND', '3P_LEAD_GEN'}`. There is **no `3P_SUPPLY` demand_type**, so NBP / RBP / window-anchored metrics are inherently demand-broker-side. Do not try to bolt `is_3p_supply` on top of this table; instead, when an analysis genuinely needs the broader scope, anchor on `fact_visits` / `fact_offers` rather than on the prospect window.
2. **Demand-broker-side aggregations** (`GROUP BY sk_broker_demand`). Rows that are `is_3p_supply = TRUE AND is_3p_demand = FALSE AND is_3p_lead_gen = FALSE` carry `sk_broker_demand = -1` by construction (the demand side is 1P — there is no demand-side broker). Including those rows in a per-broker-demand aggregation collapses them under the sentinel `-1` group, which is meaningless. Two valid responses: either keep the demand-side scope (two flags) and document the choice in the answer, or shift the aggregation grain to `sk_broker_supply` / `business_model` when the question genuinely needs the broader matrix.

When in doubt, default to the **broad three-flag scope at transaction grain**, and explicitly call out in the answer whether the analysis required dropping back to the two-flag scope (with the structural reason). The Identifying section below restates this rule operationally.

## Glossary and Synonyms

- **3P Demand**, **TSC**, **Traga Seus Clientes** → partner brings the buyer/tenant. Flag: `is_3p_demand = TRUE`.
- **3P Lead Gen**, **CQA**, **Clientes QuintoAndar** → 1P-sourced lead handed off to a partner. Flag: `is_3p_lead_gen = TRUE`.
- **Buyer Prospect** → For Sale demand-side prospect — a buyer who has at least one scheduled visit in the 3P funnel. Tracked in `dw_sale.dim_buyer_prospect_3p_history`.
- **NBP**, **New Buyer Prospect** → first episode for that `(sk_buyer, demand_type)`. `buyer_prospect_type = 'NBP'`.
- **RBP**, **Recovery Buyer Prospect** → reactivation episode after ≥ 90 idle days for the same `(sk_buyer, demand_type)`. `buyer_prospect_type = 'RBP'`.
- **Buyer Prospect Window** → the open interval `(ts_started, COALESCE(ts_ended, NOW()))` per `(sk_buyer, demand_type, version)` — the time bucket inside which downstream visits / offers attribute to that prospect episode.
- **Booking**, **agendamento** → entry into the funnel; one row per booking in `dw_public.dim_booking`. Includes Visita, Vistoria, SessaoFotos, CheckUpLar — only `type = 'Visita'` is relevant for 3P Demand.
- **Visit Booked (VB)** → booking created with `type = 'Visita'`. Timestamp `fact_visits.ts_booking_created`.
- **Visit Confirmed** → owner / tenant living / agent confirmed the visit. `dim_visit.is_visit_confirmed`, `dim_visit.ts_visit_first_confirmed`.
- **Visit Completed (VC)** → visit was successfully completed. `fact_visits.ts_visit_completed IS NOT NULL` (or boolean on `dim_visit.is_visit_completed`).
- **Visit Cancelled (BC)** → booking-level cancellation. `fact_visits.ts_visit_canceled IS NOT NULL` (or `dim_visit.is_visit_canceled`).
- **Visit Unsuccessful** → visit happened but did not conclude with success (entrance blocked, parties did not show up, etc.). `dim_visit.is_visit_unsuccessful`, `dim_visit.ts_visit_unsuccessful`.
- **Visit Stalled** → visit stuck without a terminal outcome. `dim_visit.is_visit_stalled`, `dim_visit.ts_visit_stalled`.
- **Visit Schedule** → an attempt to confirm a visit slot; a visit can have multiple schedules (reschedules). `dw_visit.fact_visit_schedules`.
- **Sale Flow** → buyer × house interaction set. `sk_sale_flow` on `fact_visits` / `fact_offers`.
- **Offer**, **proposta** → buyer's purchase proposal. `dw_sale.fact_offers`. Submitted with `ts_offer_submitted`.
- **OS**, **Offer Submitted** → first event of the OFFER stage. **Primary source: `fact_offers.ts_offer_submitted`**; abbreviation `OS` in `dim_sale_event_type` is the naming convention only.
- **OA**, **Offer Accepted** → owner accepted. **Primary source: `fact_offers.ts_offer_accepted`**; abbreviation `OA` in catalog.
- **OR**, **Offer Rejected** ≡ **Offer Dismissed** → the underlying data lives in **`fact_offers.ts_offer_dismissed`**; the catalog event in `dim_sale_event_type` is `OFFER_REJECTED` (abbreviation `OR`). Treat *rejected* and *dismissed* as synonyms — the catalog uses *rejected*, the fact uses *dismissed*.
- **Offer Rescued** → cancelled offer re-opened. `ts_offer_rescued`, `is_a_rescued_offer = TRUE`.
- **Offer Cancelled** → cancelled before acceptance or post acceptance. `ts_offer_canceled`.
- **SAC**, **Sale Agreement Created** → CCV draft created. **Primary source: `fact_offers.ts_sale_agreement_created`**; abbreviation `SAC` in catalog.
- **CCV**, **Compromisso de Compra e Venda**, **Sale Agreement Signed** → terminal success event. **Primary source: `fact_offers.ts_sale_agreement_signed`**; abbreviation `CCV` in catalog. Detail attributes on `dw_sale.dim_sale_agreement`.
- **Sale Agreement Cancelled** → CCV cancelled after creation. `ts_sale_agreement_canceled`, `is_ccv_canceled = TRUE`.
- **`sk_broker_demand`** → broker on the demand side (brought the buyer). Populated when `business_model` contains `3P_DEMAND` or `3P_LEAD_GEN`; `-1` otherwise. JOIN with `dw_brokers.dim_broker.sk_broker`.
- **`sk_broker_supply`** → broker on the supply side (owns the listing). Populated when `business_model` contains `3P_SUPPLY`. Relevant here to identify cross-broker transactions (`BM_3P_DEMAND_3P_SUPPLY`).
- **Buyer Intention** → `dim_booking.buyer_intention`: `LIVING` (will live in), `INVESTMENT_FOR_RENT` (will rent out), `INVESTMENT_OTHER` (other investment).
- **Hub** / **Central** / **Deal Making (DM)** → negotiation models that produced the offer. `dim_sale_agreement.offer_flow`, `dim_offer.offer_flow`.
- **Closing Specialist** → closing analyst working the CCV. `fact_offers.sk_closing_specialist`.
- **Visit Follow-up** → agent's perception of buyer's next action after a completed visit. `dim_booking.visit_follow_up`: `VaiNegociar`, `Talvez`, `NaoGostou`, `NaoCompareceu`, `ImovelAlugado`, `EntradaNaoAutorizada`, `VisitouSozinho`.

## The 3P Demand funnel — sub-stages

### Top of funnel — Buyer Prospect Window (NBP / RBP)

The funnel **opens** when a buyer's first booking (visit) of the period materialises a prospect window in `dim_buyer_prospect_3p_history`:

```
[Buyer Prospect Window Opens]                       ← dim_buyer_prospect_3p_history.ts_started
   |  classification: demand_type ∈ {3P_DEMAND, 3P_LEAD_GEN}
   |  type: NBP  (first episode of the buyer in that demand_type)
   |        RBP  (reactivation after ≥ 90 idle days for that demand_type)
   |  attribution: sk_broker = demand-side broker that opened the window
   |  source: event_source ∈ {VISIT, BUYER_COMPANY_RELATION}
   ↓ (materialised by the first booking inside the window)
```

The window stays open until a subsequent NBP / RBP event for the same `(sk_buyer, demand_type)` supersedes it (`ts_ended` filled). A single buyer can have multiple windows over their lifetime — one NBP plus N RBPs per demand_type. **The Buyer Prospect Window opening has no equivalent timestamp on `fact_visits` / `fact_offers`** (and is not represented in the optional event-grain `fact_sale_demand_event` either) — always use `dim_buyer_prospect_3p_history.ts_started` as the ToF synthetic event in funnel analyses.

### Visit sub-stages

```
[Visit Requested]                       (dim_visit.ts_visit_requested)
        ↓
[Visit Booked (VB)]                     (fact_visits.ts_booking_created, abbreviation 'VB')
        ↓ confirmations
[Supply / Demand / Agent / Tenant Answers]  (dim_visit.ts_visit_supply_answer, ts_visit_demand_answer,
                                             ts_visit_agent_answer, ts_visit_tenant_answer,
                                             first_supply_answer, first_tenant_living_answer)
        ↓
[Visit First Confirmed]                 (dim_visit.ts_visit_first_confirmed, visit_first_confirmed_channel,
                                         visit_first_confirmed_user_role)
        ↓  0..N reschedules            (fact_visit_schedules; dim_visit.ts_visit_first_rescheduled,
                                         ts_visit_last_rescheduled, nbr_reschedule)
[Visit Last Confirmed]                  (dim_visit.ts_visit_last_confirmed)
        ↓
[Visit Check-in]                        (fact_visits.ts_visit_checkin — For Sale only;
                                         dim_booking.visit_checkin_status, checkin_fail_reason)
        ↓
[Visit Performed]                       (dim_booking.performed; visitor_arrived / agent_arrived /
                                         owner_arrived; successful_entrance)
        ↓
[Visit Completed (VC)] ✓                (dw_sale.fact_visits.ts_visit_completed; dim_visit.is_visit_completed;
                                         abbreviation 'VC')
   OR
[Visit Cancelled (BC)]                  (dw_sale.fact_visits.ts_visit_canceled; dim_visit.is_visit_canceled;
                                         abbreviation 'BC')
   OR
[Visit Unsuccessful]                    (dim_visit.is_visit_unsuccessful, dim_visit.ts_visit_unsuccessful)
   OR
[Visit Stalled]                         (dim_visit.is_visit_stalled, dim_visit.ts_visit_stalled)
        ↓
[Post-Visit Evaluation]                 (dim_post_visit_demand — agent_rating, house_rating, etc.)
[Visit Follow-up]                       (fact_visits.ts_visit_follow_up; dim_booking.visit_follow_up)
```

**Cancelled vs Unsuccessful vs Stalled — three distinct outcomes.** All three are non-completion endings but they describe different operational realities:

- **Cancelled (BC)** — the visit was **explicitly cancelled** before it happened (booking cancellation flow). `dim_visit.is_visit_canceled = TRUE`. The reason taxonomy is in `dim_booking` (free-text and category) and `dim_visit` (structured, via `dim_cancellation_type`).
- **Unsuccessful** — the visit **happened but did not conclude with success**: entrance was blocked (no keys, wrong lock, unauthorised entry), one of the parties did not show up, the wrong address was on the listing, etc. `dim_visit.is_visit_unsuccessful = TRUE`. Diagnostic columns: `dim_booking.troublesome_entrance`, `dim_booking.visit_follow_up`.
- **Stalled** — the visit got stuck without reaching a terminal status: no cancellation, no completion, no unsuccessful flag. `dim_visit.is_visit_stalled = TRUE`. Indicates operational follow-up debt; relatively rare but important for QA on broker demand performance.

### Offer sub-stages

```
[Booking + Visit Completed]             (pre-requisite for most offers, but not all;
                                         fact_offers.has_completed_visit_before_offer / has_booking_before_offer)
        ↓
[Offer Submitted (OS)]                  (fact_offers.ts_offer_submitted, abbreviation 'OS';
                                         dim_offer.offer_status = 'Offer Sent')
        ↓ iterative negotiation
[Negotiation Rounds]                    (first_price_offered_by_buyer → last_price_offered_by_buyer;
                                         first_discount_proposed → last_discount_proposed;
                                         has_used_negotiation_chat;
                                         dim_offer.offer_status transitions:
                                         'Chat em branco', 'Contra Buyer', 'Contra Seller',
                                         'Stand By', 'Sem Contato - Buyer', 'Sem Contato - Seller',
                                         'OA em validação', 'Offer validated')
        ↓
[Offer Accepted (OA)]                   (fact_offers.ts_offer_accepted, abbreviation 'OA';
                                         dim_offer.offer_status = 'Offer Accepted')
   OR
[Offer Rejected (OR) ≡ Dismissed]       (fact_offers.ts_offer_dismissed, abbreviation 'OR';
                                         dim_offer.offer_status = 'Offer Rejected' or 'Descarte Pós Aceite';
                                         drop_reason, drop_reason_responsible)
[Offer Cancelled]                       (fact_offers.ts_offer_canceled)
[Offer Rescued]                         (fact_offers.ts_offer_rescued, dim_offer.is_a_rescued_offer = TRUE)
        ↓
[Sale Agreement Drafted]                (fact_offers.ts_sale_agreement_drafted;
                                         dim_sale_agreement.sale_agreement_status = 'Forms enviado')
        ↓
[Sale Agreement Created (SAC)]          (fact_offers.ts_sale_agreement_created, abbreviation 'SAC';
                                         dim_sale_agreement.sale_agreement_status = 'Enviar para Fila de CCV')
        ↓
[Sale Agreement Signed (CCV)] ✓         (fact_offers.ts_sale_agreement_signed, abbreviation 'CCV';
                                         dim_sale_agreement.sale_agreement_status = 'Assinado')
   OR
[Sale Agreement Cancelled]              (fact_offers.ts_sale_agreement_canceled;
                                         dim_sale_agreement.is_ccv_canceled = TRUE;
                                         sale_agreement_cancellation_reason ∈ {Buyer Desistiu, Seller Desistiu,
                                         Reprovado Crédito, Reprovado Diligência, Modelo QA, COVID, Não se Aplica})
[CCV Rescued]                           (dim_sale_agreement.is_a_rescued_ccv = TRUE)
```

### Visit timeline tables (audit / reschedule)

When the funnel question requires reconstructing a visit's full timeline or counting reschedules, two granular fact tables back the visit core:

- **`dw_visit.fact_visit_events`** — 1 row per visit status event. Joins with `dim_event_type`, `dim_author_type`, `dim_cancellation_type`. Carries `sk_broker_supply`, `sk_broker_demand`, `is_3p_supply/demand/lead_gen`, `minutes_between_last_event`, `hours_between_last_event`. Useful for *event-level timeline reconstruction* — e.g. "what happened to this visit and in what order".
- **`dw_visit.fact_visit_schedules`** — 1 row per visit schedule. A visit with reschedules has N rows in this table. Carries `is_booking`, `is_reschedule`, `is_confirmed`, `is_completed`, `is_canceled`, `is_unsuccessful`, plus `sk_succeed_schedule` (the next schedule when this one is rescheduled). Useful for *reschedule-rate analysis* and *schedule-grain timing metrics*.

Both tables carry the 3P broker keys and flags, so they can be filtered for 3P Demand directly. They are **orthogonal** to `fact_visits` (which is visit-grain) — keep them for diagnostic deep dives, not for headline metrics.

### Canonical events catalog

The 3P Demand funnel has **8 canonical events** across 3 stages. **The canonical source for every event is the corresponding timestamp column on `dw_sale.fact_visits` or `dw_sale.fact_offers`** — that is the primary path for all funnel analyses. The catalog dimension `dw_sale.dim_sale_event_type` is used only for naming convention (abbreviation, stage label); it does not hold any quantitative data.

**De/para — event → source fact / column:**

| `abbreviation` | `event_name` | `stage` | Source fact | Source timestamp |
|---|---|---|---|---|
| `VB` | `VISIT_BOOKED` | BOOKING | `dw_sale.fact_visits` | `ts_booking_created` |
| `VC` | `VISIT_COMPLETED` | BOOKING | `dw_sale.fact_visits` | `ts_visit_completed` |
| `BC` | `VISIT_CANCELLED` | BOOKING | `dw_sale.fact_visits` | `ts_visit_canceled` |
| `OS` | `OFFER_SUBMITTED` | OFFER | `dw_sale.fact_offers` | `ts_offer_submitted` |
| `OA` | `OFFER_ACCEPTED` | OFFER | `dw_sale.fact_offers` | `ts_offer_accepted` |
| `OR` | `OFFER_REJECTED` | OFFER | `dw_sale.fact_offers` | `ts_offer_dismissed` (synonym, see Glossary) |
| `SAC` | `SALE_AGREEMENT_CREATED` | CLOSING | `dw_sale.fact_offers` | `ts_sale_agreement_created` |
| `CCV` | `SALE_AGREEMENT_SIGNED` | CLOSING | `dw_sale.fact_offers` | `ts_sale_agreement_signed` |

All eight rows carry `is_3p_supply` / `is_3p_demand` / `is_3p_lead_gen` and `sk_broker_supply` / `sk_broker_demand` directly on `fact_visits` and `fact_offers` — no JOIN to a separate event-grain fact is needed for 3P attribution.

**Events that exist as `fact_offers` timestamps but are NOT in this catalog** — `ts_offer_rescued`, `ts_offer_canceled`, `ts_sale_agreement_drafted`, `ts_sale_agreement_canceled`. Query `fact_offers` directly for these.

**Buyer Prospect Window opening (ToF) is also NOT in this catalog.** Combine `dim_buyer_prospect_3p_history.ts_started` with the source-fact timestamps above when building end-to-end funnel views.

**Optional event-grain fallback.** `dw_sale.fact_sale_demand_event` materialises the 8 events above as long-format rows (1 row per `(visit, event_type)` or `(offer, event_type)`) and JOINs to `dim_sale_event_type`. **Treat it as a fallback** for scans that need to cross multiple stages without manually unpivoting timestamps — most analyses are simpler and faster against `fact_visits` / `fact_offers` directly. See section **5.4 Event bridges** below.

## Bridges (JOIN keys)

### 5.1 Buyer Prospect bridges (ToF)

The Buyer Prospect window is the funnel entry — every downstream fact aggregation that wants to attribute to a 3P prospect episode must pass through it.

- **Prospect window ↔ Visits**: `dim_buyer_prospect_3p_history.sk_buyer = dw_sale.fact_visits.sk_buyer`, **with window match** — the visit's `ts_booking_created` (or `ts_visit_completed`) must fall within `(ts_started, COALESCE(ts_ended, NOW()))`. Additionally, the visit's flag must align with `demand_type`:
  - `demand_type = '3P_DEMAND'` ↔ `fact_visits.is_3p_demand = TRUE`
  - `demand_type = '3P_LEAD_GEN'` ↔ `fact_visits.is_3p_lead_gen = TRUE`
- **Prospect window ↔ Offers**: same pattern with `dw_sale.fact_offers.sk_buyer` and `ts_offer_submitted`.
- **Prospect window ↔ Broker**: `dim_buyer_prospect_3p_history.sk_broker = dw_brokers.dim_broker.sk_broker` (demand-side broker that opened the window). **Do not** confuse this with `fact_visits.sk_broker_demand` / `fact_offers.sk_broker_demand` — those reflect the broker on the demand side of each specific transaction and may change over the life of a prospect window if the buyer transfers between partners.
- **Prospect window ↔ Buyer aggregate**: `dim_buyer_prospect_3p_history.sk_buyer = dw_sale.fact_buyer_prospects.sk_buyer`. `fact_buyer_prospects` covers **every** buyer with at least one booking or offer (not just 3P); combine with `dim_buyer_prospect_3p_history` to isolate the 3P universe.

**Critical rule.** For any aggregation "per 3P buyer prospect", the minimal filter set on `dim_buyer_prospect_3p_history` is `sk_broker <> -1` **and** the window temporal match **and** the `demand_type` consistency with the downstream fact's 3P flag.

### 5.2 Visit bridges

- **Booking ↔ Visits (For Sale)**: `dw_public.dim_booking.sk_booking = dw_sale.fact_visits.sk_booking`. 1:1 when `dim_booking.type = 'Visita'` and `visit_intent = 'SALE'`. Booking is the parent universe (also covers Vistoria, SessaoFotos, CheckUpLar); visit is the For-Sale specialisation.
- **Booking ↔ Visits (combined)**: `dim_booking.sk_booking = dw_visit.fact_visits.sk_booking`. Same 1:1 cardinality but covers Sale and Rent.
- **Visit ↔ Visit attributes**: `dw_visit.fact_visits.sk_visit = dw_visit.dim_visit.sk_visit`. 1:1. Descriptive attributes — cancellation taxonomy, visit model, behaviour, channels, supply / demand / agent / tenant answer timestamps.
- **Visit ↔ Schedules**: `dw_visit.fact_visits.sk_visit = dw_visit.fact_visit_schedules.sk_visit`. 1:N — reschedules generate multiple schedule rows.
- **Visit ↔ Events**: `dw_visit.fact_visits.sk_visit = dw_visit.fact_visit_events.sk_visit`. 1:N — granular event-level audit trail.
- **Visit ↔ Post-visit eval**: `dw_visit.fact_visits.sk_visit = dw_visit.dim_post_visit_demand.sk_visit`. 1:1 when the visit was evaluated (LEFT JOIN).
- **Visit ↔ Visit funnel milestones**: `dw_visit.fact_visits.sk_visit = dw_visit.dim_visit_funnel.sk_visit`. 1:N — one row per `(event_code, business_context)` where `event_code ∈ {os, oa, cs}`. Combines For Sale and For Rent visit milestones; **for For Sale-only funnels prefer `dw_sale.fact_visits` + `dw_sale.fact_offers` timestamps directly** (see the canonical event catalog above). `dim_visit_funnel` is the right path when the analysis must span Sale and Rent together. The general Visit-domain coverage (lifecycle, schedules, cancellation reasons, post-visit feedback) is in [`visits.md`](./visits.md).

### 5.3 Offer bridges

- **Visits ↔ Offers**: `dw_sale.fact_visits.sk_booking = dw_sale.fact_offers.sk_booking`. **1:N**: a booking can produce multiple offers. `fact_visits.sk_offer` carries only the **first** offer associated with the booking — use it for visit-grain summaries, but **never** as a substitute for the full `fact_offers` JOIN in offer-grain analyses.
- **Offer ↔ Offer attributes**: `dw_sale.fact_offers.sk_offer = dw_sale.dim_offer.sk_offer`. 1:1. Descriptive attributes — offer_status, drop_reason, drop_reason_responsible, is_a_rescued_offer.
- **Offer ↔ Sale Agreement (CCV)**: `dw_sale.fact_offers.sk_offer = dw_sale.dim_sale_agreement.sk_offer`. 1:1 when the offer reached the sale-agreement stage; LEFT JOIN otherwise. **CCV is offer-grain** — the same `sk_offer` carries both the offer and its CCV attributes.
- **Offer ↔ Buyer aggregate**: `dw_sale.fact_offers.sk_buyer = dw_sale.fact_buyer_prospects.sk_buyer`. N:1.

### 5.4 Event bridges (optional event-grain fallback)

**Primary path: `fact_visits` and `fact_offers` directly.** Both facts carry every event of the canonical catalog as a column (see the de/para table above), plus `is_3p_*` and `sk_broker_*` columns — most cross-stage analyses are simpler and faster against them, JOINed by `sk_booking` (Visit ↔ Offer 1:N) or `sk_buyer` (buyer-grain). The event-grain fact below is a long-format projection of those same timestamps, kept as a fallback for queries that benefit from an unpivoted layout.

- **Visits / Offers ↔ Event-grain (fallback)**: `dw_sale.fact_sale_demand_event.sk_visit = dw_sale.fact_visits.sk_visit` for `VB / VC / BC`; `fact_sale_demand_event.sk_offer = fact_offers.sk_offer` for `OS / OA / OR / SAC / CCV`. 1 row per `(visit, event_type)` and `(offer, event_type)`. Use when the question genuinely needs cross-stage rows without manually unpivoting timestamps — for example, "average minutes between any two events" or "share of visits that reached event X" across many stages at once.
- **Event-grain ↔ Catalog**: `fact_sale_demand_event.sk_event_type = dim_sale_event_type.sk_event_type`.
- **Event-grain ↔ Brokers**: `fact_sale_demand_event.sk_broker_supply / sk_broker_demand` → `dw_brokers.dim_broker.sk_broker`. Same flags `is_3p_supply/demand/lead_gen` are present here as well, mirroring the source facts.

### 5.5 Broker bridges (demand and supply sides)

- **Demand side**: `fact_visits.sk_broker_demand = fact_offers.sk_broker_demand = dw_brokers.dim_broker.sk_broker` (and `fact_sale_demand_event.sk_broker_demand` carries the same key when the event-grain fallback is used). Prefer `fact_visits` / `fact_offers` for 3P Demand and 3P Lead Gen analyses.
- **Supply side**: same pattern with `sk_broker_supply`. Relevant for 3P Demand only when the transaction is also 3P Supply (`BM_3P_DEMAND_3P_SUPPLY`, `BM_3P_DEMAND_3P_SUPPLY_6P`).
- **Prospect window broker**: `dim_buyer_prospect_3p_history.sk_broker` is **demand-side by construction** — it is the broker that opened the prospect's window. Do not treat it as supply.

Full broker context (products, status / tier / account-manager history, agents 3P, the eight-row `business_model` matrix) lives in [`broker_xp.md`](./broker_xp.md).

## Tables

| You need... | Use this table |
|-------------|----------------|
| Buyer Prospect 3P windows (NBP / RBP, demand_type, demand-side broker, episode start / end) — **ToF central** | `dw_sale.dim_buyer_prospect_3p_history` — SCD2 per `(sk_buyer, demand_type)`. Filter `is_current = TRUE` for the open window or temporally with `ts_started`/`ts_ended`. |
| Visit metrics with 3P attribution (booking → visit completed) — **Visit central** | `dw_sale.fact_visits` (DAG `dw_sale_visits`) — 1 row per For Sale visit booking. Carries `sk_broker_supply`, `sk_broker_demand`, `is_3p_supply/demand/lead_gen`, `hours_booking_to_offer`, `hours_visit_to_offer`, hub / virtual / rented flags, secretariat keys. |
| Offer metrics with 3P attribution (OS → OA → SAC → CCV) — **Offer central** | `dw_sale.fact_offers` (DAG `dw_sale_offers`) — 1 row per offer. Carries `sk_broker_supply`, `sk_broker_demand`, `is_3p_supply/demand/lead_gen`, `is_buyer_first_offer`, `is_house_first_offer`, `has_completed_visit_before_offer`, brokerage_fee, sale_price_agreed, and the full negotiation timestamp set. |
| Descriptive attributes of an offer (status, drop reason, negotiation flags) | `dw_sale.dim_offer` — `offer_status` (17 categorical states), `drop_reason` (free text), `drop_reason_responsible` (Buyer / Seller / Other), `is_a_rescued_offer`. |
| Sale Agreement (CCV) attributes | `dw_sale.dim_sale_agreement` — `ccv_type`, `sale_agreement_status` (`Assinado` / `Enviar para Fila de CCV` / `Forms enviado`), `offer_flow` (Hub / Deal Making / Central), `payment_method`, `credit_model`, `closing_status`, diligence statuses, `sale_agreement_cancellation_reason`, `is_ccv_canceled`, `is_a_rescued_ccv`. **Carries `is_3p_supply` and `is_3p_demand` but NOT `is_3p_lead_gen`.** |
| Buyer-level OBT (every buyer with at least one booking / offer, with per-stage counts and time-diffs) | `dw_sale.fact_buyer_prospects` — buyer-grain. `bookings_created`, `visits_completed`, `offers_submitted`, `offers_accepted`, `sale_agreements_signed`, `further_funnel_step`, `days_first_*_to_*`, `avg_offer_price`, `avg_offer_discount`, `first_buyer_intention`. Covers all buyers, not just 3P — cross with `dim_buyer_prospect_3p_history` to isolate 3P. |
| Buyer prospect type catalog | `dw_sale.dim_buyer_prospect_type` — buyer prospect type metadata (NBP / RBP), city_group, price_segment. |
| Event-grain unified funnel (For Sale) — **fallback / advanced** | `dw_sale.fact_sale_demand_event` — long-format projection of `fact_visits` / `fact_offers` timestamps (1 row per event). Carries `is_3p_supply/demand/lead_gen`, `sk_broker_supply/demand`. **Prefer querying `fact_visits` + `fact_offers` directly**; reach for this fact only when the question benefits from an unpivoted cross-stage layout. |
| Event type catalog (naming convention) | `dw_sale.dim_sale_event_type` — 8 canonical events (VB, VC, BC, OS, OA, OR, SAC, CCV) across 3 stages. **Reference for abbreviations and stage labels only** — no quantitative data; the underlying timestamps live on `fact_visits` / `fact_offers`. |
| Booking universe (Visita + Vistoria + Foto + CheckUpLar) | `dw_public.dim_booking` — only `type = 'Visita'` is in scope for Demand. Carries `is_3p_supply/demand/lead_gen`, `partner_3p_supply`, `partner_3p_demand`, `buyer_intention`, full marketing taxonomy. |
| Post-visit qualitative feedback (rating of agent and house) | `dw_visit.dim_post_visit_demand` — 1 row per evaluated visit. `agent_rating` (1–5), `house_rating` (yes / partially / no), category fields (`agent_punctuality`, `agent_house_features_knowledge`, etc.). |
| Visit attributes (cancellation taxonomy, supply / demand answers, visit model) | `dw_visit.dim_visit` — covers Sale + Rent. Filter `business_context = 'SALE'` for For Sale. |
| Cancellation reason catalog (structured) | `dw_visit.dim_cancellation_type` — 15 categories (`PERSON_NOT_INTERESTED_*`, `PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE`, `Request_expired`, etc.) — JOIN via `dim_visit.cancellation_type`. |
| Granular visit event timeline (audit trail) | `dw_visit.fact_visit_events` — 1 row per visit status event. Carries `sk_broker_supply/demand`, 3P flags, and `minutes_between_last_event`. |
| Visit schedule timeline (booking + reschedules) | `dw_visit.fact_visit_schedules` — 1 row per schedule per visit. Carries 3P flags and `is_reschedule`, `sk_succeed_schedule`. |
| Visit funnel milestones across modalities (OS / OA / CS only) | `dw_visit.dim_visit_funnel` — combined For Sale + For Rent. **For For Sale-only analyses prefer `dw_sale.fact_visits` + `dw_sale.fact_offers` timestamps directly** — this dim is the right path only when the analysis must span Sale and Rent together. |
| Combined Sale + Rent visit metrics (legacy path, still used for Rent) | `dw_visit.fact_visits` (DAG `dw_visit`) — covers both modalities. `is_3p_*` columns will be moved to `dw_visit.dim_visit` in the future (see Dos and Don'ts). Full Visit-domain coverage in [`visits.md`](./visits.md). |

**Critical rules:**
- **Visits ↔ Offers link by `sk_booking`, not `sk_visit`.** A booking can spawn multiple offers; `sk_visit` only narrows to a specific scheduling instance and breaks N:N analyses.
- **CCV is offer-grain.** There is **no** separate CCV fact — `dim_sale_agreement` is an attribute extension of `fact_offers.sk_offer` for offers that reached the agreement stage.
- **Buyer Prospect requires at least one scheduled visit.** `dim_buyer_prospect_3p_history` opens a window only after a visit-event materialises it. Buyers in pure browsing / sale-flow without a booking do not appear in this table — for that universe use `fact_buyer_prospects`.
- **Sentinel `-1` everywhere.** All `sk_*` columns use `-1` for unattributed. Filter `<> -1` when counting real entities.
- **Two brokers can co-exist on a transaction** (`sk_broker_supply` ≠ `sk_broker_demand` in `BM_3P_DEMAND_3P_SUPPLY` and `BM_3P_DEMAND_3P_SUPPLY_6P`). Decide upfront which side answers the question — never sum both columns without de-duplicating.
- **`dim_buyer_prospect_3p_history.sk_buyer_prospect` is NOT unique on its own** — it is `CONCAT(id_buyer, 0, version)` and version restarts per demand_type. Uniqueness grain is `(sk_buyer, demand_type, version)`.
- **`dim_sale_agreement` lacks `is_3p_lead_gen`.** To identify CCVs of 3P Lead Gen origin, bridge via `fact_offers.is_3p_lead_gen` on `sk_offer`.

## Buyer Prospects 3P (NBP / RBP)

The Buyer Prospect 3P entity is `dw_sale.dim_buyer_prospect_3p_history` — an SCD2 dimension that opens a **window** every time a buyer enters the 3P funnel for a given `demand_type`. Each row is one `(sk_buyer, demand_type, version)`; `version` restarts at 1 per `(sk_buyer, demand_type)`, ordered by `ts_started`.

**Classification:**

- **`buyer_prospect_type = 'NBP'`** (New Buyer Prospect) — the first window the buyer has ever opened in that `demand_type`. Always `version = 1`.
- **`buyer_prospect_type = 'RBP'`** (Recovery Buyer Prospect) — a subsequent window opened after the buyer has been **idle for ≥ 90 days** since their last event in that `demand_type`. `version ≥ 2`.

**`demand_type` values:**

- **`3P_DEMAND`** — sourced from `visits.business_model` containing `3P_DEMAND` (TSC).
- **`3P_LEAD_GEN`** — sourced from `visits.business_model` containing `3P_LEAD_GEN` (CQA).

**`event_source` values:**

- **`VISIT`** — window was opened by a `datalake_visit.visits` event (`event_type = 'VISIT_REQUESTED'`, `trigger_actor = 'AGENT'`). The vast majority of 3P Demand prospects originate here — the **first booking** is what materialises the window.
- **`BUYER_COMPANY_RELATION`** — window was opened by an upstream event on the rede platform's `buyer_company` stream (CRM-side prospect declaration).

**Window navigation:**

- `is_current = TRUE` — the open window. `ts_ended IS NULL` is equivalent.
- `version` — sequential, restarts per `(sk_buyer, demand_type)`. Use `MAX(version)` per pair for "latest window of this prospect on this demand_type".
- `(ts_started, COALESCE(ts_ended, NOW()))` — the time interval inside which downstream visits / offers attribute to this prospect episode.

**Broker attribution.** `dim_buyer_prospect_3p_history.sk_broker` is the demand-side broker that opened the window — sourced from `visits.sk_broker_demand` (VISIT branch) or `core_brokers.brokers.sk_broker` (BUYER_COMPANY_RELATION branch). Filter `<> -1` for real broker matches.

**Caveat — `is_buyer_first_offer` is NOT NBP.** `fact_offers.is_buyer_first_offer` marks the first-ever offer of the buyer's life (offer-grain, no window concept, no demand_type split). NBP marks the first **window** for the `(sk_buyer, demand_type)` pair, scoped to the 3P funnel. They answer different questions and should not be used interchangeably.

## Identifying 3P Demand transactions

Apply the same matrix as in [`broker_xp.md`](./broker_xp.md). **Default scope = three flags `OR`** (see "Default scope rule" above); narrow only when the user is explicit.

- **Default scope — full 3P Demand funnel** (broadest, the team's working definition): `is_3p_demand = TRUE OR is_3p_lead_gen = TRUE OR is_3p_supply = TRUE`. Captures every Marketplace-touched transaction.
- **Two-flag demand-broker side only** (use only when the question requires attribution to the demand-side broker that brought the buyer): `is_3p_demand = TRUE OR is_3p_lead_gen = TRUE`. Equivalent to `sk_broker_demand <> -1`.
- **3P Demand only** (TSC): `is_3p_demand = TRUE`.
- **3P Lead Gen only** (CQA): `is_3p_lead_gen = TRUE`.
- **3P Supply only — partner listing, 1P-worked demand** (`BM_3P_SUPPLY_1P_DEMAND_AGENT`): `is_3p_supply = TRUE AND is_3p_demand = FALSE AND is_3p_lead_gen = FALSE`. **Only meaningful at transaction grain** — these rows have `sk_broker_demand = -1` (no demand-side broker), so they cannot be attributed in a `GROUP BY sk_broker_demand` analysis.
- **3P Demand × 3P Supply combinations** (cross-broker transactions, `BM_3P_DEMAND_3P_SUPPLY` / `BM_3P_DEMAND_3P_SUPPLY_6P`): `is_3p_demand = TRUE AND is_3p_supply = TRUE` — carry both `sk_broker_supply` and `sk_broker_demand`. Same pattern for Lead Gen × Supply (`BM_3P_LEAD_GEN_3P_SUPPLY` / `_6P`).

**Where the flags live:**

- `dw_sale.fact_visits` — both flags present.
- `dw_sale.fact_offers` — both flags present.
- `dw_sale.dim_offer` — both flags present.
- `dw_sale.fact_sale_demand_event` — both flags present (event-grain).
- `dw_sale.dim_sale_agreement` — `is_3p_demand` present, `is_3p_lead_gen` **absent** (see CCV rule below).
- `dw_visit.fact_visits` / `fact_visit_events` / `fact_visit_schedules` / `dim_visit` — flags present.
- `dw_public.dim_booking` — flags present (`is_3p_demand`, `is_3p_lead_gen`).

**CCV of 3P Lead Gen.** `dim_sale_agreement` does not carry `is_3p_lead_gen`. To list CCVs of 3P Lead Gen origin, JOIN `dim_sale_agreement.sk_offer = fact_offers.sk_offer` and filter `fact_offers.is_3p_lead_gen = TRUE AND dim_sale_agreement.sale_agreement_status = 'Assinado'`.

## Coincident vs Cohort views of conversion

Every conversion metric in 3P Demand has **two valid measurement modes**. Pick the one that matches the business question — answers can differ dramatically, especially on recent periods.

### Coincident view (default for volume / operational dashboards)

Numerator and denominator events are counted **in the same calendar period** (month, week, day). Example for VB2VC in month X:

```
VB2VC_coincident(X) = COUNT(visits_completed in X) / COUNT(visits_booked in X)
```

- ✔ Fast, easy to read, lines up with operational reporting cycles.
- ✘ **Distorts conversion** when the stage transition crosses the period boundary — a visit booked on 31 Jan and completed on 1 Feb shows up in the denominator of January and the numerator of February, inflating Feb conversion and deflating Jan.
- Most current queries in this doc (Queries 1, 2, 5, 6, 7, 8) use this view. Use it for **share, volume, and per-broker dashboards** where the question is "what happened in the period".

### Cohort view (default for true conversion / retention behaviour)

Bucket the denominator by its **origin month** (the month in which the denominator event fired) and track the numerator as it accumulates across subsequent months from that origin. Example for VB2VC anchored on the booking month:

```
VB2VC_cohort(origin=X, by M_N) = COUNT(visits booked in X, where ts_visit_completed by end of X + N months) / COUNT(visits booked in X)
```

- ✔ True conversion behaviour — each origin cohort has a fixed denominator and the rate matures monotonically (cumulative) over M0, M1, M2, ...
- ✔ Reveals **time-to-convert** patterns and **stage-throughput stability** that the coincident view hides.
- ✘ More expensive to compute; output is a 2-D matrix instead of a single column.
- Use it for **conversion-rate analyses, A/B comparisons across cohorts, and any question of the form "of the X that happened in month M, what % converted by month M+N"**.

### Result-matrix layout

The canonical cohort output is a wide table: **rows = origin month of the denominator**, **columns = M0, M1, M2, ... (cumulative conversion by N months after origin)**, optional grouping dimension (3P configuration, broker, demand_type) stacks vertically next to origin month.

| origin_month | total_<denominator> | <metric>_m0 | <metric>_m1 | <metric>_m2 | <metric>_m3 | ... |
|---|---|---|---|---|---|---|
| 2025-10-01 | 1,200 | 0.65 | 0.78 | 0.82 | 0.83 | ... |
| 2025-11-01 | 1,350 | 0.62 | 0.75 | 0.80 | 0.82 | ... |
| 2025-12-01 | 1,420 | 0.61 | 0.74 | 0.79 | NULL | |
| 2026-01-01 | 1,500 | 0.63 | 0.76 | NULL | NULL | |
| 2026-02-01 | 1,580 | 0.64 | NULL | NULL | NULL | |

`M_N` semantics — **cumulative by default** (`M_N` = stage reached within N months after origin, inclusive). When the analysis explicitly needs the incremental contribution of a single month, use `M_N (incremental)` = `M_N − M_(N−1)` and label it as such.

### Right-censoring caveat (always disclose)

Recent cohorts cannot have their later columns populated yet — for an origin month M with N months between M and `current_date − 1 month`, only columns `M0..M_(N−1)` are observable; `M_N` and beyond are `NULL`. Always:

- Set `M_N` columns to `NULL` when `current_date < origin_month + N + 1 months`, not zero. A zero would falsely flatten the rate.
- Truncate the denominator window to **completed origin months** (`CAST(ts_<origin_event> AS DATE) < date_trunc('month', current_date)`) so the most recent in-flight month does not appear with an inflated 0% conversion.

### Stage transitions where the cohort view applies

The cohort pattern applies to **every conversion metric in the funnel**. The common transitions:

| Transition | Denominator | Numerator timestamp | Origin month source |
|---|---|---|---|
| **BP2VB** | NBP windows opened (`dim_buyer_prospect_3p_history` filtered to `buyer_prospect_type = 'NBP'`) | First `fact_visits.ts_booking_created` for the buyer after `ts_started` | `ts_started` |
| **VB2VC** | Visits booked (`fact_visits` filtered to `ts_booking_created IS NOT NULL`) | `fact_visits.ts_visit_completed` | `ts_booking_created` |
| **VC2OS** | Visits completed (`fact_visits` filtered to `ts_visit_completed IS NOT NULL`) | First `fact_offers.ts_offer_submitted` joined by `sk_booking` | `ts_visit_completed` |
| **OS2OA** | Offers submitted (`fact_offers`) | `fact_offers.ts_offer_accepted` | `ts_offer_submitted` |
| **OA2CCV** | Offers accepted (`fact_offers` filtered to `ts_offer_accepted IS NOT NULL`) | `fact_offers.ts_sale_agreement_signed` | `ts_offer_accepted` |
| **VB2CCV** (end-to-end) | Visits booked | `fact_offers.ts_sale_agreement_signed` joined by `sk_booking` | `ts_booking_created` |
| **NBP2CCV** (ToF end-to-end) | NBP windows | First `fact_offers.ts_sale_agreement_signed` for the buyer after `ts_started` | `ts_started` |

Apply the **default three-flag filter** (`is_3p_demand OR is_3p_lead_gen OR is_3p_supply`) on the source fact, exactly as in the coincident view. Demand-broker-grain cohorts retain the two-flag structural exception. **BP-anchored cohorts (BP2VB, NBP2CCV) inherit the demand-side-only construction of `dim_buyer_prospect_3p_history`** — no `is_3p_supply` scope there.

Worked SQL: **Query 10** (single-stage VB2VC cohort matrix as a template) and **Query 11** (NBP-anchored multi-stage cohort matrix VC / OS / CCV).

## Reasons, Cancellations and Drop Reasons

The funnel exposes outcome reasons at four levels. The taxonomy of each level is independent — a single transaction can carry a booking-level cancellation reason, a visit-level cancellation type, an offer drop reason, **or** a CCV cancellation reason depending on where it dropped.

### 9.1 Booking-level cancellations — `dw_public.dim_booking`

The widest taxonomy. Each cancelled booking carries:

- **`cancellation_reason`** — ~80 categorical values (the raw enum from the booking system). Examples: `CANCELED_BY_OWNER_FROM_APP`, `CANCELED_BY_TENANT_NOT_BUYING`, `CANCELED_AUTOMATICALLY_PROPERTY_UNPUBLISHED`, `CANCELED_HOUSE_OCCUPIED`, `KEY_HOLDER_AGENT_NOT_AVAILABLE`, `PROPERTY_UNPUBLISHED`, `RESCHEDULING_CONTRACT`, `RESCHEDULING_HOUSEFUL`. Use this for granular operational analysis.
- **`cancellation_reason_category`** — 11 macro buckets: `Agent`, `Owner`, `Tenant`, `Consequence Management`, `House Reserved`, `House Suspended`, `House Unlisted`, `Reschedule_Agent`, `Reschedule_Tenant`, `Other`, `Unknown`. Use this for aggregated drop-reason dashboards.
- **`responsible`** — 6 values: `Owner`, `Tenant`, `QuintoAndar`, `Reschedule`, `Other`, `Unknown`. Use this to split cancellations by accountable party.
- **`reason`** — free-text comment written by the agent in app. Useful for qualitative deep dives.
- **`troublesome_entrance`** — ~30 values describing why entry was blocked (unsuccessful visits): `LockboxProblems`, `KeysKeeperNotPresent`, `ResidentTenantDidntAllowVisit`, `RentedByAnotherCompany`, `WrongAddress`, `WrongPassword`, etc.

**Deprecated fields** (don't use for new analyses): `reason_category`, `visitor_missing_reason`, `agent_missing_reason`, `owner_missing_reason`.

### 9.2 Visit-level cancellations — `dw_visit.dim_visit` + `dw_visit.dim_cancellation_type`

The visit-level taxonomy is split between the legacy free-text path and the modern structured path:

- **Modern (data since 2024-11)** — JOIN `dim_visit.cancellation_type = dim_cancellation_type.sk_cancellation_type` to get the structured reason. The 15 enum values:
  - `PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT` — prospect lost interest in this specific property / visit, still searching.
  - `PERSON_SCHEDULED_FOR_ANOTHER_TIME` — already rescheduled.
  - `PERSON_CANNOT_ATTEND` — could not attend, still interested.
  - `PERSON_DOESNT_WANT_5A` — gave up on QuintoAndar entirely.
  - `VISIT_OCCURRED_AT_A_DIFFERENT_TIME` — visit happened off-schedule (e.g. with the agent at another moment).
  - `PERSON_IDENTIFIED_LISTING_AS_INACCURATE_OR_INCOMPLETE` — listing did not match expectations.
  - `PERSON_HAD_ISSUES_WITH_AGENT` — agent-related friction.
  - `QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES` — 5A failed to reach demand or supply.
  - `PROPERTY_TEMPORARILY_UNAVAILABLE` — temporary supply issue (renovation, travel).
  - `PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE` — terminal supply or demand exit (already sold, gave up).
  - `PROPERTY_ON_HOLD_FOR_ANOTHER_PROSPECT` — preference for another proposal.
  - `PROPERTY_RESERVED` — Rent-specific override.
  - `PERSON_DOESNT_WANT_TO_WORK_ON_THIS_LOCATION` — agent not assigned to the region.
  - `CONSEQUENCE_MANAGEMENT` — property / prospect / agent entered GC.
  - `AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT` — no available agent to take over.
  - `Request_expired` — confirmation time-out.
- **Legacy** — `dim_visit.cancellation_reason` (free text), `cancellation_on_behalf_of`, `cancellation_channel`. Available since 2016. Keep using for historical analyses pre-2024-11.
- **Author context (since 2024-11)** — `cancellation_author_role`, `first_supply_answer`, `first_supply_answer_channel`, `first_tenant_living_answer`, `first_tenant_living_answer_channel` — useful to attribute the cancellation to the right party and channel.

> **`dim_visit.unsuccessful_reason` — skipped here.** The metadata enum (`ASSISTED_ENTRANCE`, `EASY_ENTRANCE`, `NOT_CLASSIFIED`) appears out of date and does not match the operational unsuccessful taxonomy. For now, derive unsuccessful outcomes from `dim_visit.is_visit_unsuccessful = TRUE` together with `dim_booking.troublesome_entrance` and `dim_booking.visit_follow_up`. Re-validate the dim enum directly via Trino when the analysis depends on it.

### 9.3 Offer drop reasons — `dw_sale.dim_offer`

- **`offer_status`** — 17 categorical states the offer can sit in: `Offer Sent`, `Offer Accepted`, `Offer Rejected`, `OA em validação`, `Offer validated`, `Chat em branco`, `Contra Buyer`, `Contra Seller`, `Descarte Pós Aceite`, `Invalid Offer`, `Negociação fora do 5A`, `Não tratado`, `Sem Contato - Buyer`, `Sem Contato - Seller`, `Stand By`, `Corretor Vendedor`, `Teste Corretor`. Use this for negotiation-state analysis (where offers stall).
- **`drop_reason`** — free-text reason why the offer dropped before reaching the sale agreement. Drives qualitative drop analysis.
- **`drop_reason_responsible`** — 3 values: `Buyer`, `Seller`, `Other`.
- **`is_a_rescued_offer`** — boolean; TRUE when the offer was cancelled and re-opened later.

### 9.4 CCV-level cancellation — `dw_sale.dim_sale_agreement`

- **`sale_agreement_status`** — `Assinado` (signed CCV), `Enviar para Fila de CCV` (created, queued), `Forms enviado` (drafted), or empty / null.
- **`sale_agreement_cancellation_reason`** — 7 values: `Buyer Desistiu`, `Seller Desistiu`, `Reprovado Crédito` (credit denied), `Reprovado Diligência` (diligence failed), `Modelo QA` (QA model), `COVID`, `Não se Aplica`.
- **`closing_status`** — operational closing status (free text).
- **`house_dilligence_status` / `seller_dilligence_status` / `report_dilligence_status`** — diligence sub-statuses.
- **`is_ccv_canceled`**, **`is_a_rescued_ccv`** — boolean toggles.
- **`diligence_appointment_reason`** — appointment context for the diligence step.

### 9.5 Post-visit qualitative feedback — `dw_visit.dim_post_visit_demand`

Use this to assess broker-demand operational quality on 3P transactions (cross with `fact_visits.sk_broker_demand`):

- **Numerical** — `agent_rating` (1–5), free-text `agent_rating_comment` / `house_rating_comment`.
- **Categorical (GOOD / NEEDS_IMPROVEMENT)** — `agent_punctuality`, `agent_thoughtfulness`, `agent_house_features_knowledge`, `agent_rent_sale_process_knowledge`, `agent_get_in_touch`, `agent_other`, `agent_bypass_attempt`.
- **House evaluation** — `house_rating` (yes / partially / no), `house_location`, `house_conservation`, `house_neighborhood`, `house_cost_benefit`, `house_condominium_features`, `house_ad_discrepancies`.
- **Demand perspective on outcome** — `is_visit_completed_by_demand`, `is_visit_canceled_by_demand` (the buyer's view of whether the visit happened).
- **Scope** — `evaluation_domain` ∈ `AGENT_HOUSE`, `HOUSE`, `AGENT`.

## Key Metrics

Default 3P filter for every transaction-grain metric below: `is_3p_demand = TRUE OR is_3p_lead_gen = TRUE OR is_3p_supply = TRUE` (the broad scope from "Default scope rule"). Narrow only when the user asks for a specific flag.

**Two measurement modes per conversion metric** (see "Coincident vs Cohort views of conversion"):
- **Coincident** — same-period numerator and denominator. Default for volume / share / per-broker dashboards.
- **Cohort (M0, M1, M2, ...)** — denominator bucketed by origin month; numerator accumulates cumulatively across subsequent months. Default for true conversion-rate analyses. **Always disclose right-censoring on recent cohorts** (NULL the unobservable columns; truncate the last in-flight origin month). Worked patterns in Queries 10 and 11.

- **BP2VB (Buyer Prospect → first Visit Booked)** — denominator: NBP windows opened. Numerator: first `ts_booking_created` for the buyer after `ts_started`. **Cohort variant only meaningful for windows where `event_source = 'BUYER_COMPANY_RELATION'`** (VISIT-originated windows have `BP2VB = 100%` at M0 by construction — the window is materialised by the first booking). Demand-side only by table construction.
- **VB2VC (Booking-to-Visit, Visit Booked → Visit Completed)** — `visits_completed / bookings_created`. Coincident: `fact_visits` filtered by month. Cohort: origin = `ts_booking_created` month; numerator = `ts_visit_completed`. **Most common cohort metric for operational quality.**
- **VC2OS (Visit Completed → Offer Submitted)** — `offers_submitted / visits_completed`. Cohort: origin = `ts_visit_completed` month; numerator = first `fact_offers.ts_offer_submitted` joined by `sk_booking`. A booking can yield multiple offers — take the first per `sk_booking` to avoid fanout.
- **OS2OA (Offer Submitted → Offer Accepted)** — `offers_accepted / offers_submitted`. Cohort: origin = `ts_offer_submitted` month; numerator = `ts_offer_accepted` on the same `sk_offer`.
- **OA2CCV (Offer Accepted → CCV signed)** — `sale_agreements_signed / offers_accepted`. Cohort: origin = `ts_offer_accepted` month; numerator = `ts_sale_agreement_signed` on the same `sk_offer`.
- **O2C / O2CCV (Offer Submitted → CCV signed, alias)** — `sale_agreements_signed / offers_submitted` — the merged version of OS2OA × OA2CCV. Useful when the OA stage is not the analytical pivot.
- **VB2CCV / B2CCV (Booking-to-CCV, end-to-end transaction)** — full end-to-end conversion at transaction grain. Coincident: often computed via `fact_buyer_prospects.sale_agreements_signed / bookings_created`. Cohort: origin = `ts_booking_created` month; numerator = `ts_sale_agreement_signed` joined via `sk_booking → fact_offers`. Expect long tails — M3..M12 columns are still meaningful.
- **NBP2VC / NBP2CCV (ToF-anchored end-to-end)** — buyer-prospect-anchored conversion: `visits_completed (or sale_agreements_signed) / NBP windows opened`. Coincident: `fact_buyer_prospects` cross with `dim_buyer_prospect_3p_history` per period. Cohort: origin = `dim_buyer_prospect_3p_history.ts_started` month for `buyer_prospect_type = 'NBP'`; numerator = first `fact_visits.ts_visit_completed` (or `fact_offers.ts_sale_agreement_signed`) for the same buyer after `ts_started`. **Structural exception**: NBP windows are demand-side only (no `3P_SUPPLY` demand_type) — these metrics do not include `is_3p_supply`-only configurations by construction, so they read narrower than the headline transaction metrics. Call this out explicitly when reporting NBP-anchored conversion next to headline volumes.
- **Share of 3P on the full demand funnel** — `COUNT(*) FILTER (WHERE is_3p_demand OR is_3p_lead_gen OR is_3p_supply) / COUNT(*)` per stage on `fact_visits` / `fact_offers`. The narrower "share of buyer-attributed 3P demand" (excluding supply-only) is a separate metric — `COUNT(*) FILTER (WHERE is_3p_demand OR is_3p_lead_gen)` — name it explicitly when delivered.
- **Volume per demand-side broker** — `COUNT(*) GROUP BY sk_broker_demand` filtering `is_3p_demand OR is_3p_lead_gen` (two-flag scope) **and** `sk_broker_demand <> -1`; join `dw_brokers.dim_broker` for partner names. **Structural exception**: cannot mechanically include `is_3p_supply`-only rows (their `sk_broker_demand = -1`). If the question needs the broader scope at broker grain, group by `sk_broker_supply` or `business_model` instead.
- **Volume per supply-side broker on the demand funnel** — `COUNT(*) GROUP BY sk_broker_supply` filtering `is_3p_supply = TRUE` and `sk_broker_supply <> -1`; covers both `BM_3P_DEMAND_3P_SUPPLY` (partner brokers on both sides) and `BM_3P_SUPPLY_1P_DEMAND_AGENT` (partner listing, 1P-worked demand). Use this when the question is "how is the demand funnel performing on partner inventory".
- **Volume NBP vs RBP** — `COUNT(*) GROUP BY buyer_prospect_type, demand_type` on `dim_buyer_prospect_3p_history` (filtered to current windows or by cohort). Demand-side only by table construction.
- **Time-to-close (booking → CCV signed)** — `DATE_DIFF('day', ts_booking_created, ts_sale_agreement_signed)` per closed CCV; or use `fact_buyer_prospects.days_first_booking_created_to_first_sale_agreement_signed`.
- **Average brokerage fee on 3P CCVs** — `AVG(brokerage_fee)` on `fact_offers` where `ts_sale_agreement_signed IS NOT NULL` and the default three-flag filter applies.

## Relationships with Other Entities

### Broker (N:1 — two paths)

- `fact_visits.sk_broker_demand = dw_brokers.dim_broker.sk_broker` and analogously for `fact_offers`, `fact_sale_demand_event`, `dim_buyer_prospect_3p_history`.
- `fact_visits.sk_broker_supply = dw_brokers.dim_broker.sk_broker` for cross-broker transactions (`is_3p_demand AND is_3p_supply`).
- Full broker context — products, status / tier / account-manager / profile / integrator history, agents 3P, the eight-row business-model matrix — lives in [`broker_xp.md`](./broker_xp.md).

### 3P Supply (N:1 — same Marketplace, opposite side)

- The supply-side counterpart of this funnel. Bridge via `sk_house` between `fact_visits` / `fact_offers` and `dw_3p_supply.fact_lead_3p_flows`.
- For cross-broker transactions, the demand-side analysis here pairs with the supply-side coverage in [`3p_supply.md`](./3p_supply.md).

### House (N:1)

- `fact_visits.sk_house = fact_offers.sk_house = dw_house.dim_house.sk_house`. House attributes (rooms, price segment, neighbourhood) live in `dw_house`.

### Buyer (N:1)

- `fact_visits.sk_buyer = fact_offers.sk_buyer = fact_buyer_prospects.sk_buyer = dim_buyer_prospect_3p_history.sk_buyer = dw_public.dim_user.sk_user`. Buyer-level OBT in `fact_buyer_prospects`.

### Agent (N:1)

- `fact_visits.sk_agent = fact_offers.sk_agent = dw_public.dim_agent.sk_agent`. For 3P agents, filter `is_3p_agent = TRUE` or `agent_type = 'CORRETOR_REDE'`. SCD2 history in `dw_agent.dim_agent_3p_history`.

### Booking (1:1 with Visit; 1:N with Offer)

- `fact_visits.sk_booking = fact_offers.sk_booking = dw_public.dim_booking.sk_booking`. Booking is the parent universe; visit is one type within it.

### Region (N:1)

- `fact_visits.sk_region = fact_offers.sk_region = dw_public.dim_region.sk_region`. For demand-side broker operating regions, see `dw_brokers.dim_broker_regions` filtered by `business_context = 'SALE'`.

### Buyer Intention (categorical)

- `dim_booking.buyer_intention` (`LIVING`, `INVESTMENT_FOR_RENT`, `INVESTMENT_OTHER`) — captured at booking creation. Useful for partner segmentation (e.g. partners specialised in investor vs end-buyer demand).

## Dos and Don'ts

**Do:**
- Treat `dw_sale.dim_buyer_prospect_3p_history` as the **top of funnel**. Every "per-prospect" or "per-broker-demand" analysis must start there, with window match to downstream facts.
- Always bridge Visits ↔ Offers via `sk_booking` (1:N), not `sk_visit`.
- For For Sale 3P Demand, always prefer `dw_sale.fact_visits` and `dw_sale.fact_offers` (DAGs `dw_sale_visits` / `dw_sale_offers`).
- **Default 3P filter at transaction grain** = `is_3p_demand = TRUE OR is_3p_lead_gen = TRUE OR is_3p_supply = TRUE` (three flags). See "Default scope rule" at the top of the doc. Use the narrower demand-broker-side filter (`is_3p_demand OR is_3p_lead_gen`, equivalent to `sk_broker_demand <> -1`) only when the question requires attribution to the demand-side broker that brought the buyer, or when the user explicitly asks for that subset.
- **Pick the right view between coincident and cohort** for every conversion metric. Coincident (same-period numerator and denominator) for volume / share / operational dashboards; cohort (denominator bucketed by origin month, numerator cumulative across M0/M1/M2/...) for true conversion-rate analyses. When the user says "conversão", "taxa de", "% de" without qualifier, lean cohort if the question is about rates, lean coincident if the question is about period volumes. **Always disclose** which view is being used in the response and **NULL** the right-censored cells on recent cohorts (do not zero-fill). Queries 10 and 11 are the canonical cohort templates.
- For cross-stage conversion analyses, **prefer JOINing `dw_sale.fact_visits` and `dw_sale.fact_offers` on `sk_booking` (or `sk_buyer`) and counting per-stage timestamps directly** (`COUNT(*) FILTER (WHERE ts_<event> IS NOT NULL)`). Both facts already carry `is_3p_supply/demand/lead_gen` and `sk_broker_supply/demand`, so 3P attribution requires no extra JOIN. Fall back to `fact_sale_demand_event` only when the analysis genuinely benefits from an unpivoted event-grain layout (e.g. many stages at once, or time-between-events scans across heterogeneous event types).
- For NBP / RBP analyses, always start from `dim_buyer_prospect_3p_history` — never reconstruct from `is_buyer_first_offer` (it answers a different question).
- For CCVs of 3P Lead Gen origin, bridge `dim_sale_agreement.sk_offer = fact_offers.sk_offer` and use `fact_offers.is_3p_lead_gen`. `dim_sale_agreement` does not carry that flag.
- For broker-demand operational quality, JOIN `dim_post_visit_demand.sk_visit = fact_visits.sk_visit` and group by `fact_visits.sk_broker_demand`.
- Use the structured cancellation taxonomy (`dim_visit.cancellation_type` ↔ `dim_cancellation_type`) for visits cancelled since 2024-11; fall back to the legacy free-text fields for older history.
- Filter `dim_booking.type = 'Visita'` whenever counting demand-funnel bookings — the table also covers `Vistoria`, `SessaoFotos`, `CheckUpLar`.
- Decide upfront whether the question is about the **supply side** (`sk_broker_supply`) or **demand side** (`sk_broker_demand`); they answer different broker-performance questions.

**Don't:**
- ❌ **Don't drop `is_3p_supply` from the default 3P Demand filter.** Filtering only on `is_3p_demand OR is_3p_lead_gen` excludes `BM_3P_SUPPLY_1P_DEMAND_AGENT` (partner listing, 1P-worked demand) and underestimates headline volumes (visits, offers, CCVs) on Marketplace-touched transactions. Use the two-flag filter only when the question genuinely requires demand-broker attribution (see Default scope rule).
- ❌ **Don't use `dw_rent.fact_offers` to isolate 3P Demand.** That table does not carry `is_3p_*` or `sk_broker_*` columns — it focuses on the rent-negotiation iterations (`original_rent_value`, `last_proposed_rent_value`, `days_of_negotiation`). Same for `dw_rent.fact_rent_demand_events`, `dw_rent.fact_listing_rent_flows`, and `dw_rent.fact_rent_flows` — none of them carry 3P broker attribution. For For Rent 3P Demand, route through the combined `dw_visit.fact_visits` / `dw_visit.dim_visit` filtered by `business_context = 'RENT'`, or `dw_public.dim_booking` filtered by `visit_intent = 'RENT' AND type = 'Visita'`. See the For Rent appendix.
- ❌ Don't use `dim_sale_agreement.is_3p_supply` / `is_3p_demand` to identify **3P Lead Gen** CCVs — `is_3p_lead_gen` is absent from that dim. Bridge via `fact_offers`.
- ❌ Don't conflate `is_buyer_first_offer` (offer-grain, first-ever offer of the buyer) with **NBP** (window-grain, first appearance of the buyer for that `demand_type`). They answer different questions.
- ❌ Don't treat `dim_buyer_prospect_3p_history.sk_broker` as the supply-side broker — it is demand-side by construction. The supply-side broker on a transaction is on the fact tables (`sk_broker_supply`).
- ❌ Don't count `dim_buyer_prospect_3p_history.sk_buyer_prospect` as a unique key — it is `CONCAT(id_buyer, 0, version)` and version restarts per demand_type. Uniqueness grain is `(sk_buyer, demand_type, version)`.
- ❌ Don't aggregate `fact_offers` with `dim_sale_agreement` expecting matching grains — `dim_sale_agreement` only has rows for offers that reached the sale-agreement stage (LEFT JOIN, not INNER, when comparing the universes).
- ❌ Don't sum `sk_broker_supply` and `sk_broker_demand` together without de-duplicating — a single transaction can attribute to both columns (e.g. `BM_3P_DEMAND_3P_SUPPLY`).
- ❌ Don't aggregate `dim_booking` rows without filtering `type = 'Visita'` — `Vistoria` / `SessaoFotos` / `CheckUpLar` are not demand-funnel events.
- ❌ Don't apply `is_3p_*` flags on `dw_visit.fact_visits` for new analyses without noting the planned schema migration (see Note below).

> **Note — flag migration on `dw_visit.fact_visits`.** The `is_3p_supply` / `is_3p_demand` / `is_3p_lead_gen` columns currently on `dw_visit.fact_visits` (combined Sale + Rent) will be **moved** to `dw_visit.dim_visit` (where they already exist as `is_visit_3p_supply` / `is_visit_3p_demand` / `is_visit_3p_lead_gen`). The columns are NOT being deprecated — both locations work today, but new analyses should target the dim path. For For Sale-specific work, `dw_sale.fact_visits` is unaffected.

## Golden Queries

### Query 1 — Stage-conversion rates split by 3P configuration

Conversion across the canonical funnel (Visit Booked → Visit Completed → Offer Submitted → Offer Accepted → CCV) per 3P configuration. Counts come directly from `fact_visits` and `fact_offers` — each per-stage count is a `COUNT(*) FILTER (WHERE ts_<event> IS NOT NULL)` on the row's own fact, with the 3P configuration label derived from the same row's `is_3p_supply` / `is_3p_demand` / `is_3p_lead_gen` flags. The configuration label covers the **five** Marketplace-touched rows of the eight-row `business_model` matrix from [`broker_xp.md`](./broker_xp.md) — the default three-flag scope.

```sql
WITH config AS (
    SELECT
        sk_booking,
        sk_visit,
        is_3p_demand,
        is_3p_lead_gen,
        is_3p_supply,
        ts_booking_created,
        ts_visit_completed
    FROM dw_sale.fact_visits
    WHERE is_3p_demand = TRUE OR is_3p_lead_gen = TRUE OR is_3p_supply = TRUE
),
visit_metrics AS (
    SELECT
        CASE
            WHEN is_3p_demand   AND     is_3p_supply  THEN '3P_DEMAND + 3P_SUPPLY'
            WHEN is_3p_demand   AND NOT is_3p_supply  THEN '3P_DEMAND + 1P_SUPPLY'
            WHEN is_3p_lead_gen AND     is_3p_supply  THEN '3P_LEAD_GEN + 3P_SUPPLY'
            WHEN is_3p_lead_gen AND NOT is_3p_supply  THEN '3P_LEAD_GEN + 1P_SUPPLY'
            WHEN is_3p_supply   AND NOT is_3p_demand AND NOT is_3p_lead_gen THEN '3P_SUPPLY + 1P_DEMAND'
        END                                                              AS three_p_configuration,
        COUNT(*) FILTER (WHERE ts_booking_created  IS NOT NULL)          AS visits_booked,
        COUNT(*) FILTER (WHERE ts_visit_completed  IS NOT NULL)          AS visits_completed
    FROM config
    GROUP BY 1
),
offer_metrics AS (
    SELECT
        CASE
            WHEN o.is_3p_demand   AND     o.is_3p_supply  THEN '3P_DEMAND + 3P_SUPPLY'
            WHEN o.is_3p_demand   AND NOT o.is_3p_supply  THEN '3P_DEMAND + 1P_SUPPLY'
            WHEN o.is_3p_lead_gen AND     o.is_3p_supply  THEN '3P_LEAD_GEN + 3P_SUPPLY'
            WHEN o.is_3p_lead_gen AND NOT o.is_3p_supply  THEN '3P_LEAD_GEN + 1P_SUPPLY'
            WHEN o.is_3p_supply   AND NOT o.is_3p_demand AND NOT o.is_3p_lead_gen THEN '3P_SUPPLY + 1P_DEMAND'
        END                                                              AS three_p_configuration,
        COUNT(*) FILTER (WHERE o.ts_offer_submitted       IS NOT NULL)   AS offers_submitted,
        COUNT(*) FILTER (WHERE o.ts_offer_accepted        IS NOT NULL)   AS offers_accepted,
        COUNT(*) FILTER (WHERE o.ts_sale_agreement_signed IS NOT NULL)   AS ccvs_signed
    FROM dw_sale.fact_offers AS o
    WHERE o.is_3p_demand = TRUE OR o.is_3p_lead_gen = TRUE OR o.is_3p_supply = TRUE
    GROUP BY 1
)
SELECT
    COALESCE(v.three_p_configuration, o.three_p_configuration) AS three_p_configuration,
    v.visits_booked,
    v.visits_completed,
    o.offers_submitted,
    o.offers_accepted,
    o.ccvs_signed
FROM       visit_metrics AS v
FULL JOIN  offer_metrics AS o USING (three_p_configuration)
ORDER BY v.visits_booked DESC NULLS LAST
```

> *Event-grain fallback.* The same numbers can be reproduced from `dw_sale.fact_sale_demand_event` by filtering `sk_event_type` to the relevant events — useful when a single output also needs heterogeneous events such as `BC` (cancelled) or `OR` (rejected) in the same long-format result. For headline funnel conversion, the direct timestamp pattern above is preferred.

### Query 2 — Performance per demand-side broker

Volume of visits, offers, and CCVs attributed to each demand-side broker. Joins `dim_broker` for partner names.

> **Structural exception — two-flag filter here is correct.** This query groups by `sk_broker_demand`, so `is_3p_supply`-only rows (where `sk_broker_demand = -1`) cannot be meaningfully attributed and would collapse under the sentinel. Keep the `is_3p_demand OR is_3p_lead_gen` filter. For the broader scope on partner inventory, pair this with **Query 2b** (group by `sk_broker_supply` filtering `is_3p_supply = TRUE`) — same shape, supply-side broker grain.

```sql
WITH visits AS (
    SELECT
        sk_broker_demand AS sk_broker,
        COUNT(*) FILTER (WHERE ts_visit_completed IS NOT NULL) AS visits_completed,
        COUNT(*) FILTER (WHERE ts_visit_canceled  IS NOT NULL) AS visits_canceled
    FROM dw_sale.fact_visits
    WHERE (is_3p_demand = TRUE OR is_3p_lead_gen = TRUE)
      AND sk_broker_demand <> -1
    GROUP BY sk_broker_demand
),
offers AS (
    SELECT
        sk_broker_demand AS sk_broker,
        COUNT(*)                                                     AS offers_submitted,
        COUNT(*) FILTER (WHERE ts_offer_accepted IS NOT NULL)        AS offers_accepted,
        COUNT(*) FILTER (WHERE ts_sale_agreement_signed IS NOT NULL) AS ccvs_signed
    FROM dw_sale.fact_offers
    WHERE (is_3p_demand = TRUE OR is_3p_lead_gen = TRUE)
      AND sk_broker_demand <> -1
    GROUP BY sk_broker_demand
)
SELECT
    b.sk_broker,
    b.broker_name,
    b.broker_trade_name,
    b.broker_state,
    v.visits_completed,
    v.visits_canceled,
    o.offers_submitted,
    o.offers_accepted,
    o.ccvs_signed
FROM dw_brokers.dim_broker AS b
LEFT JOIN visits AS v ON b.sk_broker = v.sk_broker
LEFT JOIN offers AS o ON b.sk_broker = o.sk_broker
WHERE b.sk_broker <> -1
ORDER BY o.ccvs_signed DESC NULLS LAST
```

### Query 3 — Supply × Demand broker pairs with most transactions

Maps the collaboration grid between supply-side and demand-side brokers (only the rows where both are 3P).

```sql
SELECT
    f.sk_broker_supply,
    bs.broker_name AS broker_supply_name,
    f.sk_broker_demand,
    bd.broker_name AS broker_demand_name,
    COUNT(*)                                                     AS offers_submitted,
    COUNT(*) FILTER (WHERE f.ts_offer_accepted IS NOT NULL)      AS offers_accepted,
    COUNT(*) FILTER (WHERE f.ts_sale_agreement_signed IS NOT NULL) AS ccvs_signed
FROM dw_sale.fact_offers AS f
INNER JOIN dw_brokers.dim_broker AS bs ON f.sk_broker_supply = bs.sk_broker
INNER JOIN dw_brokers.dim_broker AS bd ON f.sk_broker_demand = bd.sk_broker
WHERE f.is_3p_supply = TRUE
  AND (f.is_3p_demand = TRUE OR f.is_3p_lead_gen = TRUE)
  AND f.sk_broker_supply <> -1
  AND f.sk_broker_demand <> -1
GROUP BY f.sk_broker_supply, bs.broker_name, f.sk_broker_demand, bd.broker_name
ORDER BY offers_submitted DESC
```

### Query 4 — Volume NBP vs RBP per demand_type

Distribution of buyer prospect windows by type and demand_type, restricted to currently open windows. Drop `is_current = TRUE` for cohort views by `YEAR(ts_started), MONTH(ts_started)`.

```sql
SELECT
    demand_type,
    buyer_prospect_type,
    COUNT(*) AS prospect_windows,
    COUNT(DISTINCT sk_buyer) AS distinct_buyers
FROM dw_sale.dim_buyer_prospect_3p_history
WHERE is_current = TRUE
  AND sk_broker <> -1
GROUP BY demand_type, buyer_prospect_type
ORDER BY demand_type, buyer_prospect_type
```

### Query 5 — 3P Demand vs 3P Lead Gen vs 3P Supply — comparison across the funnel

Side-by-side counts of each stage by the three default 3P flags. **The three columns are not mutually exclusive**: a `BM_3P_DEMAND_3P_SUPPLY` transaction is counted once under `DEMAND` and once under `SUPPLY`. Read the result as "share of each flag on the funnel", not as a partition.

```sql
WITH visits AS (
    SELECT
        flag                                                          AS flag,
        COUNT(*) FILTER (WHERE ts_visit_completed IS NOT NULL)        AS visits_completed
    FROM dw_sale.fact_visits
    CROSS JOIN UNNEST(ARRAY[
        CASE WHEN is_3p_demand   THEN 'DEMAND'   END,
        CASE WHEN is_3p_lead_gen THEN 'LEAD_GEN' END,
        CASE WHEN is_3p_supply   THEN 'SUPPLY'   END
    ]) AS t (flag)
    WHERE flag IS NOT NULL
    GROUP BY flag
),
offers AS (
    SELECT
        flag                                                          AS flag,
        COUNT(*) FILTER (WHERE ts_offer_submitted IS NOT NULL)        AS offers_submitted,
        COUNT(*) FILTER (WHERE ts_offer_accepted IS NOT NULL)         AS offers_accepted,
        COUNT(*) FILTER (WHERE ts_sale_agreement_signed IS NOT NULL)  AS ccvs_signed
    FROM dw_sale.fact_offers
    CROSS JOIN UNNEST(ARRAY[
        CASE WHEN is_3p_demand   THEN 'DEMAND'   END,
        CASE WHEN is_3p_lead_gen THEN 'LEAD_GEN' END,
        CASE WHEN is_3p_supply   THEN 'SUPPLY'   END
    ]) AS t (flag)
    WHERE flag IS NOT NULL
    GROUP BY flag
)
SELECT
    v.flag,
    v.visits_completed,
    o.offers_submitted,
    o.offers_accepted,
    o.ccvs_signed
FROM       visits AS v
INNER JOIN offers AS o ON v.flag = o.flag
ORDER BY v.flag
```

### Query 6 — Average time booking → offer and visit_completed → offer per business_model

Time-to-stage metrics, split by `business_model`. Uses pre-computed columns on `fact_offers` and bridges to `dim_visit.business_model` via the visit linked to the offer's booking (`fact_offers.sk_booking → fact_visits.sk_booking → fact_visits.sk_visit → dim_visit.sk_visit`). Filter uses the default three-flag scope so all five Marketplace-touched business models appear in the breakdown.

```sql
WITH offer_with_visit AS (
    SELECT
        o.sk_offer,
        o.hours_booking_to_offer,
        o.hours_visit_completed_to_offer,
        o.days_offer_submitted_to_offer_accepted,
        o.days_offer_accepted_to_sale_agreement_signed,
        fv.sk_visit
    FROM dw_sale.fact_offers AS o
    LEFT JOIN dw_sale.fact_visits AS fv ON o.sk_booking = fv.sk_booking
    WHERE (o.is_3p_demand = TRUE OR o.is_3p_lead_gen = TRUE OR o.is_3p_supply = TRUE)
)
SELECT
    v.business_model,
    AVG(owv.hours_booking_to_offer)                          AS avg_hours_booking_to_offer,
    AVG(owv.hours_visit_completed_to_offer)                  AS avg_hours_visit_to_offer,
    AVG(owv.days_offer_submitted_to_offer_accepted)          AS avg_days_os_to_oa,
    AVG(owv.days_offer_accepted_to_sale_agreement_signed)    AS avg_days_oa_to_ccv,
    COUNT(*)                                                 AS offers_count
FROM offer_with_visit AS owv
LEFT JOIN dw_visit.dim_visit AS v ON owv.sk_visit = v.sk_visit
GROUP BY v.business_model
ORDER BY offers_count DESC
```

### Query 7 — CCVs signed split by 3P type (supply / demand / both)

CCV volume per 3P configuration. Bridges `dim_sale_agreement` to `fact_offers` so we can use `is_3p_lead_gen` (which is absent from the dim).

```sql
SELECT
    CASE
        WHEN f.is_3p_supply AND f.is_3p_demand AND NOT f.is_3p_lead_gen THEN '3P Supply + 3P Demand'
        WHEN f.is_3p_supply AND f.is_3p_lead_gen                        THEN '3P Supply + 3P Lead Gen'
        WHEN f.is_3p_supply AND NOT f.is_3p_demand AND NOT f.is_3p_lead_gen THEN '3P Supply only'
        WHEN NOT f.is_3p_supply AND f.is_3p_demand                      THEN '3P Demand only'
        WHEN NOT f.is_3p_supply AND f.is_3p_lead_gen                    THEN '3P Lead Gen only'
        WHEN NOT f.is_3p_supply AND NOT f.is_3p_demand AND NOT f.is_3p_lead_gen THEN '1P (no 3P)'
        ELSE 'Other'
    END AS three_p_configuration,
    COUNT(*)                                                AS ccvs_signed,
    AVG(f.sale_price_agreed)                                AS avg_sale_price_agreed,
    AVG(f.brokerage_fee)                                    AS avg_brokerage_fee
FROM dw_sale.fact_offers AS f
INNER JOIN dw_sale.dim_sale_agreement AS sa ON f.sk_offer = sa.sk_offer
WHERE sa.sale_agreement_status = 'Assinado'
  AND f.ts_sale_agreement_signed IS NOT NULL
GROUP BY 1
ORDER BY ccvs_signed DESC
```

### Query 8 — Post-visit ratings per demand-side broker

Quality signal per partner — average rating and operational categorical splits. Same structural exception as Query 2: grouped by `sk_broker_demand`, so the two-flag filter is correct (rows that are only `is_3p_supply` have `sk_broker_demand = -1` and cannot be attributed).

```sql
SELECT
    f.sk_broker_demand,
    b.broker_name,
    COUNT(*)                                                            AS evaluations,
    AVG(CAST(pv.agent_rating AS DOUBLE))                                AS avg_agent_rating,
    COUNT(*) FILTER (WHERE pv.agent_punctuality = 'GOOD')               AS punctuality_good,
    COUNT(*) FILTER (WHERE pv.agent_punctuality = 'NEEDS_IMPROVEMENT')  AS punctuality_needs_improvement,
    COUNT(*) FILTER (WHERE pv.agent_bypass_attempt = 'NEEDS_IMPROVEMENT') AS bypass_attempts
FROM dw_visit.dim_post_visit_demand AS pv
INNER JOIN dw_sale.fact_visits AS f ON pv.sk_visit = f.sk_visit
INNER JOIN dw_brokers.dim_broker AS b ON f.sk_broker_demand = b.sk_broker
WHERE (f.is_3p_demand = TRUE OR f.is_3p_lead_gen = TRUE)
  AND f.sk_broker_demand <> -1
GROUP BY f.sk_broker_demand, b.broker_name
HAVING COUNT(*) >= 10
ORDER BY avg_agent_rating DESC NULLS LAST
```

### Query 9 — Buyer journey 3P (window → first booking → first visit → first offer → first CCV)

End-to-end ToF-anchored journey, using `dim_buyer_prospect_3p_history` as the window source and `fact_buyer_prospects` for the per-buyer aggregated journey timestamps.

```sql
WITH windows AS (
    SELECT
        sk_buyer,
        demand_type,
        buyer_prospect_type,
        sk_broker AS demand_broker,
        version,
        ts_started,
        ts_ended,
        is_current
    FROM dw_sale.dim_buyer_prospect_3p_history
    WHERE buyer_prospect_type = 'NBP'
      AND sk_broker <> -1
),
buyer_journey AS (
    SELECT
        sk_buyer,
        sk_first_booking_created_date,
        sk_first_visit_completed_date,
        sk_first_offer_submitted_date,
        sk_first_sale_agreement_signed_date,
        days_first_sale_flow_to_first_sale_agreement_signed,
        further_funnel_step,
        first_buyer_intention
    FROM dw_sale.fact_buyer_prospects
)
SELECT
    w.sk_buyer,
    w.demand_type,
    w.demand_broker,
    b.broker_name AS demand_broker_name,
    w.ts_started AS nbp_window_started,
    bj.sk_first_booking_created_date,
    bj.sk_first_visit_completed_date,
    bj.sk_first_offer_submitted_date,
    bj.sk_first_sale_agreement_signed_date,
    bj.days_first_sale_flow_to_first_sale_agreement_signed,
    bj.further_funnel_step,
    bj.first_buyer_intention
FROM windows AS w
LEFT JOIN buyer_journey AS bj ON w.sk_buyer = bj.sk_buyer
LEFT JOIN dw_brokers.dim_broker AS b ON w.demand_broker = b.sk_broker
ORDER BY w.ts_started DESC
```

### Query 10 — VB2VC cohort matrix (template for any single-stage cohort)

Cohort version of the Visit Booked → Visit Completed conversion. Each row is one origin month (the month the booking was created), each `vb2vc_m_N` column is the **cumulative conversion rate** by N months after the origin. `M_N` is set to `NULL` for cohorts that are not yet observable, never to zero.

This query is the **canonical template** for every single-stage cohort in the funnel — to compute VC2OS / OS2OA / OA2CCV, swap the origin timestamp (`ts_booking_created` → `ts_visit_completed` / `ts_offer_submitted` / `ts_offer_accepted`) and the numerator timestamp (`ts_visit_completed` → `ts_offer_submitted` / `ts_offer_accepted` / `ts_sale_agreement_signed`). The 3P filter and right-censoring logic are unchanged.

```sql
WITH params AS (
    SELECT
        date '2025-01-01'                         AS first_origin_month,
        date_trunc('month', current_date)         AS current_month_start,
        6                                          AS horizon_months
),
bookings AS (
    SELECT
        f.sk_booking,
        f.sk_visit,
        f.is_3p_demand,
        f.is_3p_lead_gen,
        f.is_3p_supply,
        CAST(date_trunc('month', CAST(f.ts_booking_created AS DATE)) AS DATE) AS origin_month,
        f.ts_booking_created,
        f.ts_visit_completed
    FROM dw_sale.fact_visits AS f
    CROSS JOIN params AS p
    WHERE (f.is_3p_demand = TRUE OR f.is_3p_lead_gen = TRUE OR f.is_3p_supply = TRUE)
      AND CAST(f.ts_booking_created AS DATE) >= p.first_origin_month
      AND CAST(f.ts_booking_created AS DATE) <  p.current_month_start
),
cohort AS (
    SELECT
        b.origin_month,
        COUNT(*) AS total_visits_booked,
        COUNT(*) FILTER (
            WHERE b.ts_visit_completed IS NOT NULL
              AND date_diff('month', b.origin_month,
                            CAST(date_trunc('month', CAST(b.ts_visit_completed AS DATE)) AS DATE)) <= 0
        ) AS vc_by_m0,
        COUNT(*) FILTER (
            WHERE b.ts_visit_completed IS NOT NULL
              AND date_diff('month', b.origin_month,
                            CAST(date_trunc('month', CAST(b.ts_visit_completed AS DATE)) AS DATE)) <= 1
        ) AS vc_by_m1,
        COUNT(*) FILTER (
            WHERE b.ts_visit_completed IS NOT NULL
              AND date_diff('month', b.origin_month,
                            CAST(date_trunc('month', CAST(b.ts_visit_completed AS DATE)) AS DATE)) <= 2
        ) AS vc_by_m2,
        COUNT(*) FILTER (
            WHERE b.ts_visit_completed IS NOT NULL
              AND date_diff('month', b.origin_month,
                            CAST(date_trunc('month', CAST(b.ts_visit_completed AS DATE)) AS DATE)) <= 3
        ) AS vc_by_m3,
        COUNT(*) FILTER (
            WHERE b.ts_visit_completed IS NOT NULL
              AND date_diff('month', b.origin_month,
                            CAST(date_trunc('month', CAST(b.ts_visit_completed AS DATE)) AS DATE)) <= 6
        ) AS vc_by_m6
    FROM bookings AS b
    GROUP BY b.origin_month
),
censored AS (
    SELECT
        c.origin_month,
        c.total_visits_booked,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 1 THEN c.vc_by_m0 END AS vc_by_m0,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 2 THEN c.vc_by_m1 END AS vc_by_m1,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 3 THEN c.vc_by_m2 END AS vc_by_m2,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 4 THEN c.vc_by_m3 END AS vc_by_m3,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 7 THEN c.vc_by_m6 END AS vc_by_m6
    FROM cohort AS c
    CROSS JOIN params AS p
)
SELECT
    origin_month,
    total_visits_booked,
    ROUND(CAST(vc_by_m0 AS DOUBLE) / NULLIF(total_visits_booked, 0), 4) AS vb2vc_m0,
    ROUND(CAST(vc_by_m1 AS DOUBLE) / NULLIF(total_visits_booked, 0), 4) AS vb2vc_m1,
    ROUND(CAST(vc_by_m2 AS DOUBLE) / NULLIF(total_visits_booked, 0), 4) AS vb2vc_m2,
    ROUND(CAST(vc_by_m3 AS DOUBLE) / NULLIF(total_visits_booked, 0), 4) AS vb2vc_m3,
    ROUND(CAST(vc_by_m6 AS DOUBLE) / NULLIF(total_visits_booked, 0), 4) AS vb2vc_m6
FROM censored
ORDER BY origin_month
```

The `censored` CTE is the **right-censoring guard** — it sets a column to `NULL` when there is not enough elapsed time to observe the full cohort window. The condition `date_diff('month', origin_month, current_month_start) >= N + 1` says: "M_N is observable only if at least N+1 full calendar months have elapsed since `origin_month`". Adjust horizons (`m0`, `m1`, ... `m6` here) to the granularity the analysis needs.

**To split by a dimension** (3P configuration, demand-side broker, demand_type), add the dimension column to the `bookings` CTE, propagate through `cohort` / `censored`, and add it to the final `GROUP BY` and `SELECT`. The matrix shape stays the same — origin months stack vertically, M_N columns extend horizontally.

### Query 11 — NBP-anchored multi-stage cohort matrix (NBP → VC, OS, CCV)

ToF-anchored cohort: every row in `dim_buyer_prospect_3p_history` with `buyer_prospect_type = 'NBP'` is a denominator unit. Three numerators track the buyer's first downstream event after `ts_started` — visit completed, offer submitted, CCV signed — and conversion rates are emitted at M0, M3, M6 cumulative. Inherits the demand-side-only construction of the NBP table (no `is_3p_supply`-only scope here — see structural exception).

```sql
WITH params AS (
    SELECT
        date '2025-01-01'                         AS first_origin_month,
        date_trunc('month', current_date)         AS current_month_start
),
nbp_windows AS (
    SELECT
        h.sk_buyer,
        h.demand_type,
        h.sk_broker AS sk_broker_demand,
        h.ts_started,
        CAST(date_trunc('month', CAST(h.ts_started AS DATE)) AS DATE) AS origin_month
    FROM dw_sale.dim_buyer_prospect_3p_history AS h
    CROSS JOIN params AS p
    WHERE h.buyer_prospect_type = 'NBP'
      AND h.sk_broker <> -1
      AND CAST(h.ts_started AS DATE) >= p.first_origin_month
      AND CAST(h.ts_started AS DATE) <  p.current_month_start
),
buyer_first_events AS (
    SELECT
        v.sk_buyer,
        MIN(v.ts_visit_completed)         AS ts_first_visit_completed,
        MIN(o.ts_offer_submitted)         AS ts_first_offer_submitted,
        MIN(o.ts_sale_agreement_signed)   AS ts_first_sale_agreement_signed
    FROM dw_sale.fact_visits AS v
    LEFT JOIN dw_sale.fact_offers AS o ON v.sk_booking = o.sk_booking
    WHERE v.sk_buyer IS NOT NULL
    GROUP BY v.sk_buyer
),
joined AS (
    SELECT
        n.origin_month,
        n.sk_buyer,
        n.ts_started,
        be.ts_first_visit_completed,
        be.ts_first_offer_submitted,
        be.ts_first_sale_agreement_signed
    FROM nbp_windows AS n
    LEFT JOIN buyer_first_events AS be ON be.sk_buyer = n.sk_buyer
),
cohort AS (
    SELECT
        j.origin_month,
        COUNT(*) AS total_nbp_windows,
        COUNT(*) FILTER (
            WHERE j.ts_first_visit_completed IS NOT NULL
              AND j.ts_first_visit_completed >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_visit_completed AS DATE)) AS DATE)) <= 0
        ) AS vc_by_m0,
        COUNT(*) FILTER (
            WHERE j.ts_first_visit_completed IS NOT NULL
              AND j.ts_first_visit_completed >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_visit_completed AS DATE)) AS DATE)) <= 3
        ) AS vc_by_m3,
        COUNT(*) FILTER (
            WHERE j.ts_first_offer_submitted IS NOT NULL
              AND j.ts_first_offer_submitted >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_offer_submitted AS DATE)) AS DATE)) <= 3
        ) AS os_by_m3,
        COUNT(*) FILTER (
            WHERE j.ts_first_offer_submitted IS NOT NULL
              AND j.ts_first_offer_submitted >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_offer_submitted AS DATE)) AS DATE)) <= 6
        ) AS os_by_m6,
        COUNT(*) FILTER (
            WHERE j.ts_first_sale_agreement_signed IS NOT NULL
              AND j.ts_first_sale_agreement_signed >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_sale_agreement_signed AS DATE)) AS DATE)) <= 6
        ) AS ccv_by_m6,
        COUNT(*) FILTER (
            WHERE j.ts_first_sale_agreement_signed IS NOT NULL
              AND j.ts_first_sale_agreement_signed >= j.ts_started
              AND date_diff('month', j.origin_month,
                            CAST(date_trunc('month', CAST(j.ts_first_sale_agreement_signed AS DATE)) AS DATE)) <= 12
        ) AS ccv_by_m12
    FROM joined AS j
    GROUP BY j.origin_month
),
censored AS (
    SELECT
        c.origin_month,
        c.total_nbp_windows,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 1  THEN c.vc_by_m0   END AS vc_by_m0,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 4  THEN c.vc_by_m3   END AS vc_by_m3,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 4  THEN c.os_by_m3   END AS os_by_m3,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 7  THEN c.os_by_m6   END AS os_by_m6,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 7  THEN c.ccv_by_m6  END AS ccv_by_m6,
        CASE WHEN date_diff('month', c.origin_month, p.current_month_start) >= 13 THEN c.ccv_by_m12 END AS ccv_by_m12
    FROM cohort AS c
    CROSS JOIN params AS p
)
SELECT
    origin_month,
    total_nbp_windows,
    ROUND(CAST(vc_by_m0   AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2vc_m0,
    ROUND(CAST(vc_by_m3   AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2vc_m3,
    ROUND(CAST(os_by_m3   AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2os_m3,
    ROUND(CAST(os_by_m6   AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2os_m6,
    ROUND(CAST(ccv_by_m6  AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2ccv_m6,
    ROUND(CAST(ccv_by_m12 AS DOUBLE) / NULLIF(total_nbp_windows, 0), 4) AS nbp2ccv_m12
FROM censored
ORDER BY origin_month
```

**Reading the result** — `nbp2vc_m0` is "of NBP windows opened in this month, the share that had a completed visit within the origin month itself"; `nbp2ccv_m12` is "...within 12 months". The metrics are **buyer-grain** (`MIN(ts_*) GROUP BY sk_buyer`), so a buyer with multiple bookings only contributes once per stage — matching the NBP semantics (windows per `(sk_buyer, demand_type)`).

**Tuning**:
- Add `demand_type` (3P_DEMAND / 3P_LEAD_GEN) to the `nbp_windows` projection and final `GROUP BY` to split by demand modality.
- Replace `MIN(ts_*)` with a window-bounded variant (only events within `(ts_started, ts_ended)`) if the analysis must attribute conversion **only inside the NBP window** rather than to any future event by the buyer.
- For broker-level cohort breakdown, group by `sk_broker_demand` as well; remember the demand-side structural exception (Query 2 / Query 8 pattern).

## Appendix — For Rent

The For Rent path of 3P Demand is **partially exposed** in the current warehouse. The relevant gaps and workarounds:

- **`dw_rent.fact_offers` does NOT carry 3P attribution.** It models the rent-negotiation iterations (`original_rent_value`, `last_proposed_rent_value`, `days_of_negotiation`, `qtd_topics_negotiated`) but has no `is_3p_*` or `sk_broker_*` columns. Treat it as out-of-scope for 3P Demand analysis.
- **`dw_rent.fact_rent_demand_events` also lacks 3P attribution.** It is the event-grain rent funnel (analogous to `fact_sale_demand_event`) but carries only `sk_company_supply` (legacy Rede company), not the broker or 3P flags.
- **`dw_rent.fact_listing_rent_flows` / `dw_rent.fact_rent_flows`** — same story. No `is_3p_*` columns.

**Workarounds for For Rent 3P Demand:**

- **Visit-level**: use `dw_visit.fact_visits` / `dw_visit.dim_visit` with `business_context = 'RENT'`. The 3P flags and brokers are present on both.
- **Booking-level**: `dw_public.dim_booking` with `visit_intent = 'RENT' AND type = 'Visita'` carries `is_3p_demand`, `is_3p_lead_gen`, `partner_3p_demand`.
- **No offer-level or contract-level 3P attribution currently available** — the For Rent funnel below the visit stage is a known gap. For partner-attributed analyses past the visit, escalate to the For Rent data team.

For the umbrella business context (broker model, agents 3P, business-model matrix, 3P identification across other entities), see [`broker_xp.md`](./broker_xp.md). For the supply-side counterpart, see [`3p_supply.md`](./3p_supply.md).