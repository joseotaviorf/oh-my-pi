# Pricing

## Overview

**Pricing** tracks how rental and sale prices change over time for each house on QuintoAndar as well as how the pricing calculators — Casio and Girafales — behave. The grain is **`(sk_house, business_context)`** — the same physical property can have independent price histories and price predictions for RENT and SALE.

## Official model

### Price changes

The **official DW model** for registered price changes is:

- **`dw_listing.dim_pricing`** + **`dw_listing.fact_price_changes`**

The **only enrich source of truth** for price changes is:

- **`datalake_ebdb_pricing.listing_price_change`** (singular — **not** `listing_price_changes`)

Legacy enrich tables (`rent_listing_price_changes`, `sale_listing_price_changes`) and downstream paths such as `dw_sale.fact_listing_price_changes` still exist for historical reports and pricing lenses, but **new analyses should use `dw_listing.*`**.

### Predictions and suggestions (calculator / CPS)

Two tracks — **legacy (calculator predictions)** vs **current (CPS suggestions)**:

| Track | Enrich (source of truth) | DW | Status |
|-------|--------------------------|-----|--------|
| **Legacy — calculator predictions** | `datalake_ebdb_pricing.listing_prediction_changes` | `dw_listing.dim_price_predicted`, `dw_listing.fact_price_predicted` | **No longer source of truth.** Data ingestion is being discontinued; tables kept for **historical** analysis only. |
| **Current — CPS price suggestions** | `datalake_ebdb_pricing.house_suggestion_changes` | `dw_listing.dim_price_suggested`, `dw_listing.fact_price_suggested` | **Source of truth** for predictions/suggestions from CPS (also referred to as **sugestões de preço**). **Always prioritize this DW model** for suggestion analytics. |

**Calculator predictions (ML worker):** `datalake_pricing_clean.price_prediction` is a **reliable source** for **all** calculator-generated predictions (centralized Pricing Worker output — percentiles, model metadata, full prediction history). Use it when the analysis requires raw calculator output or complete prediction coverage. Even so, **always prioritize** `dw_listing.dim_price_suggested` + `fact_price_suggested` (fed by `house_suggestion_changes`) when the question is about price **suggestions** or DW-integrated pricing analysis.

### Grain and listing keys

Price changes and suggestions are scoped to the **house in a business context**, not to a listing version. **`id_house_listing` / `sk_house_listing` will be removed** from the official pricing modelings soon to avoid confusion — join and filter on **`sk_house`** + **`business_context`**.

The pricing lifecycle:
1. **First price** — initial rent or sale price registered (`change_type = 'FIRST_PRICE'`)
2. **Adjustments** — increases or decreases during publication (`change_type = 'PRICE_INCREASE'` / `'PRICE_DECREASE'`)
3. **Active window** — each change has `ts_price_started` and `ts_price_ended` (NULL/`is_last_price = TRUE` for current)
4. **Calculator/suggestion context** — attach CPS suggestions via `sk_price_suggested` on `fact_price_changes`; legacy calculator predictions via `sk_price_predicted` (historical only)

Legacy enrich paths (`rent_listing_price_changes`, `sale_listing_price_changes`) dedupe in SQL and still feed some sale DW tables and pricing lenses — prefer the official model above for new work.

## Glossary and Synonyms

- **Price change**, **alteração de preço**, **mudança de preço** → one registered price value change; PK `sk_pricing` (= `id_price_change`)
- **Current price**, **preço atual** → `dim_pricing.is_last_price = TRUE` for `(sk_house, business_context)`
- **Last price of day** → `is_last_price_of_day = TRUE` — use when counting daily price changes (new model)
- **First price variation** → percent change vs the very first price ever (`first_price_variation`)
- **Last price variation** → percent change vs immediately previous price (`last_price_variation`)
- **Pricing scheme / validity window** → interval between `ts_price_started` and `ts_price_ended`
- **Price suggestion**, **sugestão de preço**, **CPS suggestion** → current source of truth: **`house_suggestion_changes`** → `dim_price_suggested` / `fact_price_suggested` — **always prioritize** this DW model for suggestion analytics
- **Calculator prediction (ML worker)**, **predição calculadora** → **`datalake_pricing_clean.price_prediction`** — reliable source for **all** calculator predictions; use for raw/historical calculator output, but prefer official suggestion modeling when applicable
- **Calculator prediction (legacy DW)**, **preço calculadora (legado)** → **`listing_prediction_changes`** → `dim_price_predicted` / `fact_price_predicted` — **historical only**; ingestion ending
- **Smart Price**, **preço inteligente** → automated rent pricing (`dw_quintoandar.dim_smart_price`, `fact_listing_price_changes` in `dw_quintoandar` schema)
- **Valid price exchange** (legacy) → end-of-day price differs from first price of that day; rows failing this are excluded in legacy enrich SQL
- **RENT / SALE** → always filter `business_context`; same house has parallel price histories

## Tables

### Official — price changes

| You need... | Use this table |
|-------------|----------------|
| Price change attributes (rent + sale) | `dw_listing.dim_pricing` (`dp`) — PK `sk_pricing`; filter `is_last_price`, `is_last_price_of_day`, `business_context` |
| Price change facts with suggestion FKs | `dw_listing.fact_price_changes` (`fpc`) — join `dim_pricing` on `sk_pricing`; grain `sk_house` + `business_context` |
| Enrich source of truth (all intraday rows) | `datalake_ebdb_pricing.listing_price_change` — **not** `listing_price_changes` |

### Official — CPS suggestions (current predictions)

| You need... | Use this table |
|-------------|----------------|
| Suggestion attributes (rule, certainty, context) | `dw_listing.dim_price_suggested` — join via `fpc.sk_price_suggested <> -1` |
| Suggestion facts (bounds, suggested price, windows) | `dw_listing.fact_price_suggested` |
| Enrich source of truth | `datalake_ebdb_pricing.house_suggestion_changes` |

### Legacy — calculator predictions (historical)

| You need... | Use this table |
|-------------|----------------|
| Calculator prediction attributes | `dw_listing.dim_price_predicted` — **historical only**; join via `fpc.sk_price_predicted <> -1` |
| Calculator prediction facts | `dw_listing.fact_price_predicted` |
| Enrich source (ingestion ending) | `datalake_ebdb_pricing.listing_prediction_changes` |

### Calculator predictions (ML worker — clean layer)

| You need... | Use this table |
|-------------|----------------|
| All calculator predictions (reliable, complete history) | `datalake_pricing_clean.price_prediction` — percentiles (p10–p90), model metadata; **prioritize `dim_price_suggested` / `fact_price_suggested` for DW suggestion analytics** |

### Legacy / specialized paths

| You need... | Use this table |
|-------------|----------------|
| Sale price changes with calculator + ticket segment (legacy DW) | `dw_sale.fact_listing_price_changes` — PK `sk_price_change`; rich percentile columns |
| Sale ticket segment dimension | `dw_sale.dim_sale_price_segment` — `High Ticket` / `Low Ticket` |
| Smart Price rent changes (separate from sale fact!) | `dw_quintoandar.fact_listing_price_changes` + `dw_quintoandar.dim_smart_price` |
| Legacy enrich with daily dedup baked in | `datalake_ebdb_pricing.rent_listing_price_changes`, `datalake_sale_listings.sale_listing_price_changes` — pricing lenses only |

**Critical rules:**
- **Official price changes:** `listing_price_change` (singular) → `dw_listing.dim_pricing` + `fact_price_changes`. Do **not** treat `listing_price_changes` (plural) as source of truth.
- **Official suggestions:** `house_suggestion_changes` → `dim_price_suggested` + `fact_price_suggested`. **Always prioritize** this model for suggestion analytics. **`listing_prediction_changes` is legacy** — historical only; ingestion being discontinued.
- **Calculator predictions:** `datalake_pricing_clean.price_prediction` is reliable for **all** calculator predictions, but still **secondary** to the official suggestion DW model when both apply.
- **Grain:** price changes and suggestions are at **`(sk_house, business_context)`**. **`sk_house_listing` is being removed** from official pricing tables — do not build new logic on it.
- **New vs legacy dedup:** on `dw_listing.dim_pricing` / `listing_price_change`, filter `is_last_price_of_day = TRUE` when counting daily changes; legacy tables are already deduped.
- **`is_last_price` scope:** flags are at `(sk_house, business_context)` across all listing versions — a new price on any version updates prior rows.
- **`ts_price_ended` scope:** end timestamp closes the window at house+context level, ignoring listing version boundaries.
- **Two different `fact_listing_price_changes`:** `dw_sale.*` vs `dw_quintoandar.*` — different grains; never union blindly.
- **Temporal join for daily snapshots:** `dt >= DATE(ts_price_started) AND dt < COALESCE(DATE(ts_price_ended), DATE '2100-01-01')` plus `is_last_price_of_day`.
- **DataHub CI:** list concrete `schema.table` names only — never wildcards in the Tables section.

## Key Metrics

- Price change count (`change_number` or `COUNT(*)` with `is_last_price_of_day = TRUE`)
- Current published price (`price` where `is_last_price = TRUE` and `business_context` filtered)
- Price vs previous (`last_price_variation`, `previous_price`)
- Price vs first ever (`first_price_variation`)
- Days at current price (`days_with_pricing_scheme` on `fact_price_changes`)
- Smart Price change share (`is_smart_price_change` on sale fact or smart-price tables)
- Price vs calculator gap (legacy: `dim_price_predicted`; current: compare to `fact_price_suggested.suggested_price`)
- Suggestion certainty distribution (`suggestion_certainty` on `dim_price_suggested`)
- Sale ticket segment mix (`sk_sale_price_segment` on legacy `dw_sale.fact_listing_price_changes` — High Ticket if price ≥ 1M BRL per city rules)
- Average price changes per house in a period (filter `is_last_price_of_day`; grain is `sk_house` + `business_context`)

## Relationships with Other Entities

### House (N:1)

- `dw_listing.dim_pricing.sk_house = dw_house.dim_house.sk_house`
- See `business_entities/house_and_listing.md`.

### Listing (reference only — prefer house + context)

Official pricing grain is **`(sk_house, business_context)`**, not listing version. `sk_house_listing` still exists on some tables today but **will be removed** — do not use it in new queries. To relate price to a listing publication window, join `dim_pricing` on `sk_house` and align timestamps with listing tables from `business_entities/house_and_listing.md`.

## Dos and Don'ts

**Do:**
- Always filter `business_context IN ('RENT', 'SALE')` — the same house has parallel histories.
- Use **`dw_listing.dim_pricing` + `fact_price_changes`** fed by **`listing_price_change`** (singular) for official price change analysis.
- Use **`house_suggestion_changes` → `dim_price_suggested` + `fact_price_suggested`** for current CPS suggestions / sugestões de preço — **always prioritize** over other prediction sources for DW analytics.
- Use **`datalake_pricing_clean.price_prediction`** when you need **all** calculator predictions or raw ML worker output — reliable, but secondary to the official suggestion model when the question fits suggestion scope.
- Join on **`sk_house` + `business_context`** — the official pricing grain.
- Filter `is_last_price_of_day = TRUE` when counting daily price changes.
- Filter `is_last_price = TRUE` for current price questions.
- Use `listing_prediction_changes` / `dim_price_predicted` **only for historical** calculator analysis.
- Use temporal range joins (`ts_price_started` / `ts_price_ended`) when attaching price to daily snapshots.

**Don't:**
- Don't use **`listing_price_changes`** (plural) as source of truth — the official enrich is **`listing_price_change`** (singular).
- Don't use **`listing_prediction_changes`** for new prediction/suggestion work — use **`house_suggestion_changes`** / official suggestion DW instead.
- Don't default to **`price_prediction`** when **`dim_price_suggested` / `fact_price_suggested`** covers the analytical need — the DW suggestion model is the priority.
- Don't build new logic on **`sk_house_listing`** in pricing tables — it is being removed.
- Don't count raw rows from `listing_price_change` without `is_last_price_of_day` — intraday changes inflate counts.
- Don't union `dw_sale.fact_listing_price_changes` with `dw_quintoandar.fact_listing_price_changes` — different schemas and grains.
- Don't assume `change_number` resets per listing version — it increments at `(sk_house, business_context)`.
- Don't mix official `dw_listing.*` with legacy enrich tables in the same metric without aligning dedup rules.

## Golden Queries

### Query 1 — Current price per house (rent and sale)

```sql
SELECT
    dp.sk_house,
    dp.business_context,
    dp.price,
    dp.change_number,
    dp.change_type,
    fpc.ts_price_started
FROM dw_listing.dim_pricing AS dp
INNER JOIN dw_listing.fact_price_changes AS fpc
    ON dp.sk_pricing = fpc.sk_pricing
WHERE dp.is_last_price = TRUE
  AND dp.business_context IN ('RENT', 'SALE')
```

### Query 2 — Daily price changes in a period (new model)

```sql
SELECT
    DATE(fpc.ts_price_started) AS dt_change,
    dp.business_context,
    COUNT(*) AS price_changes,
    AVG(dp.last_price_variation) AS avg_variation_vs_previous
FROM dw_listing.dim_pricing AS dp
INNER JOIN dw_listing.fact_price_changes AS fpc
    ON dp.sk_pricing = fpc.sk_pricing
WHERE dp.is_last_price_of_day = TRUE
  AND dp.change_type <> 'FIRST_PRICE'
  AND DATE(fpc.ts_price_started) >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 3 — Price changes with CPS suggestion context (official model)

```sql
SELECT
    dp.sk_house,
    dp.business_context,
    dp.price,
    dp.previous_price,
    dp.last_price_variation,
    dp.change_type,
    fps.suggested_price,
    dps.suggestion_certainty,
    fpc.ts_price_started,
    fpc.ts_price_ended
FROM dw_listing.dim_pricing AS dp
INNER JOIN dw_listing.fact_price_changes AS fpc
    ON dp.sk_pricing = fpc.sk_pricing
LEFT JOIN dw_listing.fact_price_suggested AS fps
    ON fpc.sk_price_suggested = fps.sk_price_suggested
LEFT JOIN dw_listing.dim_price_suggested AS dps
    ON fpc.sk_price_suggested = dps.sk_price_suggested
WHERE dp.business_context = 'RENT'
  AND dp.is_last_price_of_day = TRUE
  AND DATE(fpc.ts_price_started) >= DATE '2026-01-01'
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
