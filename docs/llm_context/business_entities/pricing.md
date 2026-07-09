# Pricing

## Overview

**Pricing** tracks how rental and sale prices change over time for each house on QuintoAndar as well as how the pricing calculators behave. The grain is **`(sk_house, business_context)`** — the same physical property can have independent price histories and price predictions for RENT and SALE.

## Q: What is the source of truth for calculator data (Casio and Girafales)?

**Short answer:** it depends on the analytical layer — suggestions (CPS/DW), raw calculator output (Pricing Worker), or legacy DW.

| Question | Source of truth | Tables |
|----------|-----------------|--------|
| Current **price suggestions** linked to price changes and DW analytics | **CPS → enrich → DW** | `datalake_ebdb_pricing.house_suggestion_changes` → `dw_listing.dim_price_suggested`, `dw_listing.fact_price_suggested` |
| **All raw calculator predictions** (percentiles, model version, batch + online) | **Pricing Worker (clean)** | `datalake_pricing_clean.price_prediction` |
| **Historical** calculator predictions in legacy DW shape | Legacy only (ingestion ending) | `datalake_ebdb_pricing.listing_prediction_changes` → `dw_listing.dim_price_predicted`, `fact_price_predicted` |

**Calculator names (confirmed — DS Pricing DAG `pricing`):**

| Calculator | Business context | `price_prediction.model_name` | Role |
|------------|------------------|-------------------------------|------|
| **Casio** | RENT (ForRent) | `casio` | Full rent price calculator |
| **Casio-lite** | RENT | `casio-lite` | Lightweight rent model (may lack `id_house`) |
| **Girafales** | SALE (ForSale) | `girafales` | Full sale price calculator |
| **Girafales-lite** | SALE | `girafales-lite` | Lightweight sale model |

Filter **`business_context = 'RENT'`** for Casio-family predictions and **`'SALE'`** for Girafales-family on `price_prediction`. CPS suggestions use the same RENT/SALE split on `house_suggestion_changes.business_context` — there is **no** separate `model_name` column in the suggestion DW; link back to the raw prediction via **`id_prediction`** when needed.

**Priority rule for TARS:** when the question is about **sugestões de preço**, price vs suggestion gap, or anything joined to `fact_price_changes`, use **`dim_price_suggested` + `fact_price_suggested`** first. Use **`price_prediction`** when the question needs **all** calculator runs, percentiles, model metadata, or coverage beyond what CPS persisted. Do **not** use legacy `listing_prediction_changes` for new work.

**Not calculator source of truth:** `datalake_emlio_clean.casio` (EMLIO model **input** logs for ML ops) — do not use for pricing analytics.

## Q: Where is the recommended / suggested price?

**Short answer:** **preço recomendado**, **preço sugerido**, and **CPS suggestion** mean the same thing — use the **CPS / DW suggestion model**, not raw calculator percentiles.

| Synonym (PT/EN) | Source of truth | Columns |
|-----------------|-----------------|---------|
| preço recomendado, preço sugerido, suggested price, CPS suggestion | `datalake_ebdb_pricing.house_suggestion_changes` → **`dw_listing.fact_price_suggested`** + **`dim_price_suggested`** | **`suggested_price`** (anchor), `suggested_lower_bound_price`, `suggested_upper_bound_price`, `suggestion_certainty`, `business_context` |
| Current suggestion per house | Filter `fact_price_suggested.is_last_suggestion = TRUE` on `(sk_house, business_context)` | |

Join to price changes via `fact_price_changes.sk_price_suggested`. Link to the underlying calculator run via `fact_price_suggested.sk_prediction` = `price_prediction.id_prediction` when needed.

### When the question mentions p70 or p90

**p70 / p90 are calculator percentiles**, not column names on the CPS suggestion table. Use them only when the analyst asks for **distribution percentiles** or **model output**, not for “recommended price”.

| Need | Table | Columns |
|------|-------|---------|
| Percentile distribution (p10–p90) | `datalake_pricing_clean.price_prediction` | `p10` … `p90`, `prediction_certainty`, `model_name`, `id_house`, `ts_created` |

**Product reference percentiles** (internal rule for ideal-price comparison — may change; **not** the same as `suggested_price`):

| Context | Reference percentile | Column in `price_prediction` |
|---------|---------------------|------------------------------|
| RENT | p90 | `p90` |
| SALE | p70 | `p70` |

**`suggested_price`** is the persisted business recommendation from CPS — it may incorporate rules beyond a single percentile. Do **not** answer “preço recomendado?” with `price_prediction.p70` or `p90` unless the user explicitly asks for percentiles.

**Legacy:** `datalake_ebdb_clean.house_predicted_price` (`p_70`, `p_90` with underscore) — historical only; prefer CPS for suggestions and `price_prediction` for percentiles.

## Q: What is an overpriced listing (imóvel overpriced)?

**Short answer:** a listing whose **published price is above the ideal range** estimated by the calculator/CPS for its vertical. The opposite is **well priced** (within the ideal range).

### Ideal-limit rule (binary)

Product rule of thumb — published price **above** the reference percentile for the vertical:

| Context | Reference | Compare |
|---------|-----------|---------|
| **RENT** | p90 | `dim_pricing.price` (`is_last_price = TRUE`) **>** `price_prediction.p90` — or **>** CPS `suggested_upper_bound_price` |
| **SALE** | p70 | same pattern with **`p70`** |

**Well priced (binary):** listed price **≤** that reference (or within CPS bounds).

For price-vs-reference comparisons, analysts **may** exclude **`low`** and **`none`** at their discretion — **official metrics do not require this filter**; see certainty section below.

## Q: What is the best calculator reference for overpriced analysis?

**Pick by analytical goal:**

| Goal | Best reference | Where |
|------|----------------|-------|
| **Binary “above ideal limit?”** | **RENT → `p90`**; **SALE → `p70`** | `price_prediction.p90` / `p70` joined to `dim_pricing.price` (`is_last_price = TRUE`, same `business_context`) |
| **Above CPS suggested ceiling?** | **`suggested_upper_bound_price`** | `fact_price_suggested` (current suggestion: `is_last_suggestion = TRUE`) |
| **% gap vs market estimate** (custom bins) | **P50** (median prediction) | `price_prediction.p50`; legacy enrich `calculator_price` on `rent_listing_price_changes` / sale equivalent |

**Default routing for TARS:**

1. Question is **“is this listing overpriced?”** (binary) → **p90 (RENT) / p70 (SALE)** vs `dim_pricing.price`; certainty filter on the join is optional at analyst discretion.
2. Question is **“above the recommended/suggested range?”** → CPS bounds on **`fact_price_suggested`**, not raw percentiles alone.
3. Question is **“% gap vs calculator estimate?”** → **`price_prediction.p50`** vs listed price.

The p90/p70 rule is a **documented product rule** for ideal-limit checks — state the rule used in the query comment.

**Join pattern (binary rule):**

```sql
-- Latest published price vs reference percentile (example: RENT)
SELECT
    dp.sk_house,
    dp.price AS listed_price,
    pp.p90 AS reference_percentile,
    dp.price > pp.p90 AS is_overpriced_binary
FROM dw_listing.dim_pricing AS dp
INNER JOIN datalake_pricing_clean.price_prediction AS pp
    ON dp.sk_house = pp.id_house
   AND dp.business_context = pp.business_context
WHERE dp.is_last_price = TRUE
  AND dp.business_context = 'RENT'
  -- dedupe to latest prediction per house+context in production queries
```

### Related (not the same as overpriced tier)

- **Quality Pub / Quality 4Ws** (RENT metric) — uses `price_score` from listing scores; see `metric_entities/supply_quality_score.md`
- **Overpriced comms** — Amplitude events `listing_overpriced_comms_routine_*`; ops in `sale_operation_management` — campaign/communication flows, not the analytics definition above

## Q: What does prediction / suggestion certainty mean? Should I filter it?

**Two columns — do not conflate:**

| Column | Table | Meaning |
|--------|-------|---------|
| **`suggestion_certainty`** | `dim_price_suggested`, `house_suggestion_changes` | CPS confidence in the **persisted price suggestion** |
| **`prediction_certainty`** | `price_prediction` | Pricing Worker confidence in the **raw calculator prediction** |

**Values in prod (lowercase on CPS / Pricing Worker):** `high`, `medium`, `low`, `none` — ~49% high, ~34% medium, ~14% low, ~0.1% none on `dim_price_suggested` (BR, prod snapshot).

**Should you filter?**

| Analysis | Filter certainty? |
|----------|-------------------|
| **Compare listed price vs CPS `suggested_price` or bounds** | **Analyst choice** — may exclude `low` and `none` on `suggestion_certainty`; official metrics do not require it |
| **Compare listed price vs `price_prediction` percentiles (p70/p90)** | **Analyst choice** — may exclude `low` and `none` on `prediction_certainty`; official metrics do not require it |
| **Certainty distribution / model quality** | **No filter** — report all levels |
| **Strict pricing-quality cohorts** | Optional: keep only `high` (and sometimes `medium`) — state explicitly in the query |

Example filter when the analyst chooses to narrow the cohort:

```sql
AND dps.suggestion_certainty NOT IN ('low', 'none')
-- or: AND pp.prediction_certainty NOT IN ('low', 'none')
```

Do **not** defer to `safe_fields` for certainty values — categories are documented above and in metadata YAML.

## Official model

### Price changes

The **official DW model** for registered price changes is:

- **`dw_listing.dim_pricing`** + **`dw_listing.fact_price_changes`**

The **only enrich source of truth** for price changes is:

- **`datalake_ebdb_pricing.listing_price_change`** (singular — **not** `listing_price_changes`)

Legacy enrich tables (`rent_listing_price_changes`, `sale_listing_price_changes`) and downstream paths such as `dw_sale.fact_listing_price_changes` still exist for historical reports, but **new analyses should use `dw_listing.*`**.

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

Legacy enrich paths (`rent_listing_price_changes`, `sale_listing_price_changes`) dedupe in SQL and still feed some sale DW tables — prefer the official model above for new work.

## Glossary and Synonyms

- **Price change**, **alteração de preço**, **mudança de preço** → one registered price value change; PK `sk_pricing` (= `id_price_change`)
- **Current price**, **preço atual** → `dim_pricing.is_last_price = TRUE` for `(sk_house, business_context)`
- **Last price of day** → `is_last_price_of_day = TRUE` — use when counting daily price changes (new model)
- **First price variation** → percent change vs the very first price ever (`first_price_variation`)
- **Last price variation** → percent change vs immediately previous price (`last_price_variation`)
- **Pricing scheme / validity window** → interval between `ts_price_started` and `ts_price_ended`
- **Price suggestion**, **sugestão de preço**, **preço sugerido**, **preço recomendado**, **CPS suggestion** → **`fact_price_suggested.suggested_price`** (+ bounds) via **`house_suggestion_changes`** — default for “recommended/suggested price” questions
- **Casio**, **calculadora de aluguel** → RENT price calculator; raw output in **`price_prediction`** (`model_name IN ('casio', 'casio-lite')`, `business_context = 'RENT'`); operational suggestions via CPS → **`house_suggestion_changes`** with `business_context = 'RENT'`
- **Girafales**, **calculadora de venda** → SALE price calculator; raw output in **`price_prediction`** (`model_name IN ('girafales', 'girafales-lite')`, `business_context = 'SALE'`); operational suggestions via CPS with `business_context = 'SALE'`
- **CPS**, **Centralized Pricing Service** → service that turns calculator predictions into persisted **suggestions** (`house_price_suggestion_historical` → `house_suggestion_changes`); links to raw prediction via **`id_prediction`**
- **Calculator prediction (ML worker)**, **predição calculadora** → **`datalake_pricing_clean.price_prediction`** — percentile distribution only; **not** the CPS suggested price
- **Calculator prediction (legacy DW)**, **preço calculadora (legado)** → **`listing_prediction_changes`** → `dim_price_predicted` / `fact_price_predicted` — **historical only**; ingestion ending
- **Smart Price**, **preço inteligente** → automated rent pricing (`dw_quintoandar.dim_smart_price`, `fact_listing_price_changes` in `dw_quintoandar` schema)
- **Valid price exchange** (legacy) → end-of-day price differs from first price of that day; rows failing this are excluded in legacy enrich SQL
- **p70 / p90**, **percentil calculadora** → **`price_prediction.p70` / `p90`** — use only when percentiles are explicitly requested, not for preço recomendado/sugerido
- **Overpriced**, **imóvel overpriced**, **caro demais** → listed price **>** p90 (RENT) / p70 (SALE) on `price_prediction`, or above CPS `suggested_upper_bound_price`
- **Suggestion certainty**, **prediction certainty** → `suggestion_certainty` (CPS/DW) or `prediction_certainty` (`price_prediction`); values `high`, `medium`, `low`, `none` — analysts may exclude `low`/`none` at discretion; official metrics do not require it
- **Well priced**, **preço bem precificado** → listed price within ideal limit (≤ p90 RENT / ≤ p70 SALE) or within CPS bounds

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
| Raw percentiles p10–p90 (Casio/Girafales) | `datalake_pricing_clean.price_prediction` — columns `p10`…`p90`; join CPS via `id_prediction` |
| CPS suggested price + bounds | `dw_listing.fact_price_suggested` — `suggested_price`, `suggested_lower_bound_price`, `suggested_upper_bound_price` |

### Legacy / specialized paths

| You need... | Use this table |
|-------------|----------------|
| Sale price changes with calculator + ticket segment (legacy DW) | `dw_sale.fact_listing_price_changes` — PK `sk_price_change`; rich percentile columns |
| Sale ticket segment dimension | `dw_sale.dim_sale_price_segment` — `High Ticket` / `Low Ticket` |
| Smart Price rent changes (separate from sale fact!) | `dw_quintoandar.fact_listing_price_changes` + `dw_quintoandar.dim_smart_price` |
| Legacy enrich with daily dedup baked in | `datalake_ebdb_pricing.rent_listing_price_changes`, `datalake_sale_listings.sale_listing_price_changes` |

**Critical rules:**
- **Casio / Girafales:** RENT = Casio (`casio`, `casio-lite`); SALE = Girafales (`girafales`, `girafales-lite`) — see **Q: source of truth for calculator data** above.
- **Overpriced (binary):** RENT → compare listed price to **`price_prediction.p90`**; SALE → **`p70`**; certainty filter is optional at analyst discretion. Alternative: compare to CPS **`suggested_upper_bound_price`**.
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
- Don't answer **“overpriced?”** without stating the rule — use **p90 (RENT) / p70 (SALE)** vs `dim_pricing.price`, or CPS upper bound; certainty exclusion is optional and not used in official metrics.
- Don't defer **certainty values** to `safe_fields` — use `high`, `medium`, `low`, `none` on `suggestion_certainty` / `prediction_certainty`.
- Don't answer **“preço recomendado / sugerido”** with **`price_prediction.p70` or `p90`** — use **`fact_price_suggested.suggested_price`** (CPS).
- Don't use **`datalake_emlio_clean.casio`** for pricing analytics — it logs ML model inputs, not calculator/suggestion output.
- Don't hedge on Casio/Girafales scope — Casio = RENT, Girafales = SALE (see glossary and `pricing` DAG documentation).
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

### Query 4 — Recommended / suggested price (CPS — default for “preço recomendado”)

```sql
SELECT
    fps.sk_house,
    dps.business_context,
    fps.suggested_price,
    fps.suggested_lower_bound_price,
    fps.suggested_upper_bound_price,
    dps.suggestion_certainty,
    fps.ts_suggestion_started,
    fps.ts_suggestion_ended
FROM dw_listing.fact_price_suggested AS fps
INNER JOIN dw_listing.dim_price_suggested AS dps
    ON fps.sk_price_suggested = dps.sk_price_suggested
WHERE fps.is_last_suggestion = TRUE
  AND dps.business_context IN ('RENT', 'SALE')
```

### Query 5 — Calculator percentiles p70 / p90 (only when percentiles are explicitly needed)

```sql
SELECT
    pp.id_house,
    pp.business_context,
    pp.p70,
    pp.p90,
    pp.p50,
    pp.prediction_certainty,
    pp.ts_created
FROM datalake_pricing_clean.price_prediction AS pp
WHERE pp.id_house = 12345
  -- one row per business_context (RENT = Casio, SALE = Girafales)
ORDER BY pp.business_context, pp.ts_created DESC
LIMIT 10
```

### Query 6 — Listed price vs CPS suggestion (join via price change)

```sql
SELECT
    dp.sk_house,
    dp.business_context,
    dp.price AS listed_price,
    fps.suggested_price AS recommended_price,
    dps.suggestion_certainty,
    fpc.ts_price_started
FROM dw_listing.dim_pricing AS dp
INNER JOIN dw_listing.fact_price_changes AS fpc
    ON dp.sk_pricing = fpc.sk_pricing
LEFT JOIN dw_listing.fact_price_suggested AS fps
    ON fpc.sk_price_suggested = fps.sk_price_suggested
LEFT JOIN dw_listing.dim_price_suggested AS dps
    ON fpc.sk_price_suggested = dps.sk_price_suggested
WHERE dp.is_last_price = TRUE
  AND dp.business_context IN ('RENT', 'SALE')
```

### Query 7 — Overpriced listings (binary rule — RENT example)

```sql
-- Listed price above p90; optional certainty filter at analyst discretion (official metrics do not require it)
SELECT
    dp.sk_house,
    dp.price AS listed_price,
    pp.p90 AS reference_p90,
    pp.prediction_certainty,
    dp.price > pp.p90 AS is_overpriced
FROM dw_listing.dim_pricing AS dp
INNER JOIN datalake_pricing_clean.price_prediction AS pp
    ON dp.sk_house = pp.id_house
   AND dp.business_context = pp.business_context
WHERE dp.is_last_price = TRUE
  AND dp.business_context = 'RENT'
  -- AND pp.prediction_certainty NOT IN ('low', 'none')  -- optional; analyst choice
  AND dp.price > pp.p90
-- dedupe to latest prediction per house+context in production queries
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
