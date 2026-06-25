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
- **Hybrid house**, **imóvel híbrido** → same **`sk_house`**, rent **and** sale active in parallel. Rent cycles through multiple **`sk_house_listing`** versions. For sale: use **`sk_house_listing` + `business_context = 'SALE'`** in hybrid tables, or **`sk_sale_listing`** in `dw_sale.*` only tables. In **`dw_rent.dim_house_listing`**, **RENT takes priority** on hybrid rows — sale status/flags in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`); **sale price** → `business_entities/pricing.md`
- **id_house / sk_house** → same numeric value; listing tables often use `id_house`, house dims use `sk_house`
- **First Listing**, **primeira captação**, **FL** → **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication detected via `fact_listings.sk_first_publication_date` / `listing_business_context.ts_first_listing` — no `listing_category_start`. Official metric: `metric_entities/first_listings_1p.md`
- **Re-Listing**, **relistagem** → **RENT only** — new rent version after prior rental ended (`listing_category_start = 'Re-Listing'`)
- **Recovered**, **recuperado** → **RENT only** — republished after 84+ days unpublished (`listing_category_start = 'Recovered'`)
- **Published**, **publicado** → on-market (`status = 'PUBLISHED'`)
- **Last version (RENT)** → current rent listing version (`is_last_version = TRUE` on `dim_house_listing`)
- **Early Demand** → rent listing published during active contract termination; triggers a **new rent version** (`is_early_demand = TRUE`); see **RENT listing versioning** and `business_entities/closing.md`
- **Amenities** → property features; `dw_house.dim_house_amenities` (current), `dim_house_amenities_version` (history)
- **Entrance model**, **modelo de entrada** → property access method; history in `dim_house_entrance_history`
- **Ongoing listing** → published inventory on a given day; rent via daily infos; sale via `fact_daily_ongoing_listing`
- **3P listing** → third-party broker inventory (`is_3p_supply = TRUE`)
- **Stranded listing** → **RENT only** — published 8+ weeks without contract (`fact_house_listings.sk_stranded_date <> -1`)
- **RENT / SALE**, **aluguel / venda** → business contexts (`business_context`, `listing_business_context`); separate DW stars (`dw_rent.*`, `dw_sale.*`). Only **RENT** has listing versioning and `listing_category_start`

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

**`dw_rent.dim_house_listing` is rent-first.** On **hybrid** houses, the row grain, versioning, and core listing attributes (`status`, `listing_category_start`, `rent`, etc.) reflect **RENT** — not sale. Sale-side status/flags on the same row appear in columns with **`sale`** in the name (e.g. `house_sale_status`, `is_for_sale`, `is_sale_3p_supply`). **Sale price** is not authoritative here — use `business_entities/pricing.md`. For full sale listing analysis, use **`dw_sale.dim_listing`**.

The table can also include **sale-only** houses (`is_for_rent = FALSE`, `is_for_sale = TRUE`) — properties with a SALE business context but no rent listing versioning history. On those rows, **generic attributes** not exclusive to RENT (e.g. `status`) reflect **SALE**; RENT-only fields (`listing_category_start`, `rent`, etc.) do not apply. Use `dw_sale.*` for full sale listing metrics.

| You need... | Use this table |
|-------------|----------------|
| Rent listing attributes at version grain | `dw_rent.dim_house_listing` (`dhl`) — PK `sk_house_listing`; house via `id_house`; `listing_category_start`; hybrid: sale attrs in `*sale*` columns; sale-only: generic attrs for SALE; flags `is_for_rent`, `is_for_sale` |
| Rent lifetime metrics (days-to-contract, next listing, rental count) | `dw_rent.fact_house_listings` (`fhl`) — rent-filtered at build time; join on `sk_house_listing` |
| Listing status history (intervals) | `dw_rent.fact_house_listing_status` |
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
| Sale listing status transitions (includes `sk_broker` for 3P) | `dw_sale.fact_listing_status`                                                                                                                                  |
| Sale status history (not versioning) | `datalake_sale_listings.sale_status_version_order` — status transitions; `order_version` does not increment beyond 1 for business relistings                   |

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
- **DataHub CI:** concrete `schema.table` names only — never wildcards.

## Key Metrics

### House grain

- Distinct houses (`COUNT(DISTINCT dim_house.sk_house)`)
- Houses by city/region (`dim_house.sk_region` → `dw_public.dim_region`)
- Repeat-rental houses (`fact_house_listings.nr_renting > 1`)

### Listing grain

- First Listings — **RENT:** `listing_category_start = 'First Listing'` on `dim_house_listing`. **SALE:** first publication date on `fact_listings` (see `metric_entities/first_listings_1p.md`)
- Published inventory (`status = 'PUBLISHED'`; rent also uses `is_last_version = TRUE`)
- Days to contract — **RENT:** `fact_house_listings.days_listing_to_contract_signed`
- Relisting / rerent lag — **RENT only:** `days_ended_rental_to_relisting`, `days_relisting_to_re_rental`
- Sale funnel velocity — **SALE:** `fact_listings.days_first_publication_to_*`
- 3P vs 1P listing volume (`is_3p_supply`)

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
- Use `dim_house` for property attributes; listing tables for publication state, price, and 3P flags.
- Join listings to house on `id_house = sk_house`.
- Filter `country_code`, `is_last_version = TRUE` (rent), and `status = 'PUBLISHED'` as needed.
- Use `fact_house_listings` for time-to-contract on rent.
- For **RENT** next version: `sk_house_listing + 1`.
- Use `obt_supply` with dedup when joining supply funnel to listings.
- Follow `metric_entities/first_listings_1p.md` for the official FL metric (separate rent and sale branches).

**Don't:**
- Don't read **`status`**, **`listing_category_start`**, or **`rent`** on **hybrid** rows in `dim_house_listing` as sale context — use `house_sale_status` and other `*sale*` columns for sale-side status/flags; **sale price** must come from official pricing sources (see `business_entities/pricing.md`, e.g. `dw_listing.dim_pricing` with `business_context = 'SALE'`).
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
- Don't use `dw_public.dim_house_listing` for new For Rent work.

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

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
