# House and Listing

## Ownership

**Data Owner:**
- bruna.prates@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br

## Overview

**House** and **listing** are two grains of the same property domain on QuintoAndar. The **house** is the physical property — a stable identity (apartment, house, unit) with enduring attributes like address, layout, and amenities. The **listing** is the publication of that property on the platform — status, pricing, and demand metrics. One house (`sk_house`) can appear in rent and sale contexts, sometimes in parallel (hybrid listings).

**Only RENT has business listing versioning.** Each rent cycle is keyed by **`sk_house_listing`** (= `id_house` + version) and labeled via **`listing_category_start`**. **SALE has no equivalent lifecycle** — republication does not increment versions or apply relisting rules; sale listing keys are **`sk_house_listing` + `business_context = 'SALE'`** in hybrid tables or **`sk_sale_listing`** in `dw_sale.*` (where `order_version` is only 0 or 1). Both contexts share **`sk_house`**. On hybrid properties, rent evolves through multiple `sk_house_listing` versions; sale follows the key convention of each table layer. Details below.

Analysts must pick the grain before writing SQL:
- **House grain** — property-level questions (rooms, geo, distinct properties, repeat rentals across versions)
- **Listing grain** — publication, inventory, time-to-contract, first listing, ongoing demand (scope RENT vs SALE before picking tables and filters)

The end-to-end lifecycle typically follows:
1. **House creation** — property registered in EBDB (`dw_house.dim_house.ts_created`)
2. **Enrichment** — amenities, entrance keys, catalog info (`fact_house_information_filling`, `dim_house_entrance_history`)
3. **Listing draft** — property prepared for publication (`status = 'EDITING'`)
4. **Publication** — visible on platform (`status = 'PUBLISHED'`, `ts_publication`)
5. **Conversion** — rent listing → contract (`fact_house_listings.sk_contract`); sale listing → CCV (see `domain_entities/fs-transact.md`)

Not every house follows every step. Some are created during supply acquisition and never list; others are delisted and relisted months later under the same `sk_house`. At the EBDB source, each business context has its own row in `listing_business_context`.

**TARS — RENT vs SALE on tables:** state whether a table is rent, sale, or both **only** when this document (or the linked domain entity for that table) **explicitly** documents that scope on the table entry — e.g. **just rent**, **just sale**, **both** (`business_context = 'RENT' | 'SALE'`). Do not use **“RENT only” / “SALE only”** for table scope (here “only” means non-hybrid; hybrids can still exist). Do not infer from `dw_rent` / `dw_sale` prefixes or column names alone.

## Related Metric Entities

- [Listing to Rental (L2R)](../metric_entities/listing_to_rental.md) — official rent listing-version cohort conversion to signed contract (monthly/weekly/daily grains).
- [Listing to Unpublish (L2Unp)](../metric_entities/listing_to_unpublish.md) — publication-cohort conversion to UNPUBLISHED (monthly/weekly/daily/windowed grains).
- [Listing Demand Funnel Conversions](../metric_entities/listing_demand_funnel_conversions.md) — L2VB, L2VC, L2OS, L2TP (RENT), L2CCV (SALE) listing-cohort demand funnel.
- [Listing to Well Priced (L2Wp)](../metric_entities/listing_to_well_priced.md) — publication-cohort share/volume of well-priced rent listings (Pub and 4W snapshots; RENT only).
- [Listing Performance Score](../metric_entities/listing_performance_score.md) — daily 1–5 demand score vs similar listings (RENT and SALE); source `enrich_similarity_score` / `datalake_similarity_score.*`.
- [Ongoing Listings](../metric_entities/ongoing_listings.md) — daily published-inventory volume (RENT and SALE; different table paths).
- [FL (First Listings)](../metric_entities/first_listings_1p.md) — first-time published inventory (also referenced from Supply for acquisition funnel).
- [Supply Retention (Sale)](../metric_entities/supply_retention_sale.md) — month-over-month Sale listing stock flow (FL, republished, churn, CCV) — **local definitions differ from corporate FL/OL**; use only for Supply Retention questions.
- [Credit Metrics](../metric_entities/credit_metrics.md) — credit-policy monitoring metrics that join to listing/proposal grain (Evers, FPD, EC|ES2CS, etc.).
- Owner Activation Listing Churn (H2 2026) — cohort churn OKR (`COUNT DISTINCT` churned / matured at 4w RENT, 8w SALE); **not** unpublish transition volume — see [`metric_entities/owner_activation_listing_churn.md`](metric_entities/owner_activation_listing_churn.md)

## RENT listing versioning

Rent listing versioning separates each **lifecycle cycle** of the same house so metrics (time-to-rent, relisting lag, retention) can be analyzed per cycle. It is a **data/analytics construct** aligned to business rules but **not identical** to the Product listing entity — status-name changes in EBDB are high-maintenance for pipelines.

**`sk_house_listing`** is the rent listing-version key (= `id_house` concatenated with version; last three digits encode version number). One row per version in `dw_rent.dim_house_listing` / `datalake_ebdb_listing.house_listing`.

### When a new rent version starts

A new version **begins at the next `PUBLISHED` status**, even when the trigger event happened earlier (e.g. `SUSPENDED+RENTED` or long `UNPUBLISHED`). A new `sk_house_listing` is created when the house is published after:

| Trigger | Category at creation (`listing_category_start`) |
|---------|--------------------------------------------------|
| First publication ever | **First Listing** |
| Publication after the house was rented (`SUSPENDED+RENTED`) | **Re-Listing** (takes priority over Recovered when both apply) |
| Publication after **84+ days** (12 weeks) unpublished | **Recovered** |
| Publication during **Early Demand** (active contract termination in progress) | New version; flag `is_early_demand = TRUE` — see `domain_entities/closing.md` |

Republication **within 12 weeks** (< 84 days unpublished) **reuses the same** `sk_house_listing`.

### Enrich sources (versioning logic)

| Generation | Table | Notes |
|------------|-------|-------|
| **1.0** (legacy, pre-LBC) | `datalake_ebdb_listing.house_status_version_order` | Built from `house_aud`; triggers on rented (`alugado`) or unpublished (`despublicado`) ≥ 84 days |
| **2.0** (current) | `datalake_ebdb_listing.lbc_status_version_order` | Built from `business_context_history` / LBC audit; integrates 1.0 for houses pre-2020-01-06 |
| Category labels | `datalake_ebdb_listing.house_listing_category` | Derives `listing_category_start` → `dim_house_listing.listing_category_start` |

### Edge-case flags (rent)

- **`is_extended_rental`** — after Early Demand, house returned to rented under the **same** contract (termination canceled or owner opted out of Early Demand after activating it); version incremented but no new contract
- **`has_termination_canceled`** — termination was canceled; usually paired with `is_extended_rental`
- **Next listing navigation (RENT)** — **`sk_house_listing + 1`** navigates to the **next rent version**. Does **not** apply to **SALE** (no version sequence)

## SALE — no business versioning

Sale does **not** follow rent-style listing versioning. Despite enrich tables such as `datalake_sale_listings.sale_status_version_order`, there are **no relisting categories**, **no 84-day republication rules**, and **no version increments above 1** in the business sense.

| Concept                         | SALE behavior |
|---------------------------------|---------------|
| **`sk_sale_listing`**           | JOIN key in **SALE-only** `dw_sale.*` tables (= `id_house` + `order_version`) |
| **Hybrid tables**               | **`sk_house_listing`** + **`business_context = 'SALE'`** — same key column as rent, scoped by context |
| **`order_version`**             | **0** = editing, **1** = published — only these two values; republication does **not** create version 2+ |
| **`listing_category_start`**    | Does not exist for sale |
| **Republication / relisting**   | Track via status and publication timestamps on `dw_sale.dim_listing`, `fact_listings` — not new listing versions |
| **`sale_status_version_order`** | Status transition history — **not** rent-style versioning |

## Glossary and Synonyms

- **House**, **imóvel**, **propriedade** → physical property; grain `dw_house.dim_house.sk_house` (= EBDB `house.id`)
- **Listing**, **anúncio**, **captação publicada** → the property's **publication on the platform** — status, price, and demand lifecycle. Rent cycles are versioned (`sk_house_listing`); sale is not.
- **Listing version key (RENT)** → `sk_house_listing` (= `id_house` + version); increments on business triggers in **RENT listing versioning** above; labeled via `listing_category_start`
- **Listing key (SALE)** → depends on the table: in **hybrid/cross-context tables** (RENT and SALE in the same table), the listing key is **`sk_house_listing`** — filter **`business_context = 'SALE'`** to scope sale rows. In **SALE-only tables** (`dw_sale.*`), the key is **`sk_sale_listing`**. In both cases there is no rent-style versioning; where `order_version` exists on sale-only tables, it is only **0** (editing) or **1** (published)
- **Sale status history** → `sale_status_version_order` — status transitions only; do not interpret as listing version increments
- **Shared house key** → `sk_house` / `id_house` links rent versions, sale star-schema rows, and hybrid cross-context tables
- **Hybrid house**, **imóvel híbrido** → same **`sk_house`**, rent **and** sale active in parallel. Rent cycles through multiple **`sk_house_listing`** versions. For sale: use **`sk_house_listing` + `business_context = 'SALE'`** in hybrid tables, or **`sk_sale_listing`** in `dw_sale.*` only tables. In **`dw_rent.dim_house_listing`**, **RENT takes priority** on hybrid rows — sale status/flags in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`). **Prices and calculators** for either context → `domain_entities/pricing.md` — filter **`business_context`** (**Casio** = RENT, **Girafales** = SALE).
- **id_house / sk_house** → same numeric value; listing tables often use `id_house`, house dims use `sk_house`
- **First Listing**, **primeira captação**, **FL** → **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication detected via `fact_listings.sk_first_publication_date` / `listing_business_context.ts_first_listing` — no `listing_category_start`. Official metric: `metric_entities/first_listings_1p.md`
- **Re-Listing**, **relistagem**, **RL** → **RENT only** — new rent version after prior rental ended (`listing_category_start = 'Re-Listing'`)
- **Recovered**, **recuperado**, **RC** → **RENT only** — republished after 84+ days unpublished (`listing_category_start = 'Recovered'`)
- **NL**, **New Listings**, **novas publicações** → listings **published in a reference period**. **RENT:** FL + RL + RC. **SALE:** FL only. Well-priced cohort variants → **FL2WP / RL2WP / RC2WP** in `metric_entities/listing_to_well_priced.md`
- **OL**, **Ongoing Listings** (corporate) → **published inventory snapshot** on a day — see `metric_entities/ongoing_listings.md`. **Not** the same as Supply Retention (Sale) local OL definition
- **Published**, **publicado** → on-market (`status = 'PUBLISHED'`)
- **Preço do anúncio**, **listing price**, **preço publicado** → **`dw_listing.dim_pricing` + `fact_price_changes`** (`business_context` RENT/SALE) — see `domain_entities/pricing.md`; **not** `dim_house_listing.rent` / `house_rent` / `dim_listing.price`
- **Performance Score**, **Listing Performance Score**, **demand score**, **score de performance** → **`datalake_similarity_score.house_metrics_score`** (`final_score`) — DAG **`enrich_similarity_score`**; see `metric_entities/listing_performance_score.md` — **not** EBDB/OPL/`reverse_demand_score`
- **Last version (RENT)** → current rent listing version (`is_last_version = TRUE` on `dim_house_listing`)
- **Early Demand** → rent listing published during active contract termination; triggers a **new rent version** (`is_early_demand = TRUE`); see **RENT listing versioning** and `domain_entities/closing.md`
- **Amenities** → property features; `dw_house.dim_house_amenities` (current), `dim_house_amenities_version` (history)
- **Entrance model**, **modelo de entrada** → property access method; history in `dim_house_entrance_history`
- **Ongoing listing** → published inventory on a given day; **RENT** and **SALE** use different sources — see `metric_entities/ongoing_listings.md`
- **3P listing** → third-party broker inventory (`is_3p_supply = TRUE`)
- **L2R**, **Listing to Rental**, **Listing2Rental**, **listing → alugado (RENT)** → `metric_entities/listing_to_rental.md` (monthly / weekly / daily / windowed views)
- **L2Unp**, **Listing to Unpublish**, **listing → despublicado** → `metric_entities/listing_to_unpublish.md` — **publication-cohort** rate (listings published in period that unpublished). Not unpublish event volume
- **L2TP**, **Listing to Tenant Prospect** → **RENT only** — listing reached **VB and/or OS** within cohort window
- **L2Wp**, **Listing to Well Priced**, **Total Listings Well Priced**, **Relisting Well Priced - 4W**, **FL2WP**, **RL2WP**, **RC2WP** → `metric_entities/listing_to_well_priced.md` (**RENT only** for category splits; NL/OL breakdown documented there)
- **L2R / L2VB / L2CCV × well priced vs overpriced** → cross-metric slice in `listing_to_well_priced.md` (**Conversion by pricing tier**); L2VB/L2CCV base → `listing_demand_funnel_conversions.md`; L2R base → `listing_to_rental.md`
- **L2VB / L2VC / L2OS / L2CCV** → listing demand funnel cohort conversions; **RENT ≠ SALE** — see `metric_entities/listing_demand_funnel_conversions.md`
- **Despublicações / unpublishes**, **listing unpublished (volume)** → UNPUBLISHED **status transitions** bucketed by **event date** — see **Listing unpublishes** below. For **publication-cohort rate** use **L2Unp** → `metric_entities/listing_to_unpublish.md`
- **Suspensões / listing suspensions (volume)** → **SUSPENDED** **status transitions** bucketed by **event date** — see **Listing suspensions** below. **Not** the same as stock of currently suspended listings (snapshot)
- **Stranded listing** → **RENT only** — published 8+ weeks without contract (`fact_house_listings.sk_stranded_date <> -1`)
- **RENT / SALE**, **aluguel / venda** → business contexts (`business_context`, `listing_business_context`); separate DW stars (`dw_rent.*`, `dw_sale.*`). Only **RENT** has listing versioning and `listing_category_start`
- **OPTED_OUT** → LBC status (`listing_business_context.status`) — owner opted out of a **business context** (RENT or SALE). Source of truth for current exclusion at context grain. See **Exclusion statuses** below
- **EXCLUDED** → audit/API status in `house_listing_status_log.status_to` — event of definitive exclusion via the new state machine. Maps to OPTED_OUT on LBC in the standard exclude flow; not present on every OPTED_OUT row
- **excluido** → legacy **house-level** status (`house.status` / `dim_house_listing.house_status`, Portuguese in `fact_house_listing_status.status_history`). Set only when **all** LBCs of the house are OPTED_OUT — not equivalent to OPTED_OUT on one context alone
- **`house_status`** / **`Imovel.status`** → legacy **house-level** field on `dim_house_listing.house_status` — **not** source of truth for RENT/SALE operational status today; see **House.status vs LBC** below
- **`status_change_reason`** → **default** status-change reason code on `fact_house_listing_status` / `fact_listing_status` — valid for **all** cases (3P, non-deactivation, 1P when `deactivation_*` is NULL). **Not deprecated**
- **`deactivation_reason`** / **`deactivation_reason_category`** / **`deactivation_additional_context`** → **1P owner deactivation only** (unpublish / owner suspend), enriched from `house_listing_status_log` since 2026-02-03 — use **when populated**; see **Status reasons — which column to use**
- **`SUSPENDED` + `RENTED`** → **alugado** — operational suspension after contract signed; **not** owner pause. Always read `status_reason` with `SUSPENDED` — see **SUSPENDED + `status_reason`**

## Listing status lifecycle

Source of truth for **current** status per business context: `datalake_ebdb_clean.listing_business_context` (`status`, `status_reason`) — one row per house × context (RENT or SALE).

### Q: What does each listing status mean?

| Status | Meaning | Receives demand? |
|--------|---------|------------------|
| **EDITING** | Draft — not yet published for this context. After the first publication, the listing does not return to EDITING. | No |
| **PUBLISHED** | Currently published on the platform. | Yes |
| **SUSPENDED** | Off-market **temporarily** — meaning depends on **`status_reason`**. **Not** always an owner pause. See **SUSPENDED + `status_reason`** below. | No |
| **UNPUBLISHED** | Disabled for an indefinite period. Reversible — owner may republish. Many "owner gave up" cases land here (not OPTED_OUT). | No |
| **OPTED_OUT** | Owner opted out of this business context — **permanent logical exclusion**. Reversible only in limited cases. Always read `status_reason`. | No |

### Q: What does SUSPENDED mean? Always read `status_reason`

**`SUSPENDED` alone is ambiguous.** The status only says the listing is not receiving demand; **`status_reason`** (LBC: `listing_business_context.status_reason`, `dim_house_listing.house_rent_status_reason` / `house_sale_status_reason`; history: `status_change_reason` on `fact_house_listing_status` / `fact_listing_status`) tells you **why**.

**When answering “what does each listing status mean?”, always mention this for SUSPENDED.**

| `status_reason` (with `SUSPENDED`) | Meaning | Owner-initiated pause? |
|-----------------------------------|---------|------------------------|
| **`RENTED`** | **Alugado** — rental contract signed (or equivalent success path); listing suspended **operationally** because the house is rented. **Most common `SUSPENDED` case on RENT.** CDP/API may expose this as `CONTRACT_ONGOING`. | No — conversion success |
| **`ContractDraft`**, **`HouseReserved`**, **`PaidGuarantee`**, **`RENTAL_GUARANTEE`**, **`ProposalDocumentationApproved`**, **`ProposalDocumentationSentToCardiff`**, **`CCV_SIGNED`** | Listing suspended while an **offer/contract is in progress** (advanced funnel stage). Not published, not “owner gave up”. CDP/API may map to `ADVANCED_OFFER`. | No — demand in progress |
| **`OwnerTemporarilySuspended`**, **`OwnerReforming`**, **`OwnerTraveling`** | Owner **chose a temporary pause** (1P deactivation suspend). Prefer `deactivation_*` when enriched post Feb 2026. | Yes |
| **`OWNER_GAVE_UP_RENTING`**, **`OWNER_GAVE_UP_SALE`**, **`OwnerConsequencesManagement`** | Can appear on `SUSPENDED` in the deactivation gate — owner-driven; read full reason context. | Often yes (context-dependent) |
| **`RELISTING`** / **`RELISTING_*`** | Versioning / relisting transition — operational, tied to rent listing lifecycle. | No |

**Legacy rent history:** `status_history = 'suspenso'` with `status_change_reason = 'alugado'` is the pre-LBC equivalent of **`SUSPENDED` + `RENTED`**.

**Do not equate every `SUSPENDED` row with “owner paused the listing”.** Filter or group by `status_reason` / `status_change_reason`. For “how many are rented right now?”, use **`status = 'SUSPENDED' AND status_reason = 'RENTED'`** (LBC) or the history equivalent — not `SUSPENDED` alone.

```sql
-- RENT: currently rented (operational SUSPENDED, not owner pause)
SELECT COUNT(DISTINCT id_house)
FROM datalake_ebdb_clean.listing_business_context
WHERE business_context = 'RENT'
  AND status = 'SUSPENDED'
  AND status_reason = 'RENTED';
```

### Q: Are OPTED_OUT, EXCLUDED, and excluido the same thing?

**Partially.** They describe the same **definitive exclusion** operation at different layers, but they are **not interchangeable** and do **not** cover all cases of "owner gave up."

| Layer | Status value | Where in the lake | What it represents |
|-------|--------------|-------------------|--------------------|
| State machine / audit (new API) | **EXCLUDED** | `datalake_ebdb_clean.house_listing_status_log.status_to` | Definitive exclusion **event** for one listing context (RENT or SALE) |
| Listing per context (LBC) | **OPTED_OUT** | `datalake_ebdb_clean.listing_business_context.status` (+ `house_rent_status` / `house_sale_status` on `dim_house_listing`) | Persisted exclusion on the business context — standard exclude flow writes OPTED_OUT here |
| House legacy (Imovel) | **excluido** | `house.status` → `dim_house_listing.house_status`; history as `excluido` in `fact_house_listing_status.status_history` | Whole-house exclusion — set **only when every LBC on the house is OPTED_OUT** |

**Typical exclude flow (RENT `DELETE …/deactivation/exclude`):**

```
State machine → EXCLUDED (audit log)
       → OPTED_OUT on LBC (RENT or SALE)
       → excluido on Imovel only if ALL LBCs are OPTED_OUT
```

**When the three do NOT appear together:**

| Scenario | What happens |
|----------|--------------|
| **Hybrid house — exclude RENT only** | LBC RENT = OPTED_OUT + log EXCLUDED for rent; `house_status` may stay **publicado** while SALE is active |
| **Cross-sell opt-out before publish** | LBC OPTED_OUT with `status_reason = REMOVED_FROM_CONTEXT_BEFORE_PUBLISHING` — may **not** produce EXCLUDED in the audit log |
| **Legacy house field (`Imovel.status`)** | When LBC becomes **OPTED_OUT**, the product does **not** automatically write `excluido` on the legacy house. The `StatusImovel` mapper translates OPTED_OUT → **`despublicado`** on `house.status`. **`excluido`** on the house is a separate step — set only by the exclude post-action (when **all** LBCs are OPTED_OUT) or by the legacy `excluir()` flow. Do not infer OPTED_OUT from `house_status = 'excluido'` alone, or assume `excluido` whenever LBC is OPTED_OUT. |

### Q: Does "owner gave up" always mean OPTED_OUT / EXCLUDED / excluido?

**No.** Temporary or reversible give-up uses other statuses:

| Owner intent | Typical status | Reversible? |
|--------------|----------------|-------------|
| Paused / temporarily unavailable | **SUSPENDED** or **UNPUBLISHED** | Yes |
| Gave up renting/selling (deactivation, not exclude) | **UNPUBLISHED** — e.g. `reason_category` RENT_GAVE_UP / SALE_GAVE_UP in `house_listing_status_log` uses UNPUBLISH, not EXCLUDE | Yes |
| Removed one context before publishing (hybrid cross-sell) | **OPTED_OUT** on that LBC (`REMOVED_FROM_CONTEXT_BEFORE_PUBLISHING`) | Partially |
| Definitive exclusion / delete listing or house | **EXCLUDED** → **OPTED_OUT** → (eventually) **excluido** | No (logical deletion) |

### Which columns to use in queries

**Always prefer DW tables (`dw_rent.*`, `dw_sale.*`, `dw_listing.*`, `dw_house.*`) when a modeled table or column exists.** Use enrich (`datalake_ebdb_listing.*`, `datalake_sale_listings.*`) or clean (`datalake_ebdb_clean.*`) only when there is no DW equivalent — e.g. raw audit events not yet modeled as facts.

| Question | Use (DW first) |
|----------|----------------|
| **Listing price** — current or historical (**preço do anúncio**, RENT or SALE) | **`dw_listing.dim_pricing`** + **`dw_listing.fact_price_changes`** — `is_last_price = TRUE` for current; full history via `ts_price_started` / `ts_price_ended` + `business_context`. See `domain_entities/pricing.md` — **not** `dim_house_listing.rent` / `house_rent` / `dim_listing.price` |
| **Performance Score** / **demand score** (RENT or SALE) | **`datalake_similarity_score.house_metrics_score`** — column **`final_score`**; peers in **`similar_houses`**. DAG **`enrich_similarity_score`**. See `metric_entities/listing_performance_score.md` |
| Current status per context (RENT/SALE) | **`dw_rent.dim_house_listing.house_rent_status`** / **`house_sale_status`** — fallback: `datalake_ebdb_clean.listing_business_context.status` |
| Why the listing is inactive | **`house_rent_status_reason`** / **`house_sale_status_reason`** on `dim_house_listing` — fallback: `listing_business_context.status_reason` |
| Status **history** intervals (RENT) | **`dw_rent.fact_house_listing_status`** — `status_history` mixes legacy Portuguese (`excluido`, `despublicado`, `publicado`) and new English (`OPTED_OUT`, `UNPUBLISHED`) |
| Status **history** intervals (SALE) | **`dw_sale.fact_listing_status`** |
| Whole house excluded? | **`dw_rent.dim_house_listing.house_status = 'excluido'`** — only when all contexts opted out; **not** a substitute for per-context OPTED_OUT |
| Rent listing version status | **`dw_rent.dim_house_listing.status`** (version grain); on hybrids prefer **`house_rent_status`** for latest LBC |

**Do not confuse:**

- **`excluido`** (legacy house) ≠ **`OPTED_OUT`** (one LBC context) ≠ **`EXCLUDED`** (audit event)
- **`OPTED_OUT`** ≠ **`UNPUBLISHED`** — UNPUBLISHED is reversible deactivation; OPTED_OUT is permanent context exclusion
- **`status`** on `dim_house_listing` (rent version) vs **`house_rent_status`** / **`house_sale_status`** (latest LBC) — on hybrid rows, prefer LBC columns for current context status
- **Listing price** on **`dim_house_listing.rent` / `house_rent`** or **`dim_listing.price`** ≠ official price — use **`dw_listing.dim_pricing`** + **`fact_price_changes`** (`domain_entities/pricing.md`)

## House.status vs ListingBusinessContext (LBC)

**`house.status` (`dim_house_listing.house_status`) is legacy** — from when QuintoAndar had rent-only listings. It is **not** the source of truth for current operational status per business context. For **which columns and DW tables to query**, see **Which columns to use in queries** above.

**Do not infer RENT/SALE operational status from `house_status` values** such as `publicado`, `despublicado`, `suspenso`, `edicao` — those reflect the old rent-centric house model. Pipeline and product logic must read **LBC** (via `house_rent_status` / `house_sale_status` on `dim_house_listing`).

**Exception — `excluido`:** the only meaningful **whole-house** flag on `house.status`. Means the property is globally excluded (all contexts opted out). It does **not** replace per-context OPTED_OUT on LBC for hybrid partial exclusions.

## Status reasons — which column to use

Two reason sources on status history facts — **pick by case**; they are **not** interchangeable via `COALESCE`:

| Source | Fields | When to use |
|--------|--------|-------------|
| **LBC status reason (default)** | **`status_change_reason`** | **Always valid** for status-change reason on interval facts. Use for **3P**, **non-deactivation** transitions, periods before the deactivation log, and **1P deactivation rows where `deactivation_*` is NULL** (~26% post-launch match gap). **Not deprecated.** |
| **1P owner deactivation taxonomy** | **`deactivation_reason`**, **`deactivation_reason_category`**, **`deactivation_additional_context`** | **Only** for **1P owner deactivation** (unpublish or owner-initiated temporary suspend) when enriched from `house_listing_status_log` since **2026-02-03**. Prefer these over `status_change_reason` **when populated** for that case. |

### Decision tree (for TARS)

```
Reason for the status change?
│
├─ 1P owner deactivation (UNPUBLISH or owner-initiated SUSPEND)?
│   ├─ deactivation_* populated → use deactivation_reason, deactivation_reason_category, deactivation_additional_context
│   └─ deactivation_* NULL → use status_change_reason (3P, pre-log, match failure, or operational suspend)
│
└─ Any other case (3P, OPTED_OUT, operational transition, history, etc.)
    → use status_change_reason
```

**`status_history`** classifies the interval type: `UNPUBLISHED` = unpublish; `SUSPENDED` = suspend **only when owner-initiated** (see gate below) — most `SUSPENDED` rows are **operational** (e.g. rented).

**Where both columns live (DW):**

| Context | Enrich | DW fact |
|---------|--------|---------|
| RENT | `datalake_ebdb_listing.house_listing_status` | `dw_rent.fact_house_listing_status` |
| SALE | `datalake_sale_listings.sale_listing_status` | `dw_sale.fact_listing_status` |

**What counts as “1P owner deactivation”?** UNPUBLISH or temporary SUSPEND identified by a **gate** on `(status_history, status_change_reason)` — **not** every `SUSPENDED` row (~3.6M rent rows include operational suspensions like RENTED).

| Deactivation type | `status_history` in gate | Examples of `status_change_reason` (gate identifier — use `deactivation_*` for reason detail when enriched) |
|-------------------|--------------------------|-------------------------------------------------------------------------------------------------------------|
| Unpublish (UNPUBLISH) | UNPUBLISHED | RENT: `OWNER_REQUESTED_TERMINATION`, `OWNER_GAVE_UP_RENTING`, `HOUSE_NOT_AVAILABLE`, `OWNER_OTHER`, … · SALE: `OWNER_GAVE_UP_SALE`, `OWNER_ALREADY_SOLD_HOUSE`, `HOUSE_NOT_AVAILABLE`, `OWNER_OTHER`, … |
| Temporary suspend (SUSPEND) | SUSPENDED | `OWNER_GAVE_UP_RENTING` / `OWNER_GAVE_UP_SALE`, `OwnerTemporarilySuspended`, `OwnerReforming`, `OwnerTraveling`, … |

**Scope of `deactivation_*`:** only **1P** listings (`is_rent_3p_supply` / `is_sale_3p_supply = false`) that pass the gate **and** match a log event within **±2 minutes** of `ts_status_started`. Post-launch match rate ~**74% RENT / 73% SALE**; remaining eligible rows keep **`status_change_reason`** as the reason source.

**Coverage by period:**

| Period | `status_change_reason` | `deactivation_*` |
|--------|------------------------|------------------|
| Pre-2020-01-06 | Unstructured PT + free text | NULL |
| 2020-01-06 → 2026-02-02 | Structured LBC codes | NULL (log not available) |
| Since 2026-02-03 | **Still populated on every row** — use when `deactivation_*` is NULL or question is outside 1P deactivation | Populated when gate + log match (1P deactivation only) |

**Examples:**

```sql
-- 1P deactivation with new taxonomy (RENT, post Feb 2026)
SELECT
    sk_house_listing,
    status_history,
    deactivation_reason_category,
    deactivation_reason,
    deactivation_additional_context
FROM dw_rent.fact_house_listing_status
WHERE country_code = 'BR'
  AND deactivation_reason IS NOT NULL;

-- 3P or any row where deactivation_* is NULL — status_change_reason is correct
SELECT
    sk_house_listing,
    status_history,
    status_change_reason
FROM dw_rent.fact_house_listing_status
WHERE country_code = 'BR'
  AND deactivation_reason IS NULL
  AND status_history IN ('UNPUBLISHED', 'despublicado');
```

**Pitfalls — common mistakes when using reason columns:**

1. **Do not call `status_change_reason` “legacy” or deprecated.** It is the **standard LBC reason code** on status intervals. Outside 1P deactivation (or when `deactivation_*` is NULL), **use it**.

2. **Do not treat every `SUSPENDED` row as owner deactivation.** Most rent status-history rows with `status_history = 'SUSPENDED'` are **operational** suspensions (e.g. listing rented — `RENTED`), not the owner asking for a temporary pause. For owner-initiated suspend with enriched taxonomy, use `deactivation_*`; otherwise `status_change_reason`.

3. **Do not infer “no owner deactivation” from NULL `deactivation_*`.** NULL means: not 1P deactivation scope, before **2026-02-03**, failed gate (operational suspend), or no log match within **±2 minutes**. **`status_change_reason`** is still the valid reason column for those rows.

4. **`deactivation_reason` NULL with `deactivation_additional_context` populated is valid.** Partial enrichment can occur — do not discard the row or treat it as a pipeline bug.

5. **Do not COALESCE `deactivation_*` with `status_change_reason`.** Pick the column that applies to each row per the decision tree above; report both side by side when comparing — never `COALESCE(deactivation_reason, status_change_reason)`.

6. **Do not expect `deactivation_*` on versioning / category pipelines.** Tables such as `business_context_history`, `lbc_status_version_order`, and `sale_status_version_order` expose **`status_reason`** only. For the 1P deactivation taxonomy, query **`dw_rent.fact_house_listing_status`** or **`dw_sale.fact_listing_status`**.

**Quick reference:**

| Your question | Column(s) |
|---------------|-----------|
| Reason for **any** status change (default) | `status_change_reason` |
| **1P owner deactivation** reason (unpublish / owner suspend) when enriched | `deactivation_reason`, `deactivation_reason_category`, `deactivation_additional_context` |
| **3P**, pre-2026, or 1P deactivation with NULL `deactivation_*` | `status_change_reason` |
| “Did the **owner** deactivate?” (not operational suspend) | Gate pairs above **or** `deactivation_* IS NOT NULL` — not `status_history = 'SUSPENDED'` alone |

Raw events: `datalake_ebdb_clean.house_listing_status_log` (+ join to `house_event_log` for house, context, actor).

## Tables

### House grain

| You need... | Use this table |
|-------------|----------------|
| Canonical house attributes (address, rooms, geo, condo, IPTU) | `dw_house.dim_house` (`dh`) — one row per house; PK `sk_house` |
| Current amenities snapshot | `dw_house.dim_house_amenities` — join on `sk_house` |
| Amenities change history (SCD) | `dw_house.dim_house_amenities_version` |
| Entrance/key access events | `dw_house.dim_house_entrance_history` |
| House info catalog changes; 3P broker attribution | `dw_house.fact_house_information_filling` — `sk_broker <> -1` for broker-level |
| Wide denormalized house (enrich; 3P flags, publication dates) | `datalake_ebdb_listing.house` — prefer `dim_house` for stable attrs |

### Listing grain — For Rent (`sk_house_listing`)

Rent is the only context with **`listing_category_start`** (First Listing / Re-Listing / Recovered). Each row in `dim_house_listing` is one rent listing version; republication rules determine whether a new `sk_house_listing` is created.

**`dw_rent.dim_house_listing` is rent-first.** On **hybrid** houses, the row grain, versioning, and core listing attributes (`status`, `listing_category_start`, `rent`, etc.) reflect **RENT** — not sale. Sale-side status/flags on the same row appear in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`, `is_sale_3p_supply`). **Official price changes and calculator output** for either context are not on this table — use `domain_entities/pricing.md` with **`business_context`** (Casio = RENT, Girafales = SALE). For full sale listing analysis, use **`dw_sale.dim_listing`**.

The table can also include **sale-only** houses (`is_for_rent = FALSE`, `is_for_sale = TRUE`) — properties with a SALE business context but no rent listing versioning history. On those rows, **generic attributes** not exclusive to RENT (e.g. `status`) reflect **SALE**; RENT-only fields (`listing_category_start`, `rent`, etc.) do not apply. Use `dw_sale.*` for full sale listing metrics.

| You need... | Use this table |
|-------------|----------------|
| Rent listing attributes at version grain | `dw_rent.dim_house_listing` (`dhl`) — PK `sk_house_listing`; house via `id_house`; `listing_category_start`; hybrid: sale attrs in `*sale*` columns; sale-only: generic attrs for SALE; flags `is_for_rent`, `is_for_sale` |
| **Listing price** (RENT or SALE, current or historical) | **`dw_listing.dim_pricing` + `fact_price_changes`** — join `sk_house` + `business_context`; see `domain_entities/pricing.md` — **not** `dhl.rent` / `house_rent` |
| Rent lifetime metrics (days-to-contract, next listing, rental count) | `dw_rent.fact_house_listings` (`fhl`) — rent-filtered at build time; join on `sk_house_listing` |
| Rent listing status history (intervals) — **just rent** | **`dw_rent.fact_house_listing_status`** — `status_change_reason` (default reason) + `deactivation_*` (1P owner deactivation, from 2026-02-03); grain `sk_house_listing` |
| 1P owner deactivation reason (enriched) — **just rent** | `deactivation_reason`, `deactivation_reason_category`, `deactivation_additional_context` on **`dw_rent.fact_house_listing_status`** — when populated; otherwise `status_change_reason` |
| Current LBC status per context | `listing_business_context` or `dim_house_listing.house_rent_status` / `house_sale_status` |
| Deactivation audit events (raw) | `datalake_ebdb_clean.house_listing_status_log` |
| Daily listing snapshot (PP Multi, partner, occupant) | `dw_rent.fact_house_listing_daily_infos` — PK `sk_house_listing_day` |
| Enrich versioning logic (1.0 legacy) | `datalake_ebdb_listing.house_status_version_order` |
| Enrich versioning logic (2.0 current) | `datalake_ebdb_listing.lbc_status_version_order` |
| Category derivation | `datalake_ebdb_listing.house_listing_category` → `listing_category_start` on `dim_house_listing` |

### Listing grain — For Sale

Sale has **no business listing versioning** — only `order_version` **0** (editing) or **1** (published) on SALE-only tables. No `listing_category_start`.

**Pick the sale listing key by table type:**
- **Hybrid/cross-context tables** (RENT + SALE together) → **`sk_house_listing`** + **`business_context = 'SALE'`** (e.g. `dw_listing.dim_pricing`, `dw_listing.fact_price_changes`)
- **SALE-only tables** (`dw_sale.*`) → **`sk_sale_listing`**

| You need... | Use this table                                                                                                                                                 |
|-------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sale listing attributes | `dw_sale.dim_listing` (`dl`) — PK `sk_sale_listing`; house via `sk_house`; `order_version` ∈ {0, 1}                                                            |
| **Listing price** (SALE, current or historical) | **`dw_listing.dim_pricing` + `fact_price_changes`** — `business_context = 'SALE'`; **not** `dl.price` for official analytics |
| Sale lifetime metrics (publication funnel, demand totals) | `dw_sale.fact_listings` (`fl`) — join on `sk_sale_listing`; first publication via `sk_first_publication_date`; last publication via `sk_last_publication_date` |
| Daily published inventory + demand | `dw_sale.fact_daily_ongoing_listing` — only `PUBLISHED` days; PK `sk_snapshot`                                                                                 |
| Sale listing status history (intervals) — **just sale** | **`dw_sale.fact_listing_status`** — `status_change_reason` (default reason) + `deactivation_*` (1P owner deactivation, from 2026-02-03); includes `sk_broker` for 3P; grain `sk_sale_listing` |
| Sale status transition enrich (not versioning) | `datalake_sale_listings.sale_status_version_order` — status transitions; `order_version` does not increment beyond 1 for business relistings |
| Definitive exclusion audit events (EXCLUDED) | `datalake_ebdb_clean.house_listing_status_log` — filter `business_context = 'SALE'` via event log join |

### Cross-cutting

| You need...                                                | Use this table |
|------------------------------------------------------------|----------------|
| **Listing Performance Score** (1–5 demand vs similars)   | **`datalake_similarity_score.house_metrics_score`** — `final_score`; DAG **`enrich_similarity_score`**. Peers: **`similar_houses`**. See `metric_entities/listing_performance_score.md` |
| Lead → first listing supply funnel                         | `dw_public.fact_house_listing_flows` |
| Termination → relisting / rerental on next listing version | `dw_offboarding.fact_house_listing_terminations` — see `domain_entities/termination.md` |

**Critical rules:**
- **`listing_category_start` is RENT-only** — never filter it on sale tables; sale FL uses first-publication dates (`metric_entities/first_listings_1p.md`).
- **Listing versioning is RENT-only** — see **RENT listing versioning** section. Sale: `order_version` 0/1 only; no relisting categories.
- **`dim_house_listing` is rent-first on hybrids** — RENT drives row grain and core attrs; read sale from `*sale*` columns or use `dw_sale.dim_listing`. **Sale-only rows** (`is_for_rent = FALSE`): generic (non-RENT-exclusive) attrs reflect SALE.
- **Sale listing key depends on table type** — hybrid tables: `sk_house_listing` + `business_context = 'SALE'`; SALE-only tables (`dw_sale.*`): `sk_sale_listing`. Do not join `dw_sale.*` to hybrid tables on `sk_sale_listing = sk_house_listing`.
- **`sk_house` bridges hybrid houses** — same house, separate rent version lifecycle vs sale rows keyed as above.
- **Hybrid houses** — same `sk_house`; rent and sale are separate tracks with different key conventions per table layer.
- **`dim_house` does not carry 3P flags, current rent/sale price, or broker keys** — use listing dims or enrich `datalake_ebdb_listing.house` for 3P; for **price** use **`dw_listing.dim_pricing`** (`domain_entities/pricing.md`), not `dim_house_listing.rent` / `dim_listing.price`. For 3P broker at house grain: `fact_house_information_filling.sk_broker <> -1`.
- **Join key naming:** `dim_house_listing.id_house = dim_house.sk_house` (rent); `dim_listing.sk_house = dim_house.sk_house` (sale).
- **Schema vs DAG name:** DAG `dw_listing` → `dw_rent.*`; DAG `dw_sale_listings` → `dw_sale.*`.
- **Next listing navigation (RENT):** `sk_house_listing + 1` for the next rent version. **SALE:** do not use `+ 1`.
- **Current state:** `is_last_version = TRUE` + `status = 'PUBLISHED'` for on-market inventory.
- **Partition filter:** `country_code = 'BR'` (or `'MX'`) on listing/enrich tables.
- **Legacy duplicate:** prefer `dw_rent.*` over `dw_public.dim_house_listing`.
- **`house_status` is legacy** — use LBC (`house_rent_status` / `house_sale_status`) for current context status; only `excluido` is a whole-house signal.
- **Status change reason:** `status_change_reason` on status facts — **default** for all cases. For **1P owner deactivation** when enriched, prefer `deactivation_*`; see **Status reasons — which column to use**. Never treat all SUSPENDED as owner deactivation.
- **DataHub CI:** concrete `schema.table` names only — never wildcards.
- **Exclusion statuses:** use LBC `OPTED_OUT` for context-level exclusion; `house_listing_status_log` for EXCLUDED events; `excluido` only for whole-house legacy status. "Owner gave up" often → UNPUBLISHED, not OPTED_OUT.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** L2R, demand-funnel conversions, ongoing listings, first listings, and Supply Retention (Sale). The bullets below are **component** metrics at house or listing grain.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| L2R / listing to contract signed (RENT) | [Listing to Rental (L2R)](../metric_entities/listing_to_rental.md) |
| L2Unp / listing to unpublish (publication cohort) | [Listing to Unpublish (L2Unp)](../metric_entities/listing_to_unpublish.md) |
| L2VB, L2VC, L2OS, L2TP, L2CCV | [Listing Demand Funnel Conversions](../metric_entities/listing_demand_funnel_conversions.md) |
| L2Wp / well priced cohort share (RENT) | [Listing to Well Priced (L2Wp)](../metric_entities/listing_to_well_priced.md) |
| Listing Performance Score (RENT / SALE) | [Listing Performance Score](../metric_entities/listing_performance_score.md) |
| Daily ongoing published inventory | [Ongoing Listings](../metric_entities/ongoing_listings.md) |
| FL / First Listings 1P/3P | [FL (First Listings)](../metric_entities/first_listings_1p.md) |
| Sale supply retention (FL/republished/churn/CCV stock flow) | [Supply Retention (Sale)](../metric_entities/supply_retention_sale.md) |

### Component / exploratory metrics

#### House grain

- Distinct houses (`COUNT(DISTINCT dim_house.sk_house)`)
- Houses by city/region (`dim_house.sk_region` → `dw_public.dim_region`)
- Repeat-rental houses (`fact_house_listings.nr_renting > 1`)

#### Listing grain

- First Listings — **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication date on `fact_listings` (official definition in [FL (First Listings)](../metric_entities/first_listings_1p.md))
- **Ongoing listings (daily volume)** — RENT and SALE; official definition in [Ongoing Listings](../metric_entities/ongoing_listings.md)
- Current published inventory snapshot (`status = 'PUBLISHED'`; rent also uses `is_last_version = TRUE`) — point-in-time, not the daily series above
- **L2R (Listing to Rental)** — see [Listing to Rental (L2R)](../metric_entities/listing_to_rental.md) for the official cohort definition
- **L2Unp (Listing to Unpublish)** — publication-cohort rate; see [Listing to Unpublish (L2Unp)](../metric_entities/listing_to_unpublish.md). **Not** the same as unpublish volume below
- **Listing unpublishes (volume)** — transition count by **unpublish event date** — see **Listing unpublishes** below
- **Listing suspensions (volume)** — transition count by **suspend event date** — see **Listing suspensions** below
- Relisting / rerent lag — **RENT only:** `days_ended_rental_to_relisting`, `days_relisting_to_re_rental`
- Sale funnel velocity — **SALE:** `fact_listings.days_first_publication_to_*`
- 3P vs 1P listing volume (`is_3p_supply`)

## Listing unpublishes (volume)

**Listing unpublishes** counts **status transitions into UNPUBLISHED** — each time a listing enters an unpublished interval. Requires **status history** (interval facts), not `dim_* .status` snapshot alone.

**Not L2Unp:** this section buckets by **unpublish event date**. For the **publication-cohort conversion rate** (listings published in a period that later unpublished), use [Listing to Unpublish (L2Unp)](../metric_entities/listing_to_unpublish.md).

| Context | Source of truth (DW) | Listing key | Event timestamp |
|---------|----------------------|-------------|-----------------|
| **RENT** | `dw_rent.fact_house_listing_status` | `sk_house_listing` | `ts_status_start` |
| **SALE** | `dw_sale.fact_listing_status` | `sk_sale_listing` | `ts_status_started` |

**Included:** new **`UNPUBLISHED`** intervals starting in the reference period.

**RENT filter:** `status_history IN ('UNPUBLISHED', 'despublicado')`

**SALE filter:** `status_history = 'UNPUBLISHED'`

**Excluded (unless requested):** `SUSPENDED`, `OPTED_OUT`, `EDITING`, `PUBLISHED`; counting **current** unpublished listings without a transition event.

**Not the same as:** deactivation totals that merge UNPUBLISHED + SUSPENDED — clarify if the question says “unpublished **or** suspended”. **Not the same as** Owner Activation **cohort churn OKR** — point-in-time status at publication + N weeks; includes EDITING (SALE) and filtered SUSPENDED (RENT); see [`metric_entities/owner_activation_listing_churn.md`](metric_entities/owner_activation_listing_churn.md).

**Unpublish reason:** on the **event**, use **`deactivation_*`** for **1P owner deactivation** when populated; otherwise **`status_change_reason`**. See **Status reasons — which column to use**. `dim_house_listing.house_unpublished_reason` is a snapshot field only.

### Views by time grain

Same event definition; only the bucket on **event start** changes.

| View | Group by (RENT / SALE) |
|------|------------------------|
| **Daily** | `CAST(ts_status_start AS DATE)` / `CAST(ts_status_started AS DATE)` |
| **Weekly** | `DATE_TRUNC('week', ts_status_start)` / `DATE_TRUNC('week', ts_status_started)` |
| **Monthly** | `DATE_TRUNC('month', ts_status_start)` / `DATE_TRUNC('month', ts_status_started)` |

**Default count:** `COUNT(DISTINCT sk_house_listing)` (RENT) or `COUNT(DISTINCT sk_sale_listing)` (SALE) per period — distinct listings unpublished **at least once** in that period.

**Event volume (alternative):** count interval rows when the same listing can unpublish twice in one period and both events matter — state explicitly.

**Hybrid houses:** count RENT and SALE separately; do not dedupe on `sk_house` without an explicit rule.

## Listing suspensions (volume)

**Listing suspensions** counts **status transitions into SUSPENDED** — each time a listing enters a suspended interval. Requires **status history** (interval facts), not `dim_* .status` snapshot alone.

**Answering “Qual é o volume mensal de imóveis suspensos?”**

1. **Confirm RENT vs SALE** — if unspecified, **report both** in separate blocks (same pattern as unpublishes).
2. **Default metric:** **transition volume** — new `SUSPENDED` intervals starting in the month (`ts_status_start` / `ts_status_started`). **Not** a month-end stock of listings currently suspended (that needs a different point-in-time query — state if the user meant stock).
3. **Operational vs owner pause (RENT):** most `SUSPENDED` rows are **operational** (especially **`status_change_reason = 'RENTED'`** = alugado). For **owner-initiated** temporary suspend only, filter `deactivation_* IS NOT NULL` (1P, post Feb 2026) or the deactivation gate reasons — see **SUSPENDED + `status_reason`** and **Status reasons — which column to use**.
4. **Not unpublish:** do not merge with UNPUBLISHED unless the question says “suspended **or** unpublished”.

| Context | Source of truth (DW) | Listing key | Event timestamp |
|---------|----------------------|-------------|-----------------|
| **RENT** | `dw_rent.fact_house_listing_status` | `sk_house_listing` | `ts_status_start` |
| **SALE** | `dw_sale.fact_listing_status` | `sk_sale_listing` | `ts_status_started` |

**Included:** new **`SUSPENDED`** intervals starting in the reference period.

**RENT filter:** `status_history IN ('SUSPENDED', 'suspenso')`

**SALE filter:** `status_history = 'SUSPENDED'`

**Optional — owner temporary suspend only (RENT, 1P, illustrative):**

```sql
AND fhls.status_change_reason IN (
    'OwnerTemporarilySuspended', 'OwnerReforming', 'OwnerTraveling'
)
-- or: AND fhls.deactivation_reason IS NOT NULL
```

**Optional — exclude operational rent (alugado):**

```sql
AND fhls.status_change_reason <> 'RENTED'
```

**Suspend reason on the event:** `status_change_reason` (default); `deactivation_*` when 1P owner deactivation is enriched — see **Status reasons — which column to use**.

### Views by time grain

Same event definition; bucket on **interval start**.

| View | Group by (RENT / SALE) |
|------|------------------------|
| **Monthly** | `DATE_TRUNC('month', ts_status_start)` / `DATE_TRUNC('month', ts_status_started)` |
| **Weekly** | `DATE_TRUNC('week', …)` |
| **Daily** | `CAST(ts_status_start AS DATE)` / `CAST(ts_status_started AS DATE)` |

**Default count:** `COUNT(DISTINCT sk_house_listing)` (RENT) or `COUNT(DISTINCT sk_sale_listing)` (SALE) per period — distinct listings that entered **SUSPENDED at least once** in that period.

## Relationships with Other Entities

### Pricing (1:N — price changes per house and business context)

- `dw_listing.dim_pricing.sk_house = dim_house.sk_house`; join listing via `fact_price_changes.sk_house_listing` + `business_context` to scope RENT vs SALE
- See `domain_entities/pricing.md`.

### Supply (N:1 — first listing completes acquisition funnel)

- `obt_supply.sk_house` populated from qualified stage (`-1` before); `cd_funnel_step = 'first_listing'`
- See `domain_entities/supply.md`.

### Offer (downstream demand — not listing)

- Rent: `dw_rent.dim_offer` — tenant bid on a house; joins via `id_property` (= `sk_house`), not via listing PK alone
- Sale: `dw_sale.fact_offers` — buyer offer on a sale listing
- Listing funnel columns like `days_first_publication_to_first_offer_submitted` measure listing → offer conversion; see `domain_entities/closing.md` for rent offer → contract path

### Contract / Closing (N:1 house; 1:0..1 per rent listing version)

- `fact_contracts.sk_house = dim_house.sk_house`; `fact_house_listings.sk_contract = fact_contracts.sk_contract`
- Early Demand: see `domain_entities/closing.md`.

### Visits (N:1 at house grain)

- `fact_visits.sk_house = dim_house.sk_house`; filter to listing publication window for listing-level conversion.

### Termination / Offboarding (relisting and rerental)

- `fact_house_listing_terminations` — relisting and rerental after termination; see `domain_entities/termination.md`
- See `domain_entities/termination.md`.

### 3P / Broker XP

- `is_3p_supply` on listing dims; broker detail via sale facts or `fact_house_information_filling`.
- See `domain_entities/broker_xp.md`.

### Region (N:1)

- `dim_house.sk_region = dw_public.dim_region.sk_region`

### Primary Market (shell house ≠ physical unit)

- On Primary Market listings, `sk_house` is a **typology shell**, not one physical apartment — see `domain_entities/primary_market.md` for `sale_type` classification, the development/typology model, and which facts already carry a Primary flag.

## Dos and Don'ts

**Do:**
- Decide grain first: house (`dim_house`) vs listing.
- Decide **RENT vs SALE** — different versioning models, tables, and first-listing logic.
- For **rent** version questions: use `dim_house_listing` + `listing_category_start` + `fact_house_listings`.
- On **`dim_house_listing`**: **hybrid** rows — core attrs are RENT, sale in `*sale*` columns or via `dw_sale.dim_listing`; **sale-only** rows (`is_for_rent = FALSE`) — generic attrs (not RENT-exclusive) reflect SALE.
- For **sale** in `dw_sale.*`: use `dim_listing` + `fact_listings` on `sk_sale_listing`.
- For **sale** in hybrid tables: use `sk_house_listing` + `business_context = 'SALE'`.
- Use **`house_rent_status` / `house_sale_status`** (LBC) for current per-context status — not **`house_status`** except for whole-house `excluido`.
- When explaining **`SUSPENDED`**, always pair with **`status_reason`**: **`RENTED` = alugado**; other values = funnel-in-progress or owner pause — see **SUSPENDED + `status_reason`**.
- For **1P owner deactivation reasons** since Feb 2026: use `deactivation_*` when populated; otherwise `status_change_reason` — see **Status reasons — which column to use**.
- Join listings to house on `id_house = sk_house`.
- Filter `country_code`, `is_last_version = TRUE` (rent), and `status = 'PUBLISHED'` as needed.
- Use `fact_house_listings` for time-to-contract on rent.
- For **RENT** next version: `sk_house_listing + 1`.
- Use `obt_supply` with dedup when joining supply funnel to listings.
- Follow `metric_entities/first_listings_1p.md` for the official FL metric (separate rent and sale branches).
- Follow `metric_entities/listing_to_rental.md` for **L2R** — pick monthly (official), weekly, daily, or windowed view as needed.
- Follow `metric_entities/listing_to_unpublish.md` for **L2Unp** — publication-cohort rate; “mês passado” = previous month's **publication** cohort, not unpublish event volume.
- Follow `metric_entities/ongoing_listings.md` for **daily ongoing listings** — pick RENT or SALE; **RENT in TARS requires bounded date window + `country_code` filter** (never full-history `dim_date` join).
- Follow `metric_entities/listing_demand_funnel_conversions.md` for **L2VB, L2VC, L2OS, L2TP, L2CCV** — RENT uses `fact_listing_rent_flows` at `sk_house_listing`; SALE uses `fact_visits` / `fact_offers` at `sk_house`.
- Follow `metric_entities/listing_to_well_priced.md` for **L2Wp** — RENT only; `price_score_pub` (Pub) or `price_score_4w` (4W) on `sandbox.listing_scores`.
- Follow `metric_entities/listing_performance_score.md` for **Performance Score** — `datalake_similarity_score.house_metrics_score`, not EBDB/OPL/`reverse_demand_score`.
- For **unpublish volume**: use status interval facts; bucket by event start; pick RENT vs SALE and time grain — see **Listing unpublishes** above.
- For **suspension volume**: same pattern with `SUSPENDED` — see **Listing suspensions** above; report **RENT and SALE** when the question does not specify context.

**Don't:**

- Don't tell the user a table is **just rent** or **just sale** unless this document **explicitly** states that scope for that `schema.table` — schema prefix (`dw_rent`, `dw_sale`) is not enough. Do not label table scope as **“RENT only” / “SALE only”** (that wording implies non-hybrid exclusivity).
- Don't infer **RENT/SALE operational status** from **`house_status`** (`publicado`, `despublicado`, etc.) — use **LBC** columns.
- Don't describe **`SUSPENDED`** as only “owner temporary pause” — **`status_reason = 'RENTED'`** means **alugado**; other reasons mean funnel-in-progress or owner pause; see **SUSPENDED + `status_reason`**.
- Don't **COALESCE** `deactivation_reason` over **`status_change_reason`** — pick the correct column per row (1P deactivation enriched vs all other cases).
- Don't label **`status_change_reason`** as legacy or deprecated — it remains the valid reason source outside enriched 1P deactivation.
- Don't read **`status`**, **`listing_category_start`**, or **`rent`** on **hybrid** rows in `dim_house_listing` as sale context — use `house_sale_status` and other `*sale*` columns for sale-side status/flags. **Prices or calculators** for either context must come from `domain_entities/pricing.md` (e.g. `dw_listing.dim_pricing` + **`business_context`**; Casio = RENT, Girafales = SALE).
- Don't apply `listing_category_start` to sale — that taxonomy is RENT-only.
- Don't treat `sale_status_version_order` as sale listing versioning — `order_version` is only 0 or 1; no relisting increments above 1.
- Don't join sale rows from hybrid tables to `dw_sale.*` on `sk_sale_listing = sk_house_listing` — use `sk_house` or match the key convention of each table layer.
- Don't conflate hybrid houses with a single key everywhere — rent uses versioned `sk_house_listing`; sale uses `sk_house_listing` + `business_context` or `sk_sale_listing` depending on the table.
- Don't use `dim_house` alone for current price or publication status.
- Don't use **`dim_house_listing.rent`**, **`house_rent`**, or **`dim_listing.price`** as **preço do anúncio** — official source is **`dw_listing.dim_pricing` + `fact_price_changes`** (`domain_entities/pricing.md`).
- Don't answer **Performance Score** from EBDB `ListingPerformance`, OPL, or **`reverse_demand_score`** — use **`enrich_similarity_score`** → `datalake_similarity_score.house_metrics_score`.
- Don't count listing rows as distinct houses without `COUNT(DISTINCT sk_house)`.
- Don't use `sk_house_listing + 1` on **SALE** — no version sequence.
- Don't union rent and sale listing dims without normalizing keys and `business_context`.
- Don't join `obt_supply` to listing tables without dedup.
- Don't expect `sk_broker` on `dim_house_listing`.
- Don't equate **OPTED_OUT**, **EXCLUDED**, and **excluido** — different grains (LBC vs audit vs house legacy); hybrid partial exclude leaves `house_status` active.
- Don't treat **OPTED_OUT** as "owner gave up before publishing" — many OPTED_OUT rows had prior publication; use `status_reason`.
- Don't use **UNPUBLISHED** and **OPTED_OUT** interchangeably — UNPUBLISHED is reversible deactivation.
- Don't use `house_listings_daily_info`, simplified RENT interval checks, or SALE ad-hoc status SQL for official ongoing-listings volume — see `metric_entities/ongoing_listings.md`.
- Don't compute L2R from `dim_contract` joins alone — see `metric_entities/listing_to_rental.md`.
- Don't count **unpublishes** from `dim_house_listing.status` or `dim_listing` snapshot — use `fact_house_listing_status` / `fact_listing_status`.
- Don't count **suspensions** from LBC snapshot alone — use status interval facts; don't default to **RENT only** when SALE is not excluded.
- Don't treat all **SUSPENDED** volume as **owner pause** — on RENT, most events are **operational** (`RENTED` = alugado); filter explicitly when needed.
- Don't answer **L2Unp** with unpublish **volume** SQL (event date bucket) — use `metric_entities/listing_to_unpublish.md`.
- Don't apply RENT legacy code `despublicado` to SALE unpublish counts.

## Golden Queries

### Query 1 — House inventory with region attributes

```sql
SELECT
    dh.sk_house,
    dr.city_name,
    dr.city_group,
    dh.bedrooms,
    dh.bathrooms,
    dh.total_area
FROM dw_house.dim_house AS dh
INNER JOIN dw_public.dim_region AS dr
    ON dh.sk_region = dr.sk_region
WHERE dr.country_code = 'BR'
```

### Query 2 — Published rent listings with house main attributes and lifetime metrics

```sql
SELECT
    dh.sk_house,
    dhl.sk_house_listing,
    dh.bedrooms,
    dhl.rent,
    dhl.status,
    dhl.listing_category_start,
    fhl.days_listing_to_contract_signed,
    fhl.nr_renting
FROM dw_house.dim_house AS dh
INNER JOIN dw_rent.dim_house_listing AS dhl
    ON dh.sk_house = dhl.id_house
INNER JOIN dw_rent.fact_house_listings AS fhl
    ON dhl.sk_house_listing = fhl.sk_house_listing
WHERE dhl.country_code = 'BR'
  AND dhl.is_for_rent = TRUE
  AND dhl.status = 'PUBLISHED'
  AND dhl.is_last_version = TRUE
```

### Query 3 — First Listings (rent only) in a period

Component pattern — `listing_category_start` is RENT-only. For sale FL see `metric_entities/first_listings_1p.md`.

```sql
SELECT
    DATE(dhl.ts_publication) AS dt_first_publication,
    COUNT(DISTINCT dhl.sk_house_listing) AS first_listings
FROM dw_rent.dim_house_listing AS dhl
WHERE dhl.country_code = 'BR'
  AND dhl.listing_category_start = 'First Listing'
  AND CAST(dhl.ts_publication AS DATE) >= DATE '2026-01-01'
  AND CAST(dhl.ts_publication AS DATE) < CURRENT_DATE
GROUP BY 1
ORDER BY 1
```

### Query 4 — For Sale listings with publication funnel timing

```sql
SELECT
    dl.sk_sale_listing,
    dl.sk_house,
    dl.price,
    dl.status,
    fl.days_first_publication_to_first_offer_submitted,
    fl.days_first_publication_to_visit_completed
FROM dw_sale.fact_listings AS fl
INNER JOIN dw_sale.dim_listing AS dl
    ON fl.sk_sale_listing = dl.sk_sale_listing
WHERE dl.is_3p_supply = FALSE
```

### Query 5 — Owner deactivation with new taxonomy (RENT, 1P, post Feb 2026)

```sql
SELECT
    fhls.sk_house_listing,
    fhls.status_history,
    fhls.status_change_reason,
    fhls.deactivation_reason_category,
    fhls.deactivation_reason,
    fhls.deactivation_additional_context,
    fhls.sk_status_start_date
FROM dw_rent.fact_house_listing_status AS fhls
WHERE fhls.country_code = 'BR'
  AND fhls.deactivation_reason IS NOT NULL
```

### Query 6 — Listing unpublishes monthly (RENT)

```sql
SELECT
    DATE_TRUNC('month', fhls.ts_status_start) AS cohort_period,
    fhls.country_code,
    COUNT(DISTINCT fhls.sk_house_listing) AS unpublishes
FROM dw_rent.fact_house_listing_status AS fhls
WHERE fhls.status_history IN ('UNPUBLISHED', 'despublicado')
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 7 — Listing unpublishes monthly (SALE)

```sql
SELECT
    DATE_TRUNC('month', fls.ts_status_started) AS cohort_period,
    dr.country_code,
    COUNT(DISTINCT fls.sk_sale_listing) AS unpublishes
FROM dw_sale.fact_listing_status AS fls
JOIN dw_public.dim_region AS dr
    ON fls.sk_region = dr.sk_region
WHERE fls.status_history = 'UNPUBLISHED'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

For **weekly** or **daily** views, replace `cohort_period` with `DATE_TRUNC('week', …)` or `CAST(… AS DATE)` on the same event timestamp column. Add `country_code = 'BR'` when Brazil-only.

### Query 8 — Unpublishes with reason (RENT, any grain)

```sql
SELECT
    DATE_TRUNC('month', fhls.ts_status_start) AS cohort_period,
    fhls.status_change_reason,
    fhls.deactivation_reason,
    COUNT(DISTINCT fhls.sk_house_listing) AS unpublishes
FROM dw_rent.fact_house_listing_status AS fhls
WHERE fhls.status_history IN ('UNPUBLISHED', 'despublicado')
  AND fhls.country_code = 'BR'
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 4 DESC
```

### Query 9 — Listing suspensions monthly (RENT)

```sql
SELECT
    DATE_TRUNC('month', fhls.ts_status_start) AS cohort_period,
    fhls.country_code,
    COUNT(DISTINCT fhls.sk_house_listing) AS suspensions
FROM dw_rent.fact_house_listing_status AS fhls
WHERE fhls.status_history IN ('SUSPENDED', 'suspenso')
  AND fhls.country_code = 'BR'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 10 — Listing suspensions monthly (SALE)

```sql
SELECT
    DATE_TRUNC('month', fls.ts_status_started) AS cohort_period,
    dr.country_code,
    COUNT(DISTINCT fls.sk_sale_listing) AS suspensions
FROM dw_sale.fact_listing_status AS fls
JOIN dw_public.dim_region AS dr
    ON fls.sk_region = dr.sk_region
WHERE fls.status_history = 'SUSPENDED'
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
