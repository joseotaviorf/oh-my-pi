# House and Listing

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
5. **Conversion** — rent listing → contract (`fact_house_listings.sk_contract`); sale listing → CCV (see `business_entities/fs-transact.md`)

Not every house follows every step. Some are created during supply acquisition and never list; others are delisted and relisted months later under the same `sk_house`. At the EBDB source, each business context has its own row in `listing_business_context`.

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
| Publication during **Early Demand** (active contract termination in progress) | New version; flag `is_early_demand = TRUE` — see `business_entities/closing.md` |

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
- **Hybrid house**, **imóvel híbrido** → same **`sk_house`**, rent **and** sale active in parallel. Rent cycles through multiple **`sk_house_listing`** versions. For sale: use **`sk_house_listing` + `business_context = 'SALE'`** in hybrid tables, or **`sk_sale_listing`** in `dw_sale.*` only tables. In **`dw_rent.dim_house_listing`**, **RENT takes priority** on hybrid rows — sale status/flags in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`). **Prices and calculators** for either context → `business_entities/pricing.md` — filter **`business_context`** (**Casio** = RENT, **Girafales** = SALE).
- **id_house / sk_house** → same numeric value; listing tables often use `id_house`, house dims use `sk_house`
- **First Listing**, **primeira captação**, **FL** → **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication detected via `fact_listings.sk_first_publication_date` / `listing_business_context.ts_first_listing` — no `listing_category_start`. Official metric: `metric_entities/first_listings_1p.md`
- **Re-Listing**, **relistagem** → **RENT only** — new rent version after prior rental ended (`listing_category_start = 'Re-Listing'`)
- **Recovered**, **recuperado** → **RENT only** — republished after 84+ days unpublished (`listing_category_start = 'Recovered'`)
- **Published**, **publicado** → on-market (`status = 'PUBLISHED'`)
- **Last version (RENT)** → current rent listing version (`is_last_version = TRUE` on `dim_house_listing`)
- **Early Demand** → rent listing published during active contract termination; triggers a **new rent version** (`is_early_demand = TRUE`); see **RENT listing versioning** and `business_entities/closing.md`
- **Amenities** → property features; `dw_house.dim_house_amenities` (current), `dim_house_amenities_version` (history)
- **Entrance model**, **modelo de entrada** → property access method; history in `dim_house_entrance_history`
- **Ongoing listing** → published inventory on a given day; **RENT** and **SALE** use different sources — see `metric_entities/ongoing_listings.md`
- **3P listing** → third-party broker inventory (`is_3p_supply = TRUE`)
- **L2R**, **Listing to Rental**, **Listing2Rental**, **listing → alugado (RENT)** → `metric_entities/listing_to_rental.md` (monthly / weekly / daily / windowed views)
- **L2TP**, **Listing to Tenant Prospect** → **RENT only** — listing reached **VB and/or OS** within cohort window
- **L2VB / L2VC / L2OS / L2CCV** → listing demand funnel cohort conversions; **RENT ≠ SALE** — see `metric_entities/listing_demand_funnel_conversions.md`
- **Despublicações / unpublishes**, **listing unpublished** → UNPUBLISHED **status transitions** (not snapshot); daily / weekly / monthly — see **Listing unpublishes** below. Counts **UNPUBLISHED only** unless the request includes **SUSPENDED**
- **Stranded listing** → **RENT only** — published 8+ weeks without contract (`fact_house_listings.sk_stranded_date <> -1`)
- **RENT / SALE**, **aluguel / venda** → business contexts (`business_context`, `listing_business_context`); separate DW stars (`dw_rent.*`, `dw_sale.*`). Only **RENT** has listing versioning and `listing_category_start`
- **OPTED_OUT** → LBC status (`listing_business_context.status`) — owner opted out of a **business context** (RENT or SALE). Source of truth for current exclusion at context grain. See **Exclusion statuses** below
- **EXCLUDED** → audit/API status in `house_listing_status_log.status_to` — event of definitive exclusion via the new state machine. Maps to OPTED_OUT on LBC in the standard exclude flow; not present on every OPTED_OUT row
- **excluido** → legacy **house-level** status (`house.status` / `dim_house_listing.house_status`, Portuguese in `fact_house_listing_status.status_history`). Set only when **all** LBCs of the house are OPTED_OUT — not equivalent to OPTED_OUT on one context alone
- **`house_status`** / **`Imovel.status`** → legacy **house-level** field on `dim_house_listing.house_status` — **not** source of truth for RENT/SALE operational status today; see **House.status vs LBC** below

## Listing status lifecycle

Source of truth for **current** status per business context: `datalake_ebdb_clean.listing_business_context` (`status`, `status_reason`) — one row per house × context (RENT or SALE).

### Q: What does each listing status mean?

| Status | Meaning | Receives demand? |
|--------|---------|------------------|
| **EDITING** | Draft — not yet published for this context. After the first publication, the listing does not return to EDITING. | No |
| **PUBLISHED** | Currently published on the platform. | Yes |
| **SUSPENDED** | Temporarily off-market; may have an expected return date. Reversible. | No |
| **UNPUBLISHED** | Disabled for an indefinite period. Reversible — owner may republish. Many "owner gave up" cases land here (not OPTED_OUT). | No |
| **OPTED_OUT** | Owner opted out of this business context — **permanent logical exclusion**. Reversible only in limited cases. Always read `status_reason`. | No |

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

## House.status vs ListingBusinessContext (LBC)

**`house.status` (`dim_house_listing.house_status`) is legacy** — from when QuintoAndar had rent-only listings. It is **not** the source of truth for current operational status per business context. For **which columns and DW tables to query**, see **Which columns to use in queries** above.

**Do not infer RENT/SALE operational status from `house_status` values** such as `publicado`, `despublicado`, `suspenso`, `edicao` — those reflect the old rent-centric house model. Pipeline and product logic must read **LBC** (via `house_rent_status` / `house_sale_status` on `dim_house_listing`).

**Exception — `excluido`:** the only meaningful **whole-house** flag on `house.status`. Means the property is globally excluded (all contexts opted out). It does **not** replace per-context OPTED_OUT on LBC for hybrid partial exclusions.

## Status reasons — legacy LBC vs deactivation enrichment (1P)

Two **coexisting** reason tracks on status history tables — **do not merge or COALESCE**:

| Question | Field | Source |
|----------|-------|--------|
| Legacy LBC reason code (all history) | **`status_change_reason`** | `listing_business_context` / LBC audit — **unchanged** by deactivation project |
| New product taxonomy (owner deactivation) | **`deactivation_reason`**, **`deactivation_reason_category`**, **`deactivation_additional_context`** | `house_listing_status_log` — enriched onto status facts since **2026-02-03** |
| Status interval type | **`status_history`** | UNPUBLISHED = unpublish deactivation; SUSPENDED = suspend deactivation **when in the deactivation gate** |

**Where enriched (passthrough to DW):**

| Context | Enrich | DW fact |
|---------|--------|---------|
| RENT | `datalake_ebdb_listing.house_listing_status` | `dw_rent.fact_house_listing_status` |
| SALE | `datalake_sale_listings.sale_listing_status` | `dw_sale.fact_listing_status` |

**What counts as “deactivation” (1P owner intent)?** UNPUBLISH or temporary SUSPEND identified by a **gate** on `(status_history, status_change_reason)` — **not** every `SUSPENDED` row (~3.6M rent rows include operational suspensions like RENTED).

| Deactivation type | `status_history` in gate | Examples of `status_change_reason` |
|-------------------|--------------------------|-----------------------------------|
| Unpublish (UNPUBLISH) | UNPUBLISHED | `OWNER_GAVE_UP_RENTING`, `OWNER_GAVE_UP_SALE`, `OWNER_ALREADY_SOLD_HOUSE`, … |
| Temporary suspend (SUSPEND) | SUSPENDED | `OwnerTemporarilySuspended`, `OwnerReforming`, `OwnerTraveling`, … |

**Scope:** `deactivation_*` filled only for **1P** listings (`is_rent_3p_supply` / `is_sale_3p_supply = false`) that pass the gate **and** match a log event within **±2 minutes** of `ts_status_started`. Post-launch match rate ~**74% RENT / 73% SALE**; ~**26%** remain NULL on all three fields (pre-log history, no log event, timestamp lag, or incomplete origin).

**Periods:**

| Period | `status_change_reason` | `deactivation_*` |
|--------|------------------------|------------------|
| Pre-2020-01-06 | Legacy PT + free text | NULL |
| 2020-01-06 → 2026-02-02 | Structured LBC codes | NULL (log not available) |
| Since 2026-02-03 | LBC codes (unchanged) | Populated when gate + log match |

**Consumer guide:**

```sql
-- RENT: rows with new deactivation taxonomy (1P, post Feb 2026)
SELECT *
FROM datalake_ebdb_listing.house_listing_status
WHERE country_code = 'BR'
  AND deactivation_reason IS NOT NULL;
```

**Pitfalls — common mistakes when using reason columns:**

1. **Do not treat every `SUSPENDED` row as owner deactivation.** Most rent status-history rows with `status_history = 'SUSPENDED'` are **operational** suspensions (e.g. listing rented — `RENTED`), not the owner asking for a temporary pause. To isolate owner-driven temporary suspend, use the **gate** pairs in the table above, or filter `deactivation_* IS NOT NULL`.

2. **Do not infer “no owner deactivation” from NULL `deactivation_*`.** All three fields can be NULL even when the interval was a real owner unpublish/suspend: data before **2026-02-03**, **3P** listings (out of scope), rows that fail the gate (operational suspend), or rows where the log event did not match within **±2 minutes** (~**26%** of eligible 1P rows post-launch). For those cases, **`status_change_reason`** remains the source.

3. **`deactivation_reason` NULL with `deactivation_additional_context` populated is valid.** Partial enrichment can occur — do not discard the row or treat it as a pipeline bug.

4. **Do not COALESCE or merge `deactivation_*` with `status_change_reason`.** They are parallel tracks: LBC legacy reason (full history) vs new owner-intent taxonomy (1P, gated, post Feb 2026). Pick the column that matches the question; report both side by side if needed — never `COALESCE(deactivation_reason, status_change_reason)`.

5. **Do not expect `deactivation_*` on versioning / category pipelines.** Tables such as `business_context_history`, `lbc_status_version_order`, and `sale_status_version_order` still expose LBC **`status_reason`** only. For the new deactivation taxonomy, query **`dw_rent.fact_house_listing_status`** or **`dw_sale.fact_listing_status`**.

**Quick reference — which reason column to use:**

| Your question | Column(s) |
|---------------|-----------|
| Reason code for **any** period, including 3P or pre-2026 | `status_change_reason` |
| New owner-intent taxonomy (unpublish / temporary suspend, **1P**, post Feb 2026) | `deactivation_reason`, `deactivation_reason_category`, `deactivation_additional_context` |
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

**`dw_rent.dim_house_listing` is rent-first.** On **hybrid** houses, the row grain, versioning, and core listing attributes (`status`, `listing_category_start`, `rent`, etc.) reflect **RENT** — not sale. Sale-side status/flags on the same row appear in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`, `is_sale_3p_supply`). **Official price changes and calculator output** for either context are not on this table — use `business_entities/pricing.md` with **`business_context`** (Casio = RENT, Girafales = SALE). For full sale listing analysis, use **`dw_sale.dim_listing`**.

The table can also include **sale-only** houses (`is_for_rent = FALSE`, `is_for_sale = TRUE`) — properties with a SALE business context but no rent listing versioning history. On those rows, **generic attributes** not exclusive to RENT (e.g. `status`) reflect **SALE**; RENT-only fields (`listing_category_start`, `rent`, etc.) do not apply. Use `dw_sale.*` for full sale listing metrics.

| You need... | Use this table |
|-------------|----------------|
| Rent listing attributes at version grain | `dw_rent.dim_house_listing` (`dhl`) — PK `sk_house_listing`; house via `id_house`; `listing_category_start`; hybrid: sale attrs in `*sale*` columns; sale-only: generic attrs for SALE; flags `is_for_rent`, `is_for_sale` |
| Rent lifetime metrics (days-to-contract, next listing, rental count) | `dw_rent.fact_house_listings` (`fhl`) — rent-filtered at build time; join on `sk_house_listing` |
| Rent listing status history (intervals) — **RENT only** | **`dw_rent.fact_house_listing_status`** — `status_change_reason` (LBC legacy) + `deactivation_*` (1P, from 2026-02-03); grain `sk_house_listing` |
| Owner deactivation taxonomy (enriched) — **RENT only** | `deactivation_reason`, `deactivation_reason_category`, `deactivation_additional_context` on **`dw_rent.fact_house_listing_status`** |
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
| Sale lifetime metrics (publication funnel, demand totals) | `dw_sale.fact_listings` (`fl`) — join on `sk_sale_listing`; first publication via `sk_first_publication_date`; last publication via `sk_last_publication_date` |
| Daily published inventory + demand | `dw_sale.fact_daily_ongoing_listing` — only `PUBLISHED` days; PK `sk_snapshot`                                                                                 |
| Sale listing status history (intervals) — **SALE only** | **`dw_sale.fact_listing_status`** — `status_change_reason` (LBC legacy) + `deactivation_*` (1P, from 2026-02-03); includes `sk_broker` for 3P; grain `sk_sale_listing` |
| Sale status transition enrich (not versioning) | `datalake_sale_listings.sale_status_version_order` — status transitions; `order_version` does not increment beyond 1 for business relistings |
| Definitive exclusion audit events (EXCLUDED) | `datalake_ebdb_clean.house_listing_status_log` — filter `business_context = 'SALE'` via event log join |

### Cross-cutting

| You need...                                                | Use this table |
|------------------------------------------------------------|----------------|
| Lead → first listing supply funnel                         | `dw_public.fact_house_listing_flows` |
| Termination → relisting / rerental on next listing version | `dw_offboarding.fact_house_listing_terminations` — see `business_entities/termination.md` |

**Critical rules:**
- **`listing_category_start` is RENT-only** — never filter it on sale tables; sale FL uses first-publication dates (`metric_entities/first_listings_1p.md`).
- **Listing versioning is RENT-only** — see **RENT listing versioning** section. Sale: `order_version` 0/1 only; no relisting categories.
- **`dim_house_listing` is rent-first on hybrids** — RENT drives row grain and core attrs; read sale from `*sale*` columns or use `dw_sale.dim_listing`. **Sale-only rows** (`is_for_rent = FALSE`): generic (non-RENT-exclusive) attrs reflect SALE.
- **Sale listing key depends on table type** — hybrid tables: `sk_house_listing` + `business_context = 'SALE'`; SALE-only tables (`dw_sale.*`): `sk_sale_listing`. Do not join `dw_sale.*` to hybrid tables on `sk_sale_listing = sk_house_listing`.
- **`sk_house` bridges hybrid houses** — same house, separate rent version lifecycle vs sale rows keyed as above.
- **Hybrid houses** — same `sk_house`; rent and sale are separate tracks with different key conventions per table layer.
- **`dim_house` does not carry 3P flags, current rent/sale price, or broker keys** — use listing dims or enrich `datalake_ebdb_listing.house`. For 3P broker at house grain: `fact_house_information_filling.sk_broker <> -1`.
- **Join key naming:** `dim_house_listing.id_house = dim_house.sk_house` (rent); `dim_listing.sk_house = dim_house.sk_house` (sale).
- **Schema vs DAG name:** DAG `dw_listing` → `dw_rent.*`; DAG `dw_sale_listings` → `dw_sale.*`.
- **Next listing navigation (RENT):** `sk_house_listing + 1` for the next rent version. **SALE:** do not use `+ 1`.
- **Current state:** `is_last_version = TRUE` + `status = 'PUBLISHED'` for on-market inventory.
- **Partition filter:** `country_code = 'BR'` (or `'MX'`) on listing/enrich tables.
- **Legacy duplicate:** prefer `dw_rent.*` over `dw_public.dim_house_listing`.
- **`house_status` is legacy** — use LBC (`house_rent_status` / `house_sale_status`) for current context status; only `excluido` is a whole-house signal.
- **Deactivation analysis:** use `deactivation_*` for new taxonomy; `status_change_reason` for historical LBC codes; never treat all SUSPENDED as owner deactivation.
- **DataHub CI:** concrete `schema.table` names only — never wildcards.
- **Exclusion statuses:** use LBC `OPTED_OUT` for context-level exclusion; `house_listing_status_log` for EXCLUDED events; `excluido` only for whole-house legacy status. "Owner gave up" often → UNPUBLISHED, not OPTED_OUT.

## Key Metrics

### House grain

- Distinct houses (`COUNT(DISTINCT dim_house.sk_house)`)
- Houses by city/region (`dim_house.sk_region` → `dw_public.dim_region`)
- Repeat-rental houses (`fact_house_listings.nr_renting > 1`)

### Listing grain

- First Listings — **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication date on `fact_listings` (see `metric_entities/first_listings_1p.md`)
- **Ongoing listings (daily volume)** — RENT and SALE; see `metric_entities/ongoing_listings.md`
- Current published inventory snapshot (`status = 'PUBLISHED'`; rent also uses `is_last_version = TRUE`) — point-in-time, not the daily series above
- **L2R (Listing to Rental)** — monthly, weekly, daily cohort rates and days-to-contract → `metric_entities/listing_to_rental.md`
- **Listing unpublishes** — transition volume by day / week / month — see **Listing unpublishes** below
- Relisting / rerent lag — **RENT only:** `days_ended_rental_to_relisting`, `days_relisting_to_re_rental`
- Sale funnel velocity — **SALE:** `fact_listings.days_first_publication_to_*`
- 3P vs 1P listing volume (`is_3p_supply`)

## Listing unpublishes

**Listing unpublishes** counts **status transitions into UNPUBLISHED** — each time a listing enters an unpublished interval. Requires **status history** (interval facts), not `dim_* .status` snapshot alone.

| Context | Source of truth (DW) | Listing key | Event timestamp |
|---------|----------------------|-------------|-----------------|
| **RENT** | `dw_rent.fact_house_listing_status` | `sk_house_listing` | `ts_status_start` |
| **SALE** | `dw_sale.fact_listing_status` | `sk_sale_listing` | `ts_status_started` |

**Included:** new **`UNPUBLISHED`** intervals starting in the reference period.

**RENT filter:** `status_history IN ('UNPUBLISHED', 'despublicado')`

**SALE filter:** `status_history = 'UNPUBLISHED'`

**Excluded (unless requested):** `SUSPENDED`, `OPTED_OUT`, `EDITING`, `PUBLISHED`; counting **current** unpublished listings without a transition event.

**Not the same as:** deactivation totals that merge UNPUBLISHED + SUSPENDED — clarify if the question says “unpublished **or** suspended”.

**Unpublish reason:** on the **event**, use `status_change_reason` / `deactivation_*` on status facts; `dim_house_listing.house_unpublished_reason` is a legacy **snapshot** only.

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

## Relationships with Other Entities

### Pricing (1:N — price changes per house and business context)

- `dw_listing.dim_pricing.sk_house = dim_house.sk_house`; join listing via `fact_price_changes.sk_house_listing` + `business_context` to scope RENT vs SALE
- See `business_entities/pricing.md`.

### Supply (N:1 — first listing completes acquisition funnel)

- `obt_supply.sk_house` populated from qualified stage (`-1` before); `cd_funnel_step = 'first_listing'`
- See `business_entities/supply.md`.

### Offer (downstream demand — not listing)

- Rent: `dw_rent.dim_offer` — tenant bid on a house; joins via `id_property` (= `sk_house`), not via listing PK alone
- Sale: `dw_sale_offers.fact_offers` — buyer offer on a sale listing
- Listing funnel columns like `days_first_publication_to_first_offer_submitted` measure listing → offer conversion; see `business_entities/closing.md` for rent offer → contract path

### Contract / Closing (N:1 house; 1:0..1 per rent listing version)

- `fact_contracts.sk_house = dim_house.sk_house`; `fact_house_listings.sk_contract = fact_contracts.sk_contract`
- Early Demand: see `business_entities/closing.md`.

### Visits (N:1 at house grain)

- `fact_visits.sk_house = dim_house.sk_house`; filter to listing publication window for listing-level conversion.

### Termination / Offboarding (relisting and rerental)

- `fact_house_listing_terminations` — relisting and rerental after termination; see `business_entities/termination.md`
- See `business_entities/termination.md`.

### 3P / Broker XP

- `is_3p_supply` on listing dims; broker detail via sale facts or `fact_house_information_filling`.
- See `business_entities/broker_xp.md`.

### Region (N:1)

- `dim_house.sk_region = dw_public.dim_region.sk_region`

## Dos and Don'ts

**Do:**
- Decide grain first: house (`dim_house`) vs listing.
- Decide **RENT vs SALE** — different versioning models, tables, and first-listing logic.
- For **rent** version questions: use `dim_house_listing` + `listing_category_start` + `fact_house_listings`.
- On **`dim_house_listing`**: **hybrid** rows — core attrs are RENT, sale in `*sale*` columns or via `dw_sale.dim_listing`; **sale-only** rows (`is_for_rent = FALSE`) — generic attrs (not RENT-exclusive) reflect SALE.
- For **sale** in `dw_sale.*`: use `dim_listing` + `fact_listings` on `sk_sale_listing`.
- For **sale** in hybrid tables: use `sk_house_listing` + `business_context = 'SALE'`.
- Use **`house_rent_status` / `house_sale_status`** (LBC) for current per-context status — not **`house_status`** except for whole-house `excluido`.
- For **owner deactivation reasons** since Feb 2026: filter `deactivation_reason IS NOT NULL` on status facts; for legacy codes use `status_change_reason`.
- Join listings to house on `id_house = sk_house`.
- Filter `country_code`, `is_last_version = TRUE` (rent), and `status = 'PUBLISHED'` as needed.
- Use `fact_house_listings` for time-to-contract on rent.
- For **RENT** next version: `sk_house_listing + 1`.
- Use `obt_supply` with dedup when joining supply funnel to listings.
- Follow `metric_entities/first_listings_1p.md` for the official FL metric (separate rent and sale branches).
- Follow `metric_entities/listing_to_rental.md` for **L2R** — pick monthly (official), weekly, daily, or windowed view as needed.
- Follow `metric_entities/ongoing_listings.md` for **daily ongoing listings** — pick RENT or SALE section; do not mix contexts in one query.
- Follow `metric_entities/listing_demand_funnel_conversions.md` for **L2VB, L2VC, L2OS, L2TP, L2CCV** — RENT uses `fact_listing_rent_flows` at `sk_house_listing`; SALE uses `fact_visits` / `fact_offers` at `sk_house`.
- For **unpublish volume**: use status interval facts; bucket by event start; pick RENT vs SALE and time grain — see **Listing unpublishes** above.

**Don't:**
- Don't infer **RENT/SALE operational status** from **`house_status`** (`publicado`, `despublicado`, etc.) — use **LBC** columns.
- Don't treat **`status_history = 'SUSPENDED'`** as owner deactivation without the deactivation gate or **`deactivation_*`** fields.
- Don't **COALESCE** `deactivation_reason` over **`status_change_reason`** — separate legacy vs new taxonomy.
- Don't read **`status`**, **`listing_category_start`**, or **`rent`** on **hybrid** rows in `dim_house_listing` as sale context — use `house_sale_status` and other `*sale*` columns for sale-side status/flags. **Prices or calculators** for either context must come from `business_entities/pricing.md` (e.g. `dw_listing.dim_pricing` + **`business_context`**; Casio = RENT, Girafales = SALE).
- Don't apply `listing_category_start` to sale — that taxonomy is RENT-only.
- Don't treat `sale_status_version_order` as sale listing versioning — `order_version` is only 0 or 1; no relisting increments above 1.
- Don't join sale rows from hybrid tables to `dw_sale.*` on `sk_sale_listing = sk_house_listing` — use `sk_house` or match the key convention of each table layer.
- Don't conflate hybrid houses with a single key everywhere — rent uses versioned `sk_house_listing`; sale uses `sk_house_listing` + `business_context` or `sk_sale_listing` depending on the table.
- Don't use `dim_house` alone for current price or publication status.
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
- Don't apply RENT legacy code `despublicado` to SALE unpublish counts.

## Golden Queries

### Query 1 — House inventory with region attributes

```sql
SELECT
    dh.sk_house,
    dr.city,
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

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
