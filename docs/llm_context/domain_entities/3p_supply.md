# 3P Supply

## Ownership

**Data Owner:**
- vitor.musachio@quintoandar.com.br

**Data Steward:**
- vitor.musachio@quintoandar.com.br

---

## Overview

3P Supply is the third-party (rede) sub-funnel of QuintoAndar's supply chain — properties brought into the platform by partner real-estate brokers via the **BSP (Broker Supply Platform)**. It tracks each partner-submitted lead from initial ingestion in the BSP, through business validation and availability checks, all the way to the first listing publication on the main system. The model is the source of truth for L2FL on the rede channel and for identifying actionable supply opportunities.

The `dw_3p_supply` schema follows a star-schema design with a single fact (`fact_lead_3p_flows`) and three dimensions (`dim_current_conversion_funnel`, `dim_lead_3p`, `dim_lead_3p_image_inspection`). The fact-grain is **lead × business_context** — the same lead can produce one flow for SALE and another for RENT, distinguished by `sk_lead_3p_flow`.

The lifecycle has six stages, in **canonical analytical order**:
1. **Lead ingested in BSP** — `fact_lead_3p_flows.ts_lead_created` (and `ts_business_context_created` per modality)
2. **Business validation in BSP** — eligibility/not-eligibility pendings signed by BSP; status snapshot in `dim_current_conversion_funnel.current_bsp_status` + `reason_macro`
3. **Photo processing in BSP** — `ts_first_processing_photos_in_bsp` / `ts_last_processing_photos_in_bsp`
4. **Registered from BSP to main** — `ts_first_registered_from_bsp_to_main`; `sk_house` is populated
5. **Availability check on main** — `ts_availability_check_start` / `ts_availability_check_end`
6. **First listing published** — `ts_first_listing` (`current_conversion_funnel = 'FIRST_LISTING'`)

**Use this order whenever the analysis cares about stage progression** — funnel breakdowns, drop-off rates, time-in-stage, time-to-stage, conversion-by-stage. The ordering matches the `dim_current_conversion_funnel` CASE precedence so the dim's stage label and your analytical sort agree.

**The actual journey is not linear.** Leads can:
- **Skip stages** — e.g. a lead can be **DISCARDED** in BSP at stage 2 without ever reaching photo processing or main.
- **Stop and stay** — most stuck leads live in terminal-ish states (`NOT_CONVERTED_BSP`, `SUSPENDED_BSP`, `UNPUBLISHED_BSP`, `DISCARDED_BSP`); only those in `NOT_CONVERTED` with eligible pendings are `OPPORTUNITY`.
- **Move backward** — once on main, BSP status can be updated by main-side events (e.g. unpublishing a published listing in Portfolio Manager flips BSP status to `UNPUBLISHED`). The BSP status never reverts to `NOT_CONVERTED` after main, but other transitions are possible.
- **Be a duplicate** — a lead marked **DUPLICATED** against another house effectively never proceeds; `sk_house_duplicated <> -1` flags the matching house.

So treat the canonical order as the **analytical scaffold**, not a guarantee of chronological progression. For a lead's *current* state, always use `dim_current_conversion_funnel.current_conversion_funnel`; for sequence reasoning, use the timestamp set, not the stage number.

## Glossary and Synonyms

- **3P**, **rede**, **rede de parceiros**, **marketplace** → third-party broker network — the only acquisition channel covered by this entity. In `dw_growth.obt_supply` it appears as `acquisition_origin = 'rede'`.
- **BSP** (Broker Supply Processor), **portal do parceiro** → the partner-broker portal where leads are submitted; most BSP-side timestamps are suffixed `_in_bsp` (e.g. `ts_discarded_in_bsp`, `ts_first_not_converted_in_bsp`).
- **Main** → QuintoAndar's main listing system; the lead is registered there from BSP and a listing is later published. Status and timestamps on the main side are prefixed `current_main_*` or `ts_first_listing` / `ts_availability_check_*`.
- **Draft listing**, **listing draft**, **rascunho de anúncio** → the standard term for a 3P lead once it reaches main. After `ts_first_registered_from_bsp_to_main`, the lead is materialised on main as a draft listing whose lifecycle (availability check, publication, unpublication) is what `current_main_status` / `current_main_status_reason` describe. Tracked upstream in `datalake_3p_supply.listing_draft_status` and surfaced in `dim_current_conversion_funnel` via `sk_listing_draft_status` (`-1` when the lead never reached main).
- **Lead 3P**, **lead da rede** → a single property submission from a partner broker (`dim_lead_3p` grain).
- **Lead Opportunity**, **oportunidade**, **backlog**, **opportunities** → an actionable lead — `is_opportunity = TRUE`. Defined as: `status = 'NOT_CONVERTED'` AND `is_eligible_pending = TRUE` AND `is_not_eligible_pending = FALSE` (i.e. there are pendings the partner can fix and no disqualifying ones).
- **L2FL** (Lead to First Listing) → the primary supply-chain conversion metric; valid-lead denominator: `(ts_partner_contract_start IS NULL AND is_valid_first_lead) OR is_current_valid_first_lead`.
- **valid first lead** (`is_valid_first_lead`) → the first lead all-time for `(lead_hash, uuid_company, business_context)`. Prevents counting the same property submitted multiple times. **Apply only to conversion-rate denominators** (L2FL, lead-to-opportunity, etc.) — never to stock / drop-reason / opportunity-list queries, where every actual BSP submission must be visible. See Critical rules for the full decision tree.
- **current valid first lead** (`is_current_valid_first_lead`) → the first lead post-contract for `(lead_hash, uuid_company, business_context, ts_partner_contract_start)`. Use when measuring partner performance under their *current* contract.
- **reason_macro** → high-level classification of the BSP status reason JSON (computed in `enrich_3p_supply.lead_3p_status_changes`, exposed in `dim_current_conversion_funnel`). **`reason_macro` is only semantically meaningful for leads currently in `current_bsp_status = 'NOT_CONVERTED'`** — that is the only state in which the BSP's pending-reason JSON describes actual blockers. For any other status (`PROCESSING`, `REGISTERED`, `UNPUBLISHED`, `SUSPENDED`, `DISCARDED`) the field may still be populated (carried over from prior revisions), but it has **no business meaning** and must not be interpreted as the reason the lead is in its current state. Always co-filter with `current_bsp_status = 'NOT_CONVERTED'` (or `current_conversion_funnel = 'OPPORTUNITY'`, which already implies it). Categories:
  - `DUPLICATED` — lead matches an existing house (`duplicateHouse`, `hybridLead`, `duplicateLead`); when matched, `fact_lead_3p_flows.sk_house_duplicated <> -1`.
  - `NO_OPERATIONAL_INTEREST` — out of scope (polygon, type, price, partner status). **Not actionable** — these are *not* opportunities.
  - `PHOTOS` — image issues (URL/HTTPS, quality, missing photos). Actionable.
  - `OWNER_INFO` — missing or invalid owner contact. Actionable.
  - `LISTING_INFO` — incomplete location, blueprint inconsistencies, IPTU. Actionable.
  - `OTHER` — has reason keys but none matched the predefined buckets.
  - `N/A` — no status reasons at all.
- **eligible pending** (`is_eligible_pending`) → BSP signed at least one pending reason that is *actionable* by the partner.
- **not-eligible pending** (`is_not_eligible_pending`) → BSP signed at least one *disqualifying* pending reason. Any not-eligible pending automatically excludes the lead from being an opportunity.
- **business_context**, **RENT/SALE**, **aluguel/venda** → modality. The fact and conversion-funnel dimension carry one row per `(lead, business_context)` — always filter when the question is modality-specific.
- **BSP status** → `current_bsp_status` values: `PROCESSING`, `NOT_CONVERTED`, `REGISTERED`, `UNPUBLISHED`, `SUSPENDED`, `DISCARDED`.
- **Main status** → `current_main_status` values: `EDITING`, `WAITING_CONFIRMATION`, `PUBLISHED`, etc. — only populated once the lead is registered to main.
- **current_conversion_funnel** → high-level stage label computed in `dim_current_conversion_funnel`. **Purpose: track the L2FL journey** (which stage a lead has *ever* reached), not the current listing state on main. A lead labelled `FIRST_LISTING` has been published at some point but may be currently unpublished, suspended, or back to a different state — to know *what the listing is doing right now*, use `current_main_status` / `current_main_status_reason`, or join to a listing-focused DW model.
  - `FIRST_LISTING` → `ts_first_listing IS NOT NULL` — the lead was published at least once. **Does not imply the listing is currently active.**
  - `AVAILABILITY_CHECK_START` → most recent timestamp is `ts_availability_check_start` (main-side event — listing in `EDITING` / `WAITING_CONFIRMATION` awaiting owner action / availability validation).
  - `AVAILABILITY_CHECK_END` → most recent timestamp is `ts_availability_check_end` and `ts_first_listing IS NULL`. **The availability check completed but the listing was *not* approved for publication** (e.g. owner did not confirm, listing was rejected, draft never advanced). `current_main_status` / `current_main_status_reason` are the diagnostic fields for these stuck leads.
  - `PROCESSING_PHOTOS` → BSP-internal state — `current_bsp_status = 'PROCESSING'` (photos being processed in BSP, before registration to main).
  - `OPPORTUNITY` → BSP-internal state — `current_bsp_status = 'NOT_CONVERTED' AND is_opportunity = TRUE`.
  - `NOT_CONVERTED_BSP`, `UNPUBLISHED_BSP`, `REGISTERED_BSP`, `SUSPENDED_BSP`, `DISCARDED_BSP` → BSP terminal/holding states (status snapshot, regardless of when timestamps were set).
  - `OTHER` → **BSP-internal by construction**. The CASE only reaches this branch when none of the main-side timestamp branches matched (no `ts_first_listing`, `ts_max_value` is not an availability-check timestamp) AND `current_bsp_status` is outside the named set (`NOT_CONVERTED`, `UNPUBLISHED`, `REGISTERED`, `SUSPENDED`, `DISCARDED`, `PROCESSING`). Treat it as a BSP-block value in funnel ordering — never as a main-side or "unknown-stage" lead.

  **Analytical blocks for funnel analysis.** Group the values into two blocks; the BSP block always comes first in any funnel ordering, sort, drop-off chart, or stage-progression visualisation. Within the BSP block, three sub-blocks in this exact order:
  - **BSP block (early)** — eight values, ordered:
    1. *Terminal / post-main / fallback* (leads exited the active funnel): `UNPUBLISHED_BSP`, `SUSPENDED_BSP`, `DISCARDED_BSP`, `OTHER`. By construction, `OTHER` is always inside this BSP block.
    2. *Pending in `NOT_CONVERTED`* (actionable focus): `NOT_CONVERTED_BSP`, `OPPORTUNITY`.
    3. *In-flight progression toward main*: `PROCESSING_PHOTOS`, `REGISTERED_BSP`.
  - **Main block (later)** — `AVAILABILITY_CHECK_START`, `AVAILABILITY_CHECK_END`, `FIRST_LISTING`. These leads have crossed into the main system as draft listings.

  The block boundaries (and the three sub-block boundaries inside BSP) are non-negotiable: terminal/`OTHER` → pending → in-flight → main. Mixing the blocks at the same ordering level (e.g. ordering alphabetically, or interleaving `OTHER` between `AVAILABILITY_CHECK_*` and `FIRST_LISTING`) produces misleading funnel charts. Use a CASE expression on the value to assign a block-aware ordinal when sorting — see "Dos and Don'ts" for the enforced pattern.
- **current_main_status** / **current_main_status_reason** → main-system listing draft status and its reason; this is what tells you the **current state of the listing on main** (e.g. `EDITING`, `PUBLISHED`, unpublished). Two key uses:
  - **Diagnose `AVAILABILITY_CHECK_END` failures** — explain why the availability check did not result in a published listing (owner unresponsive, draft rejected, requirements unmet).
  - **Tell apart "currently published" from "ever published" `FIRST_LISTING` leads** — `current_conversion_funnel = 'FIRST_LISTING'` only proves the lead reached publication once; `current_main_status` indicates whether it is still published right now or has been unpublished/suspended.
  Less interpretable for leads still on the BSP side (`OPPORTUNITY`, `*_BSP`, `PROCESSING_PHOTOS`), where the BSP fields (`current_bsp_status_reason`, `reason_macro`) are the right diagnostic. For deeper analysis of the listing lifecycle (publication / unpublication history, current rent or sale status, listing-level supply attributes), join the lead to a listing-focused DW model via `sk_house`.
- **Portfolio Manager**, **portfolio-manager-api**, **CDI**, **Central da Imobiliária**, **Catálogo de Imóveis** → main-system tool used to publish first listings; identified by `is_first_listing_published_through_portfolio_manager`.
- **`sk_lead_3p_flow`** → flow surrogate computed as `id_lead_3p * 10` for SALE and `id_lead_3p * 10 + 1` for RENT. Same convention applies to `sk_listing_draft_status` (`id_house * 10 + 0/1`).

## Tables

| You need... | Use this table |
|-------------|----------------|
| Lead-flow level metrics, flags, and BSP/main timestamps (1 row per lead × business_context) | `dw_3p_supply.fact_lead_3p_flows` (`f`) — central fact. PK `sk_lead_3p_flow`. Source for `is_opportunity`, `is_valid_first_lead`, `is_current_valid_first_lead`, all `ts_*_in_bsp`, `ts_first_listing`, `ts_partner_contract_start`. |
| Current funnel stage and reason for any lead (snapshot) | `dw_3p_supply.dim_current_conversion_funnel` (`dcf`) — 1 row per `sk_lead_3p_flow`. Source for `current_conversion_funnel`, `reason_macro`, `current_bsp_status` / `current_bsp_status_reason`, `current_main_status` / `current_main_status_reason`. |
| Property attributes — address, pricing, blueprint, owner, access | `dw_3p_supply.dim_lead_3p` (`dl`) — 1 row per lead (`sk_lead_3p`). Note: this is lead-grain, not flow-grain. |
| Photo quality, compliance, and red-flag analytics for a lead's images | `dw_3p_supply.dim_lead_3p_image_inspection` (`dii`) — 1 row per image inspection × lead. Source: `datalake_kodak_clean.image_inspection`. Use `image_inspection_version` to pick the latest set per lead. |

The enrich layer (`datalake_3p_supply.lead_3p`, `lead_3p_status_changes`, `listing_draft_status`, `broker_lead_relationship`) is for debugging lineage only; analytical questions should be answered from the DW tables above.

**Critical rules:**
- **`sk_lead_3p_flow` is the canonical join grain** for `fact_lead_3p_flows` ↔ `dim_current_conversion_funnel`. Do *not* join on `sk_lead_3p` — one lead can have two flows (SALE + RENT) and you will fan out counts.
- **Always filter `business_context` (`'RENT'` or `'SALE'`)** when the question is modality-specific. Both fact and `dim_current_conversion_funnel` carry the column.
- **Sentinel value `-1` for missing surrogate keys** in this domain (`sk_house`, `sk_house_duplicated`, `sk_broker`, `sk_company`, `sk_person_owner_agent`, `sk_listing_draft_status`, `sk_region`). Filter `<> -1` when you need successful matches; do not COUNT them as real entities.
- **When to apply the valid-lead recipe — decision tree.** The recipe (`(ts_partner_contract_start IS NULL AND is_valid_first_lead = TRUE) OR is_current_valid_first_lead = TRUE`) deduplicates BSP submissions: it picks the first valid attempt per `(lead_hash, sk_company, business_context)` group (or per group × partner-contract period). It is **not** the right filter for every question — choose based on the analyst's intent:
  - **APPLY** the recipe (denominator only) when computing **conversion-rate metrics** that need a duplicate-free lead universe: L2FL, lead-to-opportunity, lead-to-anything, partner conversion ratios, cohort funnel rates.
  - **DO NOT APPLY** the recipe when the analyst wants to see the **raw BSP universe** — every actual submission, including duplicates. Examples:
    - "How many leads are in the BSP right now?" / lead stock or inventory questions.
    - "Why are leads stuck in the conversion funnel?" / drop-reason or `reason_macro` analysis.
    - "List all opportunities" / actionable lead lists for OPS.
    - "Funnel stage distribution" / counts by `current_conversion_funnel`.
    - Any per-row analysis of `dim_current_conversion_funnel` or `fact_lead_3p_flows`.
  - **ASK THE USER** when intent is ambiguous (e.g. "leads per partner" — does that mean unique-property attempts or total submissions including duplicates?). Explain the concept in plain terms: *"The same property can be submitted to QuintoAndar multiple times by the same partner — these are duplicate submissions. The 'valid-lead' rule keeps only the first submission per property + partner + modality. Use it for conversion-rate metrics (so duplicates don't inflate the denominator). Don't use it when you want to see every actual lead row in the BSP (stuck reasons, inventory, opportunity lists)."* Then proceed only after the user confirms.
- **L2FL valid-lead recipe — denominator only.** When the recipe **does** apply (per the decision tree above), use it in the **denominator** of L2FL only — `(ts_partner_contract_start IS NULL AND is_valid_first_lead = TRUE) OR is_current_valid_first_lead = TRUE`. **Never apply it to the numerator** (`COUNT(...) WHERE ts_first_listing IS NOT NULL`): the flags identify *the first valid lead*, not necessarily *the lead that persisted through the journey to first listing* — so the duplicate that actually got published can be excluded by the filter, undercounting first listings. Numerator is always the unfiltered first-listing count, denominator is always the valid-lead count. Using `is_valid_first_lead` alone (without the contract-aware OR clause) also underestimates partner-current-contract performance.
- **L2FL cohort instability — rates can exceed 100%.** Because the numerator counts *all* first listings while the denominator counts only valid leads, a cohort whose published lead was an invalid duplicate can produce L2FL > 100% (e.g. 4 valid leads + 1 invalid duplicate, all 5 reach FL → 5 / 4 = 125%). Two ways to handle it depending on the use case:
  - **Cohort analysis (anchored on `ts_business_context_created`)** — use a **valid-lead-attributed numerator** that maps every non-valid submission to the **most recent valid lead at-or-before it** within the same `(lead_hash, sk_company, business_context)` group, then takes the FL outcome per valid-lead segment. This guarantees rate ≤ 100% **and** correctly handles the multi-valid case (see next rule). See Golden Query 4 for the pattern.
  - **Coincident analysis (anchored on `ts_first_listing`)** — the asymmetric pattern (Query 3) is acceptable in aggregate because the small overcount washes out at scale; cap or report L2FL > 100% as a data-quality signal rather than rewriting the metric. The valid-lead-attributed pattern can also be applied if the analysis demands strict ≤ 100% rates.
- **The same `(lead_hash, sk_company, business_context)` group can have multiple valid leads.** Because `is_current_valid_first_lead` flags the first lead under each new partner-contract period, a partner that re-signs creates a new valid lead for the same group. So a single group may contain V1, V2, V3 — each anchored to a different contract period — interleaved with non-valid duplicates. The right grouping for cohort attribution is **not** `(lead_hash, sk_company, business_context)` alone — it must split each non-valid submission into the **most recent valid lead before it in time** (window-function attribution). Naively `GROUP BY (lead_hash, sk_company, business_context)` collapses all valid leads into one group, double-counting FL across contract periods and breaking per-cohort attribution.
- **Opportunity ≠ NOT_CONVERTED**. A lead in `NOT_CONVERTED` may have not-eligible pendings (e.g. out of polygon) and is *not* an opportunity. Always filter `is_opportunity = TRUE` (fact) or `current_conversion_funnel = 'OPPORTUNITY'` (dim) for actionable analysis.
- **`reason_macro` is only valid in `NOT_CONVERTED` BSP status.** The field is computed for every status revision and may be non-null for leads in `PROCESSING`, `REGISTERED`, `UNPUBLISHED`, `SUSPENDED`, or `DISCARDED`, but it carries no business meaning outside `NOT_CONVERTED`. Always pair `reason_macro` aggregations with `current_bsp_status = 'NOT_CONVERTED'` — or, equivalently, `current_conversion_funnel IN ('OPPORTUNITY', 'NOT_CONVERTED_BSP')` — to avoid mis-attributing reasons to leads that are no longer pending.
- **`is_opportunity` (fact) and `current_conversion_funnel = 'OPPORTUNITY'` (dim) are equivalent populations.** Pick whichever requires fewer JOINs — prefer the dim-only filter when `reason_macro` or `current_bsp_status*` are the only other columns needed. Why the equivalence holds: BSP statuses can be updated by main-side events (e.g. unpublishing a listing in Portfolio Manager flips BSP to `UNPUBLISHED`), so the BSP↔Main link is **not strictly one-way**, but once a lead reaches main, its BSP status only moves between **UNPUBLISHED / SUSPENDED / DISCARDED** — it never reverts to `NOT_CONVERTED`. So the only leads with `current_bsp_status = 'NOT_CONVERTED' AND is_opportunity = TRUE` are leads that never made it to main, which is exactly what the dim's `OPPORTUNITY` branch captures — the earlier timestamp-based branches (`FIRST_LISTING`, `AVAILABILITY_CHECK_*`) would otherwise have matched. (`PROCESSING_PHOTOS` is also an earlier branch but it's BSP-internal — it triggers on `current_bsp_status = 'PROCESSING'`, which is mutually exclusive with `NOT_CONVERTED`, so it never collides with the OPPORTUNITY branch.)

## Key Metrics

- **Lead volume** — `COUNT(DISTINCT sk_lead_3p_flow)` from `fact_lead_3p_flows`, optionally grouped by `business_context`.
- **Valid lead volume (L2FL denominator only)** — `COUNT(sk_lead_3p_flow) WHERE (ts_partner_contract_start IS NULL AND is_valid_first_lead) OR is_current_valid_first_lead`. Apply the valid-lead filter only here, never on the FL numerator (see Critical rules).
- **First Listing volume (FL — L2FL numerator)** — `COUNT(sk_lead_3p) WHERE ts_first_listing IS NOT NULL`. **No valid-lead filter** — the published lead may not be the same row flagged as the first valid one.
- **L2FL conversion rate** — `first_listings / valid_leads`, anchored on the period of `ts_business_context_created` (cohort) or `ts_first_listing` (coincident). The denominator carries the valid-lead recipe; the numerator does not.
- **Opportunity count** — `COUNT(*) WHERE is_opportunity = TRUE`, breakdowns by `reason_macro` or `sk_company` / `sk_broker`.
- **Drop-reason breakdown** — `COUNT(*) GROUP BY reason_macro` from `dim_current_conversion_funnel`.
- **Funnel stage distribution** — `COUNT(*) GROUP BY current_conversion_funnel`.
- **Duplicate lead count** — `COUNT(*) WHERE sk_house_duplicated <> -1` (reconcile with `reason_macro = 'DUPLICATED'`).
- **Time to first listing** — `DATE_DIFF('day', ts_business_context_created, ts_first_listing)`.
- **Lead lag from contract start** — `DATE_DIFF('day', CAST(ts_partner_contract_start AS DATE), CAST(ts_business_context_created AS DATE))`.

## Relationships with Other Entities

### Supply (3P is the rede sub-funnel of supply)

- This entity is the granular drill-in into the rede acquisition channel; in `dw_growth.obt_supply` the same population appears as `acquisition_origin = 'rede'` / `nm_supply_source = '3P'`.
- Bridge via house: `f.sk_house = obt.sk_house` (filter `f.sk_house <> -1` and `obt.sk_house <> -1`).
- Use `dw_growth.obt_supply` for end-to-end funnel mixing 1P / CIQ / 3P; use `dw_3p_supply` for partner / broker / BSP-reason analysis on rede only.

### Broker (N:1)

- `f.sk_broker = dw_brokers.dim_broker.sk_broker` (`-1` when not linked) — analytical join. The same key resolves on `core_brokers.brokers.sk_broker` upstream.
- For full broker / partner context — Marketplace business models, broker products, status / tier / account-manager history, agents 3P, and the canonical identification of 3P records in other entities — see [`broker_xp.md`](./broker_xp.md). This entity is the rede sub-funnel under that umbrella.
- For the **demand-side counterpart** of the Marketplace — 3P Demand (TSC) and 3P Lead Gen (CQA) funnels, Buyer Prospects (NBP / RBP), Visit → Offer → CCV sub-stages, drop reasons, broker-demand attribution — see [`3p_demand.md`](./3p_demand.md). Together, supply and demand are the two halves of the same partner business.
- **Post-publication on the main system** (what happens *after* `ts_first_listing`) — daily snapshot of published listings with demand metrics (`dw_sale.fact_daily_ongoing_listing`), search results / LPV events (`dw_public.fact_search_session_event`), listing version timeline (`dw_sale_listings.fact_listings`), and listing status transitions (`dw_sale_listings.fact_listing_status`) — is covered in [`broker_xp.md`](./broker_xp.md), section *"Listings — Visibility and Demand on 3P Supply"*. This entity (`3p_supply.md`) stops at first listing; that section picks up the visibility-to-CCV story on the main system.

### Company (N:1)

- `f.sk_company = datalake_company.company_sks.sk_company` (`-1` when not linked).
- `dim_lead_3p.cnpj` carries the partner CNPJ that submitted the lead — useful for cross-checks.

### Region (N:1)

- `f.sk_region` links to the region dim (`-1` when null on the source lead).

### Person — Owner agent (N:1)

- `f.sk_person_owner_agent = datalake_person.person_sks.sk_person` (`-1` when not linked).

### Image Inspection (1:N — many image rows per lead)

- `dii.sk_lead_3p = dl.sk_lead_3p` and `dii.sk_lead_3p = f.sk_lead_3p`.
- Multiple inspections per lead — pick the latest set with `image_inspection_version = MAX(...)` per `sk_lead_3p` (Trino: subquery + `ROW_NUMBER()`, never `QUALIFY`).

## Dos and Don'ts

**Do:**
- Always join `fact_lead_3p_flows` ↔ `dim_current_conversion_funnel` on `sk_lead_3p_flow` (not `sk_lead_3p`).
- Filter `business_context` for modality-specific questions — every lead has one flow per context.
- For "first lead" questions, clarify whether the user means **all-time** (`is_valid_first_lead`) or **post-current-contract** (`is_current_valid_first_lead`); for L2FL, combine both with the `ts_partner_contract_start IS NULL` clause.
- **Decide whether to apply the valid-lead recipe based on intent**, not by default. Conversion-rate questions → apply (denominator only). Stock / inventory / drop-reason / opportunity-list / per-row analyses → do not apply. When ambiguous, ask the user and explain in plain terms: the recipe deduplicates BSP submissions (same property re-submitted by the same partner), so it's right for rate metrics but wrong when you want to see every actual lead row.
- Use `dim_current_conversion_funnel.current_conversion_funnel` for stage breakdowns; use `reason_macro` for drop-reason analytics — both are pre-computed in enrich.
- **For funnel ordering or stage-sorted charts, always use a block-aware CASE ordinal** so BSP-block values precede main-block values. `OTHER` is BSP-internal by construction and must sit inside the BSP block, never alongside `FIRST_LISTING`. Within the BSP block: terminal / post-main BSP states + `OTHER` come **first**, then pending (`NOT_CONVERTED_BSP`, `OPPORTUNITY`), then in-flight progression to main (`PROCESSING_PHOTOS`, `REGISTERED_BSP`). Recommended pattern:

  ```sql
  CASE current_conversion_funnel
    -- BSP block — terminal / post-main / fallback (leads exited the active funnel)
    WHEN 'UNPUBLISHED_BSP'          THEN 1
    WHEN 'SUSPENDED_BSP'            THEN 2
    WHEN 'DISCARDED_BSP'            THEN 3
    WHEN 'OTHER'                    THEN 4
    -- BSP block — pending in NOT_CONVERTED (actionable focus)
    WHEN 'NOT_CONVERTED_BSP'        THEN 5
    WHEN 'OPPORTUNITY'              THEN 6
    -- BSP block — in-flight progression toward main
    WHEN 'PROCESSING_PHOTOS'        THEN 7
    WHEN 'REGISTERED_BSP'           THEN 8
    -- Main block — draft listing on main system
    WHEN 'AVAILABILITY_CHECK_START' THEN 9
    WHEN 'AVAILABILITY_CHECK_END'   THEN 10
    WHEN 'FIRST_LISTING'            THEN 11
  END AS funnel_order
  ```

  Use `funnel_order` in `ORDER BY` (and when grouping for stacked-bar / Sankey visualisations). The block boundaries are non-negotiable: terminal-BSP/`OTHER` (1–4) → pending-BSP (5–6) → in-flight-BSP (7–8) → main (9–11). Re-ordering rows *within* a sub-block is fine; crossing sub-block or block boundaries (e.g. placing `NOT_CONVERTED_BSP` before `DISCARDED_BSP`, or any main-block value before any BSP-block value) is not.
- Filter `is_opportunity = TRUE` (fact) or `current_conversion_funnel = 'OPPORTUNITY'` (dim) whenever the question targets actionable leads — they are equivalent populations (see Critical rules for the BSP-status-revert reasoning). Prefer the dim-only filter when you don't need other fact columns: it avoids the JOIN.
- Use `sk_house_duplicated <> -1` together with `reason_macro = 'DUPLICATED'` to study duplicate-house cases.
- For partner-level funnel, group by `sk_company` or `sk_broker` and pivot reasons via `reason_macro`.
- When investigating leads stuck at `current_conversion_funnel = 'AVAILABILITY_CHECK_END'` (availability check completed but no listing published), use `current_main_status` and `current_main_status_reason` — *not* `reason_macro` — to understand why publication was blocked. `reason_macro` reflects the BSP side and isn't the right diagnostic for main-side rejections.
- For Trino dedup on `dim_lead_3p_image_inspection`, rewrite with a `ROW_NUMBER()` CTE — the source SQL uses Spark `QUALIFY`, but Trino consumers must not.

**Don't:**
- Don't join fact ↔ funnel on `sk_lead_3p` — one lead has up to two flows (SALE + RENT) and the result will fan out counts.
- Don't use `is_valid_first_lead` alone for L2FL denominators — it ignores the partner-current-contract dimension; combine with `ts_partner_contract_start` and `is_current_valid_first_lead`.
- Don't apply the valid-lead recipe to the L2FL **numerator** (`COUNT(...) WHERE ts_first_listing IS NOT NULL`). The recipe deduplicates leads at the BSP — it identifies *the first valid submission*, not necessarily *the submission that survived the journey to first listing*. Filtering the numerator by the same flags can drop the duplicate that actually got published, undercounting FL. Numerator = unfiltered first listings; denominator = valid leads.
- Don't apply the valid-lead recipe to **stock / inventory / drop-reason / opportunity-list questions**. "How many leads are in the BSP", "Why are leads stuck in the conversion funnel", "List all opportunities", "Funnel stage distribution" — all of these need the **raw submission universe**, including duplicates. Applying the recipe undercounts and hides the BSP's actual workload. The recipe is only for conversion-rate denominators (see Critical rules decision tree).
- Don't silently default either way when the user's intent is ambiguous regarding deduplication. **Ask** ("Do you want unique-property attempts only, or every actual submission including duplicates?") and briefly explain the recipe before proceeding.
- Don't equate `current_bsp_status = 'NOT_CONVERTED'` with "opportunity" — only `is_opportunity = TRUE` filters out leads with disqualifying pendings.
- Don't aggregate or filter on `reason_macro` without also restricting to `current_bsp_status = 'NOT_CONVERTED'` (or `current_conversion_funnel IN ('OPPORTUNITY', 'NOT_CONVERTED_BSP')`). The field can be non-null for leads in `PROCESSING`, `REGISTERED`, `UNPUBLISHED`, `SUSPENDED`, or `DISCARDED` (carried over from prior status revisions), but in those states it does not describe why the lead is in its current state.
- Don't read `current_conversion_funnel = 'FIRST_LISTING'` as "currently published". It only means the listing was published *at some point*; the listing may now be unpublished, suspended, or in another main-side state. For current listing state, use `current_main_status` / `current_main_status_reason`, or join to a listing-focused DW model via `sk_house`.
- Don't confuse `current_bsp_status` (status in BSP) with `current_main_status` (status in main system) — a lead can be `REGISTERED` in BSP and still `EDITING` in main.
- Don't assume `sk_house <> -1` means the lead is published — it means BSP registered it to main; only `ts_first_listing IS NOT NULL` confirms publication.
- Don't query the enrich layer (`datalake_3p_supply.*`) for analytical reporting — DW tables already deduplicate, build flow grain, classify reasons, and compute the opportunity / first-lead flags.
- Don't aggregate `dim_lead_3p` rows expecting flow-grain counts — that table is lead-grain (`sk_lead_3p`); use `fact_lead_3p_flows` for `business_context`-aware aggregates.

## Golden Queries

### Query 1 — Opportunity counts by macro reason

Answered from `dim_current_conversion_funnel` alone — `current_conversion_funnel = 'OPPORTUNITY'` already encodes `is_opportunity = TRUE` and is equivalent (see Critical rules: leads that reached main never revert to BSP `NOT_CONVERTED`, so the only `is_opportunity = TRUE` leads sit in the dim's `OPPORTUNITY` branch).

```sql
SELECT
    reason_macro,
    COUNT(*) AS opportunity_count
FROM dw_3p_supply.dim_current_conversion_funnel
WHERE current_conversion_funnel = 'OPPORTUNITY'
    AND business_context = 'RENT'
GROUP BY reason_macro
ORDER BY opportunity_count DESC
```

### Query 2 — Funnel stage distribution (current snapshot)

Where leads are stuck right now — answers from the funnel dim alone.

```sql
SELECT
    current_conversion_funnel,
    COUNT(*) AS lead_count
FROM dw_3p_supply.dim_current_conversion_funnel
WHERE business_context = 'SALE'
GROUP BY current_conversion_funnel
ORDER BY lead_count DESC
```

### Query 3 — L2FL by month and business context (coincident)

Canonical L2FL pattern. **Denominator** (`valid_leads` CTE) applies the valid-lead recipe to deduplicate BSP submissions; **numerator** (`first_listings` CTE) is the raw first-listing count with no valid-lead filter. Don't mirror the recipe into the numerator — see Critical rules.

```sql
WITH first_listings AS (
    SELECT
        business_context,
        YEAR(ts_first_listing)  AS fl_year,
        MONTH(ts_first_listing) AS fl_month,
        COUNT(sk_lead_3p)       AS first_listings
    FROM dw_3p_supply.fact_lead_3p_flows
    WHERE ts_first_listing IS NOT NULL
    GROUP BY 1, 2, 3
),
valid_leads AS (
    SELECT
        business_context,
        YEAR(ts_business_context_created)  AS ts_year,
        MONTH(ts_business_context_created) AS ts_month,
        COUNT(sk_lead_3p)                  AS leads_created
    FROM dw_3p_supply.fact_lead_3p_flows
    WHERE
        (ts_partner_contract_start IS NULL AND is_valid_first_lead = TRUE)
        OR is_current_valid_first_lead = TRUE
    GROUP BY 1, 2, 3
)
SELECT
    vl.business_context,
    vl.ts_year,
    vl.ts_month,
    vl.leads_created,
    fl.first_listings,
    CAST(fl.first_listings AS DOUBLE) / NULLIF(vl.leads_created, 0) AS l2fl
FROM valid_leads AS vl
INNER JOIN first_listings AS fl
    ON fl.fl_year = vl.ts_year
    AND fl.fl_month = vl.ts_month
    AND fl.business_context = vl.business_context
WHERE vl.business_context = 'SALE'
ORDER BY vl.ts_year, vl.ts_month
```

### Query 4 — L2FL by cohort (valid-lead-attributed, ≤ 100% guaranteed)

Use this when the analysis is **cohort-anchored** (`ts_business_context_created` defines the bucket) and you need rates that cannot exceed 100%. The pattern attributes every non-valid submission to the **most recent valid lead at-or-before it** within the same `(lead_hash, sk_company, business_context)` group, then takes the FL outcome per valid-lead segment. This:

- Bounds the rate at 100% (one boolean per valid lead → numerator ≤ denominator by construction).
- Correctly handles the **multi-valid case**: a single group can contain V1 (cohort X), D1, V2 (cohort Y, new contract), D2 — D1 is attributed to V1 and D2 to V2, so each valid lead's cohort gets its own FL outcome, with no cross-period double counting.
- Drops non-valid submissions that occur **before any valid lead** in the group (no valid lead to attribute to).

```sql
WITH classified AS (
    SELECT
        sk_lead_3p_flow,
        lead_hash,
        sk_broker,
        business_context,
        ts_business_context_created,
        ts_first_listing,
        CASE
            WHEN (ts_partner_contract_start IS NULL AND is_valid_first_lead = TRUE)
                OR is_current_valid_first_lead = TRUE
            THEN TRUE
            ELSE FALSE
        END AS is_valid_lead
    FROM dw_3p_supply.fact_lead_3p_flows
),
attributed AS (
    SELECT
        sk_lead_3p_flow,
        is_valid_lead,
        ts_first_listing,
        LAST_VALUE(CASE WHEN is_valid_lead THEN sk_lead_3p_flow END) IGNORE NULLS OVER (
            PARTITION BY lead_hash, sk_broker, business_context
            ORDER BY ts_business_context_created
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS sk_attributed_valid
    FROM classified
),
fl_per_valid AS (
    SELECT
        sk_attributed_valid AS sk_lead_3p_flow,
        BOOL_OR(ts_first_listing IS NOT NULL) AS group_reached_fl
    FROM attributed
    WHERE sk_attributed_valid IS NOT NULL
    GROUP BY 1
),
valid_cohort AS (
    SELECT
        sk_lead_3p_flow,
        business_context,
        ts_business_context_created
    FROM classified
    WHERE is_valid_lead = TRUE
)
SELECT
    YEAR(vc.ts_business_context_created)  AS cohort_year,
    MONTH(vc.ts_business_context_created) AS cohort_month,
    vc.business_context,
    COUNT(*)                              AS valid_leads,
    COUNT_IF(fpv.group_reached_fl)        AS first_listings,
    CAST(COUNT_IF(fpv.group_reached_fl) AS DOUBLE) / NULLIF(COUNT(*), 0) AS l2fl
FROM valid_cohort AS vc
LEFT JOIN fl_per_valid AS fpv USING (sk_lead_3p_flow)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

**How the attribution works:** the `LAST_VALUE(... IGNORE NULLS) OVER (PARTITION BY group ORDER BY ts_business_context_created ROWS UNBOUNDED PRECEDING)` returns the `sk_lead_3p_flow` of the most recent valid lead at-or-before each row within the same group. For a valid row this returns its own SK; for a non-valid row this returns the SK of the closest preceding valid lead (or NULL if no valid lead has occurred yet in the group). Then `BOOL_OR(ts_first_listing IS NOT NULL) GROUP BY sk_attributed_valid` collapses each valid-lead segment into a single boolean.

### Query 5 — Actionable leads for OPS by reason category

Drill into a specific actionable bucket (e.g. `LISTING_INFO`) for OPS task lists. JOIN `fact_lead_3p_flows` only when you need partner/company/broker keys — for reason-and-status columns the dim alone is enough.

```sql
SELECT
    sk_lead_3p,
    business_context,
    reason_macro,
    current_bsp_status,
    current_bsp_status_reason
FROM dw_3p_supply.dim_current_conversion_funnel
WHERE current_conversion_funnel = 'OPPORTUNITY'
    AND reason_macro = 'LISTING_INFO'
ORDER BY sk_lead_3p
```

### Query 6 — Failed availability checks (stuck on the main side)

Leads whose availability check completed but never resulted in a published listing — `current_main_status` / `current_main_status_reason` explain why publication was blocked. Use `reason_macro` *not* here (it reflects BSP-side pendings, irrelevant once the lead is on main).

```sql
SELECT
    business_context,
    current_main_status,
    current_main_status_reason,
    COUNT(*) AS lead_count
FROM dw_3p_supply.dim_current_conversion_funnel
WHERE current_conversion_funnel = 'AVAILABILITY_CHECK_END'
GROUP BY business_context, current_main_status, current_main_status_reason
ORDER BY business_context, lead_count DESC
```

### Query 7 — Stuck non-opportunity leads (e.g. DUPLICATED, NO_OPERATIONAL_INTEREST)

Funnel dim alone is enough — useful to size the discarded / non-actionable pool.

```sql
SELECT
    dcf.current_conversion_funnel,
    dcf.reason_macro,
    COUNT(*) AS lead_count
FROM dw_3p_supply.dim_current_conversion_funnel AS dcf
WHERE dcf.business_context = 'SALE'
    AND dcf.current_conversion_funnel = 'NOT_CONVERTED_BSP'
GROUP BY dcf.current_conversion_funnel, dcf.reason_macro
ORDER BY lead_count DESC
```

### Query 8 — Lead volume per partner since contract start

Lag of lead arrival relative to the partner's current contract.

```sql
WITH fact_with_lag AS (
    SELECT
        sk_broker,
        business_context,
        sk_lead_3p_flow,
        ts_partner_contract_start,
        ts_business_context_created,
        DATE_DIFF(
            'day',
            CAST(ts_partner_contract_start AS DATE),
            CAST(ts_business_context_created AS DATE)
        ) AS days_contract_to_lead
    FROM dw_3p_supply.fact_lead_3p_flows
)
SELECT
    sk_broker,
    business_context,
    COUNT(DISTINCT CASE
        WHEN ts_partner_contract_start IS NOT NULL AND days_contract_to_lead <= 30
        THEN sk_lead_3p_flow
    END) AS leads_within_30d,
    COUNT(DISTINCT CASE
        WHEN ts_partner_contract_start IS NOT NULL AND days_contract_to_lead <= 90
        THEN sk_lead_3p_flow
    END) AS leads_within_90d,
    COUNT(DISTINCT CASE
        WHEN ts_partner_contract_start IS NOT NULL
         AND CAST(ts_business_context_created AS DATE) <= CURRENT_DATE
        THEN sk_lead_3p_flow
    END) AS leads_until_today,
    COUNT(DISTINCT CASE
        WHEN ts_partner_contract_start IS NULL
        THEN sk_lead_3p_flow
    END) AS leads_pre_contract
FROM fact_with_lag
GROUP BY sk_broker, business_context
```
