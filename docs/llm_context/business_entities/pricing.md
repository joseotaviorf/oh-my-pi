# Pricing

## Ownership

**Data Owner:**
- bruna.prates@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br
- carolina.almeida@quintoandar.com.br

| Scope                                                               | Role         | Contact                                                                           |
| ------------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------- |
| **Pricing analytics** (price changes, CPS, calculators, overpriced) | Data steward | [bruna.prates@quintoandar.com.br](mailto:bruna.prates@quintoandar.com.br)         |
| **Pricing AI analytics** (Maria / WhatsApp pricing agent)           | Data steward | [carolina.almeida@quintoandar.com.br](mailto:carolina.almeida@quintoandar.com.br) |

Squad: Owner XP / Listing Management.

## Overview

**Pricing** tracks how rental and sale prices change over time for each house on QuintoAndar as well as how the pricing calculators behave. The grain is `**(sk_house, business_context)`** — the same physical property can have independent price histories and price predictions for RENT and SALE.

**TARS — RENT vs SALE on tables:** classify a table as rent, sale, or both only when **this document** (or the linked business entity) **explicitly** documents that scope on the table — e.g. `dw_listing.*` = **both** (`business_context` filter required); `dw_rent.*` / `dw_sale.*` entries should say **just rent** / **just sale** (not “RENT only” / “SALE only” — hybrids can still exist). Do not infer from naming alone.

## Related Metric Entities

- Quality of Supply (Pricing Levers) — Pub & 4Ws — RENT combined price + easy entry; see [`metric_entities/supply_quality_score.md`](metric_entities/supply_quality_score.md)
- Supply Pricing Score (Owner Activation H2 2026) — official **price-only** OKR scores (RENT `AVG(score_4w)`, SALE `AVG(score_8w)`); see [`metric_entities/supply_pricing_score.md`](metric_entities/supply_pricing_score.md)
- Owner Activation Listing Churn (H2 2026) — cohort churn OKR (`COUNT DISTINCT` churned / matured, RENT 4w / SALE 8w); sibling KR in same Cockpit dataset; see [`metric_entities/owner_activation_listing_churn.md`](metric_entities/owner_activation_listing_churn.md)

## Q: What is the source of truth for listing price (preço do anúncio)?

**Short answer:** the **official pricing model** — **`dw_listing.dim_pricing`** + **`dw_listing.fact_price_changes`** — for **RENT and SALE**, **current and historical**.

| Need | Source of truth | How |
|------|-----------------|-----|
| **Current** listing price (preço vigente) | `dw_listing.dim_pricing.price` | `is_last_price = TRUE` + `business_context IN ('RENT', 'SALE')` on `(sk_house, business_context)` |
| **Historical** listing prices (timeline) | Same model | All rows on `dim_pricing` / `fact_price_changes` — `ts_price_started`, `ts_price_ended`, `change_type`; filter `is_last_price_of_day` when counting **daily** changes |
| Join to listing / house | `dim_pricing.sk_house` = `dim_house.sk_house` (or `dim_house_listing.id_house`) | Always filter **`business_context`** — never mix RENT and SALE |

**Do not use for official listing price analytics:**

| Column / table | Why not |
|----------------|---------|
| `dw_rent.dim_house_listing.rent`, `house_rent`, `COALESCE(rent, house_rent)` | EBDB snapshot on the listing dimension — **not** the pricing DW model; can drift from registered price changes |
| `dw_sale.dim_listing.price` | CDC snapshot of `imovel.salePrice` — convenient for some sale flows, **not** the official price-change history; use **`dw_listing.dim_pricing`** for analytics |
| `datalake_ebdb_listing.house` rent/sale price fields | Enrich only — prefer **`dw_listing.*`** |

**TARS routing:** questions like **“preço do anúncio”**, **“listing price”**, **“preço publicado”**, **“como identificar dados do listing — preço”** → answer with **`dim_pricing` + `fact_price_changes`** and link here — **not** `dim_house_listing.rent` / `sale_price`.

**Exception (documented elsewhere):** offer/CCV **discount** analysis on SALE may use **`dim_offer.sale_price`** (snapshot at offer time) vs **`sale_price_agreed`** — see `business_entities/fs-transact.md` §3.4. That is **not** a substitute for the general listing-price source of truth above.

## Q: What is the source of truth for calculator data (Casio and Girafales)?

**Short answer:** it depends on the analytical layer — suggestions (CPS/DW), raw calculator output (Pricing Worker), or legacy DW.


| Question                                                                        | Source of truth                | Tables                                                                                                                 |
| ------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Current **price suggestions** linked to price changes and DW analytics          | **CPS → enrich → DW**          | `datalake_ebdb_pricing.house_suggestion_changes` → `dw_listing.dim_price_suggested`, `dw_listing.fact_price_suggested` |
| **All raw calculator predictions** (percentiles, model version, batch + online) | **Pricing Worker (clean)**     | `datalake_pricing_clean.price_prediction`                                                                              |
| **Historical** calculator predictions in legacy DW shape                        | Legacy only (ingestion ending) | `datalake_ebdb_pricing.listing_prediction_changes` → `dw_listing.dim_price_predicted`, `fact_price_predicted`          |


**Calculator names (confirmed — DS Pricing DAG** `pricing`**):**


| Calculator         | Business context | `price_prediction.model_name` | Role                                         |
| ------------------ | ---------------- | ----------------------------- | -------------------------------------------- |
| **Casio**          | RENT (ForRent)   | `casio`                       | Full rent price calculator                   |
| **Casio-lite**     | RENT             | `casio-lite`                  | Lightweight rent model (may lack `id_house`) |
| **Girafales**      | SALE (ForSale)   | `girafales`                   | Full sale price calculator                   |
| **Girafales-lite** | SALE             | `girafales-lite`              | Lightweight sale model                       |


Filter `**business_context = 'RENT'**` for Casio-family predictions and `**'SALE'**` for Girafales-family on `price_prediction`. CPS suggestions use the same RENT/SALE split on `house_suggestion_changes.business_context` — there is **no** separate `model_name` column in the suggestion DW; link back to the raw prediction via `**id_prediction`** when needed.

**Priority rule for TARS:** when the question is about **sugestões de preço**, price vs suggestion gap, or anything joined to `fact_price_changes`, use `**dim_price_suggested` + `fact_price_suggested`** first. Use `**price_prediction`** when the question needs **all** calculator runs, percentiles, model metadata, or coverage beyond what CPS persisted. Do **not** use legacy `listing_prediction_changes` for new work.

**Not calculator source of truth:** `datalake_emlio_clean.casio` (EMLIO model **input** logs for ML ops) — do not use for pricing analytics.

## Q: Where is the recommended / suggested price?

**Short answer:** **preço recomendado**, **preço sugerido**, and **CPS suggestion** mean the same thing — use the **CPS / DW suggestion model**, not raw calculator percentiles.


| Synonym (PT/EN)                                                    | Source of truth                                                                                                      | Columns                                                                                                                                  |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| preço recomendado, preço sugerido, suggested price, CPS suggestion | `datalake_ebdb_pricing.house_suggestion_changes` → `**dw_listing.fact_price_suggested**` + `**dim_price_suggested**` | `**suggested_price**` (anchor), `suggested_lower_bound_price`, `suggested_upper_bound_price`, `suggestion_certainty`, `business_context` |
| Current suggestion per house                                       | Filter `fact_price_suggested.is_last_suggestion = TRUE` on `(sk_house, business_context)`                            |                                                                                                                                          |


Join to price changes via `fact_price_changes.sk_price_suggested`. Link to the underlying calculator run via `fact_price_suggested.sk_prediction` = `price_prediction.id_prediction` when needed.

### When the question mentions p70 or p90

**p70 / p90 are calculator percentiles**, not column names on the CPS suggestion table. Use them only when the analyst asks for **distribution percentiles** or **model output**, not for “recommended price”.


| Need                              | Table                                     | Columns                                                                       |
| --------------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------- |
| Percentile distribution (p10–p90) | `datalake_pricing_clean.price_prediction` | `p10` … `p90`, `prediction_certainty`, `model_name`, `id_house`, `ts_created` |


**Product reference percentiles** (internal rule for ideal-price comparison — may change; **not** the same as `suggested_price`):


| Context | Reference percentile | Column in `price_prediction` |
| ------- | -------------------- | ---------------------------- |
| RENT    | p90                  | `p90`                        |
| SALE    | p70                  | `p70`                        |


`**suggested_price**` is the persisted business recommendation from CPS — it may incorporate rules beyond a single percentile. Do **not** answer “preço recomendado?” with `price_prediction.p70` or `p90` unless the user explicitly asks for percentiles.

**Legacy:** `datalake_ebdb_clean.house_predicted_price` (`p_70`, `p_90` with underscore) — historical only; prefer CPS for suggestions and `price_prediction` for percentiles.

## Q: What is an overpriced listing (imóvel overpriced)?

**Short answer:** a listing whose **published price is above the ideal range** estimated by the calculator/CPS for its vertical. The opposite is **well priced** (within the ideal range).

### Ideal-limit rule (binary)

Product rule of thumb — published price **above** the reference percentile for the vertical:


| Context  | Reference | Compare                                                                                                                |
| -------- | --------- | ---------------------------------------------------------------------------------------------------------------------- |
| **RENT** | p90       | `dim_pricing.price` (`is_last_price = TRUE`) **>** `price_prediction.p90` — or **>** CPS `suggested_upper_bound_price` |
| **SALE** | p70       | same pattern with `**p70`**                                                                                            |


**Well priced (binary):** listed price **≤** that reference (or within CPS bounds).

For **share well priced / overpriced by NL and OL**, see `metric_entities/listing_to_well_priced.md` — **OL** uses this p90/p70 snapshot rule on current stock; **NL** cohort uses `sandbox.listing_scores` (`price_score_pub` / FL2WP, RL2WP, RC2WP).

For price-vs-reference comparisons, analysts **may** exclude **`low`** and **`none`** at their discretion — **official metrics do not require this filter**; see certainty section below.

## Q: What is the best calculator reference for overpriced analysis?

**Pick by analytical goal:**


| Goal                                       | Best reference                     | Where                                                                                                          |
| ------------------------------------------ | ---------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Binary “above ideal limit?”**            | **RENT →** `p90`; **SALE →** `p70` | `price_prediction.p90` / `p70` joined to `dim_pricing.price` (`is_last_price = TRUE`, same `business_context`) |
| **Above CPS suggested ceiling?**           | `**suggested_upper_bound_price`**  | `fact_price_suggested` (current suggestion: `is_last_suggestion = TRUE`)                                       |
| **% gap vs market estimate** (custom bins) | **P50** (median prediction)        | `price_prediction.p50`; legacy enrich `calculator_price` on `rent_listing_price_changes` / sale equivalent     |


**Default routing for TARS:**

1. Question is **“is this listing overpriced?”** (binary) → **p90 (RENT) / p70 (SALE)** vs `dim_pricing.price`; certainty filter on the join is optional at analyst discretion.
2. Question is **“above the recommended/suggested range?”** → CPS bounds on `**fact_price_suggested`**, not raw percentiles alone.
3. Question is **“% gap vs calculator estimate?”** → `**price_prediction.p50`** vs listed price.

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

- **Quality Pub / Quality 4Ws** (RENT metric) — combined `price_score` + `easy_entry`; see [`metric_entities/supply_quality_score.md`](metric_entities/supply_quality_score.md)
- **L2Wp / Listing to Well Priced** (RENT) — **price-only** cohort share from the same `price_score` source; see [`metric_entities/listing_to_well_priced.md`](metric_entities/listing_to_well_priced.md)
- **Supply Pricing Score (Owner Activation)** — price-only OKR 0–4 scores RENT+SALE; see [`metric_entities/supply_pricing_score.md`](metric_entities/supply_pricing_score.md) (distinct from Quality 4Ws formula)
- **Overpriced comms** — Amplitude events `listing_overpriced_comms_routine_*`; ops in `sale_operation_management` — campaign/communication flows, not the analytics definition above

## Q: What does prediction / suggestion certainty mean? Should I filter it?

**Two columns — do not conflate:**


| Column                     | Table                                             | Meaning                                                        |
| -------------------------- | ------------------------------------------------- | -------------------------------------------------------------- |
| `**suggestion_certainty**` | `dim_price_suggested`, `house_suggestion_changes` | CPS confidence in the **persisted price suggestion**           |
| `**prediction_certainty**` | `price_prediction`                                | Pricing Worker confidence in the **raw calculator prediction** |


**Values in prod (lowercase on CPS / Pricing Worker):** `high`, `medium`, `low`, `none` — ~49% high, ~34% medium, ~14% low, ~0.1% none on `dim_price_suggested` (BR, prod snapshot).

**Should you filter?**


| Analysis                                                                 | Filter certainty?                                                                                               |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| **Compare listed price vs CPS** `suggested_price` **or bounds**          | **Analyst choice** — may exclude `low` and `none` on `suggestion_certainty`; official metrics do not require it |
| **Compare listed price vs** `price_prediction` **percentiles (p70/p90)** | **Analyst choice** — may exclude `low` and `none` on `prediction_certainty`; official metrics do not require it |
| **Certainty distribution / model quality**                               | **No filter** — report all levels                                                                               |
| **Strict pricing-quality cohorts**                                       | Optional: keep only `high` (and sometimes `medium`) — state explicitly in the query                             |


Example filter when the analyst chooses to narrow the cohort:

```sql
AND dps.suggestion_certainty NOT IN ('low', 'none')
-- or: AND pp.prediction_certainty NOT IN ('low', 'none')
```

Do **not** defer to `safe_fields` for certainty values — categories are documented above and in metadata YAML.

## Official model



### Price changes

The **official DW model** for registered price changes is:

- `**dw_listing.dim_pricing**` + `**dw_listing.fact_price_changes**`

The **only enrich source of truth** for price changes is:

- `**datalake_ebdb_pricing.listing_price_change**` (singular — **not** `listing_price_changes`)

Legacy enrich tables (`rent_listing_price_changes`, `sale_listing_price_changes`) and downstream paths such as `dw_sale.fact_listing_price_changes` still exist for historical reports, but **new analyses should use** `dw_listing.`*.

### Predictions and suggestions (calculator / CPS)

Two tracks — **legacy (calculator predictions)** vs **current (CPS suggestions)**:


| Track                               | Enrich (source of truth)                           | DW                                                                  | Status                                                                                                                                                               |
| ----------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Legacy — calculator predictions** | `datalake_ebdb_pricing.listing_prediction_changes` | `dw_listing.dim_price_predicted`, `dw_listing.fact_price_predicted` | **No longer source of truth.** Data ingestion is being discontinued; tables kept for **historical** analysis only.                                                   |
| **Current — CPS price suggestions** | `datalake_ebdb_pricing.house_suggestion_changes`   | `dw_listing.dim_price_suggested`, `dw_listing.fact_price_suggested` | **Source of truth** for predictions/suggestions from CPS (also referred to as **sugestões de preço**). **Always prioritize this DW model** for suggestion analytics. |


**Calculator predictions (ML worker):** `datalake_pricing_clean.price_prediction` is a **reliable source** for **all** calculator-generated predictions (centralized Pricing Worker output — percentiles, model metadata, full prediction history). Use it when the analysis requires raw calculator output or complete prediction coverage. Even so, **always prioritize** `dw_listing.dim_price_suggested` + `fact_price_suggested` (fed by `house_suggestion_changes`) when the question is about price **suggestions** or DW-integrated pricing analysis.

### Grain and listing keys

Price changes and suggestions are scoped to the **house in a business context**, not to a listing version. `**id_house_listing` / `sk_house_listing` will be removed** from the official pricing modelings soon to avoid confusion — join and filter on `**sk_house`** + `**business_context`**.

The pricing lifecycle:

1. **First price** — initial rent or sale price registered (`change_type = 'FIRST_PRICE'`)
2. **Adjustments** — increases or decreases during publication (`change_type = 'PRICE_INCREASE'` / `'PRICE_DECREASE'`)
3. **Active window** — each change has `ts_price_started` and `ts_price_ended` (NULL/`is_last_price = TRUE` for current)
4. **Calculator/suggestion context** — attach CPS suggestions via `sk_price_suggested` on `fact_price_changes`; legacy calculator predictions via `sk_price_predicted` (historical only)

Legacy enrich paths (`rent_listing_price_changes`, `sale_listing_price_changes`) dedupe in SQL and still feed some sale DW tables — prefer the official model above for new work.

## Glossary and Synonyms

- **Price change**, **alteração de preço**, **mudança de preço** → one registered price value change; PK `sk_pricing` (= `id_price_change`)
- **Current price**, **preço atual**, **preço do anúncio**, **preço publicado**, **listing price** → **`dw_listing.dim_pricing.price`** (`is_last_price = TRUE`, `business_context`) + history on **`fact_price_changes`** — **not** `dim_house_listing.rent` / `house_rent` / `dim_listing.price`
- **Last price of day** → `is_last_price_of_day = TRUE` — use when counting daily price changes (new model)
- **First price variation** → percent change vs the very first price ever (`first_price_variation`)
- **Last price variation** → percent change vs immediately previous price (`last_price_variation`)
- **Pricing scheme / validity window** → interval between `ts_price_started` and `ts_price_ended`
- **Price suggestion**, **sugestão de preço**, **preço sugerido**, **preço recomendado**, **CPS suggestion** → `**fact_price_suggested.suggested_price`** (+ bounds) via `**house_suggestion_changes`** — default for “recommended/suggested price” questions
- **Casio**, **calculadora de aluguel** → RENT price calculator; raw output in `**price_prediction`** (`model_name IN ('casio', 'casio-lite')`, `business_context = 'RENT'`); operational suggestions via CPS → `**house_suggestion_changes`** with `business_context = 'RENT'`
- **Girafales**, **calculadora de venda** → SALE price calculator; raw output in `**price_prediction`** (`model_name IN ('girafales', 'girafales-lite')`, `business_context = 'SALE'`); operational suggestions via CPS with `business_context = 'SALE'`
- **CPS**, **Centralized Pricing Service** → service that turns calculator predictions into persisted **suggestions** (`house_price_suggestion_historical` → `house_suggestion_changes`); links to raw prediction via `**id_prediction`**
- **Calculator prediction (ML worker)**, **predição calculadora** → `**datalake_pricing_clean.price_prediction`** — percentile distribution only; **not** the CPS suggested price
- **Calculator prediction (legacy DW)**, **preço calculadora (legado)** → `**listing_prediction_changes`** → `dim_price_predicted` / `fact_price_predicted` — **historical only**; ingestion ending
- **Smart Price**, **preço inteligente** → automated rent pricing (`dw_quintoandar.dim_smart_price`, `fact_listing_price_changes` in `dw_quintoandar` schema)
- **Valid price exchange** (legacy) → end-of-day price differs from first price of that day; rows failing this are excluded in legacy enrich SQL
- **p70 / p90**, **percentil calculadora** → `**price_prediction.p70` / `p90`** — use only when percentiles are explicitly requested, not for preço recomendado/sugerido
- **Overpriced**, **imóvel overpriced**, **caro demais** → listed price **>** p90 (RENT) / p70 (SALE) on `price_prediction`, or above CPS `suggested_upper_bound_price`
- **Suggestion certainty**, **prediction certainty** → `suggestion_certainty` (CPS/DW) or `prediction_certainty` (`price_prediction`); values `high`, `medium`, `low`, `none` — analysts may exclude `low`/`none` at discretion; official metrics do not require it
- **Well priced**, **imóvel bem precificado** → listed price within ideal limit (≤ p90 RENT / ≤ p70 SALE) or within CPS bounds



## Tables



### Official — price changes


| You need...                                | Use this table                                                                                                        |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Price change attributes (rent + sale)      | `dw_listing.dim_pricing` (`dp`) — PK `sk_pricing`; filter `is_last_price`, `is_last_price_of_day`, `business_context` |
| Price change facts with suggestion FKs     | `dw_listing.fact_price_changes` (`fpc`) — join `dim_pricing` on `sk_pricing`; grain `sk_house` + `business_context`   |
| Enrich source of truth (all intraday rows) | `datalake_ebdb_pricing.listing_price_change` — **not** `listing_price_changes`                                        |




### Official — CPS suggestions (current predictions)


| You need...                                         | Use this table                                                             |
| --------------------------------------------------- | -------------------------------------------------------------------------- |
| Suggestion attributes (rule, certainty, context)    | `dw_listing.dim_price_suggested` — join via `fpc.sk_price_suggested <> -1` |
| Suggestion facts (bounds, suggested price, windows) | `dw_listing.fact_price_suggested`                                          |
| Enrich source of truth                              | `datalake_ebdb_pricing.house_suggestion_changes`                           |




### Legacy — calculator predictions (historical)


| You need...                      | Use this table                                                                                  |
| -------------------------------- | ----------------------------------------------------------------------------------------------- |
| Calculator prediction attributes | `dw_listing.dim_price_predicted` — **historical only**; join via `fpc.sk_price_predicted <> -1` |
| Calculator prediction facts      | `dw_listing.fact_price_predicted`                                                               |
| Enrich source (ingestion ending) | `datalake_ebdb_pricing.listing_prediction_changes`                                              |




### Calculator predictions (ML worker — clean layer)


| You need...                               | Use this table                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Raw percentiles p10–p90 (Casio/Girafales) | `datalake_pricing_clean.price_prediction` — columns `p10`…`p90`; join CPS via `id_prediction`                       |
| CPS suggested price + bounds              | `dw_listing.fact_price_suggested` — `suggested_price`, `suggested_lower_bound_price`, `suggested_upper_bound_price` |




### Legacy / specialized paths


| You need...                                                     | Use this table                                                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Sale price changes with calculator + ticket segment (legacy DW) | `dw_sale.fact_listing_price_changes` — PK `sk_price_change`; rich percentile columns                    |
| Sale ticket segment dimension                                   | `dw_sale.dim_sale_price_segment` — `High Ticket` / `Low Ticket`                                         |
| Smart Price rent changes (separate from sale fact!)             | `dw_quintoandar.fact_listing_price_changes` + `dw_quintoandar.dim_smart_price`                          |
| Legacy enrich with daily dedup baked in                         | `datalake_ebdb_pricing.rent_listing_price_changes`, `datalake_sale_listings.sale_listing_price_changes` |


**Critical rules:**

- **Casio / Girafales:** RENT = Casio (`casio`, `casio-lite`); SALE = Girafales (`girafales`, `girafales-lite`) — see **Q: source of truth for calculator data** above.
- **Overpriced (binary):** RENT → compare listed price to `**price_prediction.p90`**; SALE →** `**p70`; certainty filter is optional at analyst discretion. Alternative: compare to CPS `**suggested_upper_bound_price`**.
- **Official price changes:** `listing_price_change` (singular) → `dw_listing.dim_pricing` + `fact_price_changes`. Do **not** treat `listing_price_changes` (plural) as source of truth.
- **Official suggestions:** `house_suggestion_changes` → `dim_price_suggested` + `fact_price_suggested`. **Always prioritize** this model for suggestion analytics. `**listing_prediction_changes` is legacy** — historical only; ingestion being discontinued.
- **Calculator predictions:** `datalake_pricing_clean.price_prediction` is reliable for **all** calculator predictions, but still **secondary** to the official suggestion DW model when both apply.
- **Grain:** price changes and suggestions are at `**(sk_house, business_context)`**.** `**sk_house_listing` **is being removed** from official pricing tables — do not build new logic on it.
- **New vs legacy dedup:** on `dw_listing.dim_pricing` / `listing_price_change`, filter `is_last_price_of_day = TRUE` when counting daily changes; legacy tables are already deduped.
- `**is_last_price` scope:** flags are at `(sk_house, business_context)` across all listing versions — a new price on any version updates prior rows.
- `**ts_price_ended` scope:** end timestamp closes the window at house+context level, ignoring listing version boundaries.
- **Two different** `fact_listing_price_changes`**:** `dw_sale.`* vs `dw_quintoandar.`* — different grains; never union blindly.
- **Temporal join for daily snapshots:** `dt >= DATE(ts_price_started) AND dt < COALESCE(DATE(ts_price_ended), DATE '2100-01-01')` plus `is_last_price_of_day`.
- **DataHub CI:** list concrete `schema.table` names only — never wildcards in the Tables section.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** Quality Pub and Quality 4Ws. The bullets below are **component** pricing metrics on `dim_pricing` and related tables.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Quality Pub, Quality 4Ws | [Quality of Supply (Pricing Levers)](../metric_entities/supply_quality_score.md) |

### Component / exploratory metrics

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

Official pricing grain is `**(sk_house, business_context)**`, not listing version. `sk_house_listing` still exists on some tables today but **will be removed** — do not use it in new queries. To relate price to a listing publication window, join `dim_pricing` on `sk_house` and align timestamps with listing tables from `business_entities/house_and_listing.md`.

## Dos and Don'ts

**Do:**

- Always filter `business_context IN ('RENT', 'SALE')` — the same house has parallel histories.
- Use `**dw_listing.dim_pricing` + `fact_price_changes**` fed by `**listing_price_change**` (singular) for official price change analysis.
- Use `**house_suggestion_changes` → `dim_price_suggested` + `fact_price_suggested**` for current CPS suggestions / sugestões de preço — **always prioritize** over other prediction sources for DW analytics.
- Use `**datalake_pricing_clean.price_prediction**` when you need **all** calculator predictions or raw ML worker output — reliable, but secondary to the official suggestion model when the question fits suggestion scope.
- Join on `**sk_house` + `business_context**` — the official pricing grain.
- Filter `is_last_price_of_day = TRUE` when counting daily price changes.
- Filter `is_last_price = TRUE` for current price questions.
- Route **“preço do anúncio”** / **listing price** questions to **`dim_pricing` + `fact_price_changes`** for both RENT and SALE.
- Use `listing_prediction_changes` / `dim_price_predicted` **only for historical** calculator analysis.
- Use temporal range joins (`ts_price_started` / `ts_price_ended`) when attaching price to daily snapshots.

**Don't:**

- Don't classify a table as **just rent** or **just sale** for the user unless **this document explicitly** states that scope on the table row — e.g. `dw_listing.dim_pricing` = both contexts via `business_context`; `dw_sale.fact_listing_price_changes` = just sale. Do not use **“RENT only” / “SALE only”** for table scope. Schema name alone is not documentation.
- Don't answer **“preço do anúncio”** with **`dim_house_listing.rent`**, **`house_rent`**, or **`dim_listing.price`** — official source is **`dw_listing.dim_pricing` + `fact_price_changes`** (RENT and SALE, current and historical).
- Don't answer **“overpriced?”** without stating the rule — use **p90 (RENT) / p70 (SALE)** vs `dim_pricing.price`, or CPS upper bound; certainty exclusion is optional and not used in official metrics.
- Don't defer **certainty values** to `safe_fields` — use `high`, `medium`, `low`, `none` on `suggestion_certainty` / `prediction_certainty`.
- Don't answer **“preço recomendado / sugerido”** with `**price_prediction.p70` or `p90`** — use `**fact_price_suggested.suggested_price`** (CPS).
- Don't use `**datalake_emlio_clean.casio**` for pricing analytics — it logs ML model inputs, not calculator/suggestion output.
- Don't hedge on Casio/Girafales scope — Casio = RENT, Girafales = SALE (see glossary and `pricing` DAG documentation).
- Don't use `**listing_price_changes**` (plural) as source of truth — the official enrich is `**listing_price_change**` (singular).
- Don't use `**listing_prediction_changes**` for new prediction/suggestion work — use `**house_suggestion_changes**` / official suggestion DW instead.
- Don't default to `**price_prediction**` when `**dim_price_suggested` / `fact_price_suggested**` covers the analytical need — the DW suggestion model is the priority.
- Don't build new logic on `**sk_house_listing**` in pricing tables — it is being removed.
- Don't count raw rows from `listing_price_change` without `is_last_price_of_day` — intraday changes inflate counts.
- Don't union `dw_sale.fact_listing_price_changes` with `dw_quintoandar.fact_listing_price_changes` — different schemas and grains.
- Don't assume `change_number` resets per listing version — it increments at `(sk_house, business_context)`.
- Don't mix official `dw_listing.*` with legacy enrich tables in the same metric without aligning dedup rules.



## Golden Queries



### Query 1 — Current price per house (rent and sale)

```sql
SELECT
    fpc.sk_house,
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
    fpc.sk_house,
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
    fpc.sk_house,
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
    fpc.sk_house,
    dp.price AS listed_price,
    pp.p90 AS reference_p90,
    pp.prediction_certainty,
    dp.price > pp.p90 AS is_overpriced
FROM dw_listing.dim_pricing AS dp
INNER JOIN dw_listing.fact_price_changes AS fpc
    ON dp.sk_pricing = fpc.sk_pricing
INNER JOIN datalake_pricing_clean.price_prediction AS pp
    ON fpc.sk_house = pp.id_house
   AND dp.business_context = pp.business_context
WHERE dp.is_last_price = TRUE
  AND dp.business_context = 'RENT'
  AND dp.price > pp.p90
-- dedupe to latest prediction per house+context in production queries
```



## Maria (Pricing AI)

WhatsApp agent (**Maria**) that negotiates listing price reductions with property owners on published inventory. Sessions live in `**datalake_copilot_service_clean`** with `channel = 'WHATSAPP_PRICING_AI_CHAT'` — not `datalake_chatbot.sessions.bot`. Conversation outcome labels (`interaction_state`) come from `**datalake_cdp_clean.comms`** (`event_name = 'pricing_conversation_state_classified'`), produced daily by the QuintoML pricing-state-tracker job.

**Metric grain:** count **properties** (`id_house`), not users or sessions, unless the question is explicitly about session-level behaviour (e.g. messages per conversation).

**Analysis windows:** ending **D-1** (`DATE(ts) < CURRENT_DATE`) because lake tables lag same-day updates.

### Related documentation

- Price changes and CPS suggestions — sections above in this file (`dw_listing.dim_pricing`, `fact_price_changes`, `fact_price_suggested`)
- Published inventory denominators — `metric_entities/ongoing_listings.md`
- Listing keys and publication status — `business_entities/house_and_listing.md`
- LLM eval host — `business_entities/evals.md` (`eval_host = 'maria'`)



### Glossary and Synonyms

- **Maria**, **MarIA**, **Pricing AI** → WhatsApp pricing agent; filter `message.channel = 'WHATSAPP_PRICING_AI_CHAT'`
- **HSM**, **template**, **ruleId** → proactive WhatsApp template id in `state.state` JSON (`$.ruleId`); opening message has `message_index = 0` and `role = 'HARDCODED'`
- **first contact about pricing**, **HSM pricing first dispatch** , **pricing first HSM**, **pricing first message** → first proactive HSM to a house using a **first-contact** `ruleId` (not FUP); for cohort metrics take **first dispatch per** `id_house` (`ROW_NUMBER() … ORDER BY ts_created`)
- **FUP**, **follow-up** → recontact templates (`OwnerPriceReductionNoResponseRecontact`, `OwnerPriceReductionNewSuggestionRecontact`, `OwnerPriceReductionAbandonmentRecontact`, …); separate population from first contact
- **Taxa de resposta** → share of created sessions (contacted houses) where the session has **any** human message (`BOOL_OR(role = 'HUMAN')` or `EXISTS`)
- **Conversão na conversa** , **Redução de preço na conversa** → session CDP `interaction_state = 'ACCEPTED_SUGGESTION'`  (do not consider `ACCEPTED_BUT_NOT_CONFIRMED_REDUCTION` by default, just if it is needed)
- **Abandono** → session CDP state in `ABANDONED_AFTER_FIRST_SUGGESTION`, `ABANDONED_AFTER_DEAL_OBJECTIVE`, `ABANDONED_AFTER_REJECT_SUGGESTION` 
- **L2Red** → number of contacted listings that have the current price (in the period) lower than the pre-contact price, considering the cohort of N days after a **reference date** (default: first-session `ts_created` / dispatch; may instead be publication date — see Critical rules / Maria Query 5) (from `dw_listing.fact_price_changes` + `dim_pricing`, `business_context` filtered)
- **Avg Red** → average percent reduction among L2Red houses
- **L2WP**, **well priced** → **rate** = WP houses / L houses (cohort). WP = listed price at checkpoint ≤ CPS reference bound (`**suggested_upper_bound_price` = p70**, `**upper_bound_limit` = p90** on `fact_price_suggested`). Default bound timing = pre-contact; adaptable (checkpoint-aligned or D-1 current) — see Maria Query 6
- **Share vs OL** → contacted houses in period ÷ Ongoing Listings stock on the **last day of the same period** (dispatch window must match the OL snapshot window)
- **Share vs published** → contacted houses ÷ listings that were ongoing **and** had `ts_first_publication` or `ts_last_publication` inside the analysis month (join `dim_listing` for publication timestamps)
- **L2Unp** → listing unpublished within N days after dispatch (`dw_sale.fact_listing_status` / `dw_rent.fact_house_listing_status`, `status_history = 'UNPUBLISHED'`)
- **1P / 3P** → from opening HSM `ruleId`: if `json_extract_scalar(st.state, '$.ruleId')` matches `%3P%` (e.g. `REGEXP_LIKE(..., '3p', 'i')` in Trino) → **3P**; else **1P**
- **FS / FR** → `business_context` `SALE` / `RENT`



### HSM templates (`ruleId`)

Values observed in Maria WhatsApp sessions (from squad SQL + Owner XP weekly dashboard). Extract `json_extract_scalar(st.state, '$.ruleId')` on `message_index = 0`, `role = 'HARDCODED'`.

**Do not treat this table as a fixed allowlist** — new HSM templates can be introduced at any time. When scoping sessions or building cohorts, discover `ruleId` values from data in the analysis window (or use pattern filters such as FUP vs 1º contato) rather than hardcoding only the rows below.


| `ruleId`                                      | Type       | Segment                                                                      |
| --------------------------------------------- | ---------- | ---------------------------------------------------------------------------- |
| `OwnerPriceReductionProposalForSale`          | 1º contato | FS 1P (legacy template)                                                      |
| `OwnerPriceReductionProposalForSaleV2`        | 1º contato | FS 1P                                                                        |
| `OwnerPriceReductionProposalForSale3p`        | 1º contato | FS 3P                                                                        |
| `OwnerPriceReductionProposalUp15dForRent`     | 1º contato | FR 1P (published ≤ 15 days)                                                  |
| `OwnerPriceReductionProposalMore15dForRent`   | 1º contato | FR 1P (published > 15 days)                                                  |
| `OwnerPriceReductionProposalUp15dForRent3p`   | 1º contato | FR 3P (≤ 15 days)                                                            |
| `OwnerPriceReductionProposalMore15dForRent3p` | 1º contato | FR 3P (> 15 days)                                                            |
| `OwnerPriceReductionProposalRelistingForRent` | 1º contato | FR relisting                                                                 |
| `OwnerPriceReductionNoResponseRecontact`      | FUP        | No response                                                                  |
| `OwnerPriceReductionAbandonmentRecontact`     | FUP        | Abandonment                                                                  |
| `OwnerPriceAbandonmentFupForSale`             | FUP        | Sale abandonment                                                             |
| `OwnerPriceAskToTalkLaterFupForSale`          | FUP        | Talk later (sale)                                                            |
| `OwnerPriceNewSuggestionFupForSale`           | FUP        | New suggestion (sale)                                                        |
| `OwnerPriceReductionNewSuggestionRecontact`   | FUP        | New suggestion recontact                                                     |
| `OwnerPostPublishingOnboardingMaria`          | Onboarding | Post-publishing onboarding — often **excluded** from reduction/FUP analytics |


To list all `ruleId` values in a window (including new templates), aggregate HARDCODED opens: see Maria Query 7 (daily) or group with a 30-day filter on `message.ts_created`.

Segment filters: 

- **FS 1P** : businessContext = SALE && ruleId not like `%3p%`; 
- **FS 3P** : businessContext = SALE && ruleId like `%3p%`; 
- **FR 1P** : businessContext = RENT && ruleId not like `%3p%` (non-relisting rules); 
- **FR 3P** : businessContext = RENT && ruleId like `%3p%`; 
- **FR Relisting** : ruleId = `OwnerPriceReductionProposalRelistingForRent`.



### Interaction states (CDP)

Source: `datalake_cdp_clean.comms` where `event_name = 'pricing_conversation_state_classified'`. Use **latest** state per session: `MAX_BY(interaction_state, state_date)`.


| State                                                                                                     | Typical use                        |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `ACCEPTED_SUGGESTION`                                                                                     | **Conversion** (1º contato)        |
| `ABANDONED_AFTER_FIRST_SUGGESTION`, `ABANDONED_AFTER_DEAL_OBJECTIVE`, `ABANDONED_AFTER_REJECT_SUGGESTION` | **Abandonment** rate               |
| `NO_ANSWER`                                                                                               | No response (eligibility cooldown) |
| `REFUSED_TO_TALK`, `REJECT_SUGGESTION_AFTER_NEGOTIATION`, …                                               | Refusal / resistance               |
| `CANT_TALK_NOW_FIRST_CONTACT`, `CANT_TALK_NOW_RESCHEDULE`, …                                              | Talk later / FUP scheduling        |


Full classifier list is defined in QuintoML `pricing-state-tracker` (`NO_ANSWER`, `USER_UPSET`, `BOT_PROBLEM`, `OTHER`, …). Do **not** use `datalake_pricing_agent.interaction_state_tracker` or Langfuse `PricingStateClassification` scores for Maria analytics — CDP is the source of truth.

CDP properties also carry `hsm_count` and `hsm_detailed_count` (per-template counts) for FUP eligibility logic.

### Tables (Maria)


| You need...                                                             | Use this table                                                                                                                                                             |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Messages, channel, roles                                                | `datalake_copilot_service_clean.message` — filter `channel = 'WHATSAPP_PRICING_AI_CHAT'`                                                                                   |
| Session user + Langfuse external id                                     | `datalake_copilot_service_clean.session`                                                                                                                                   |
| HSM metadata (`ruleId`, `houseId`, `businessContext`, `houseOwnership`) | `datalake_copilot_service_clean.state` — join `state.id_message = message.id`; **metadata exists only on the opening HSM row** (`message_index = 0`, `role = 'HARDCODED'`) |
| Interaction state, FUP counts                                           | `datalake_cdp_clean.comms` — `event_name = 'pricing_conversation_state_classified'`                                                                                        |
| Price at dispatch / L2Red                                               | `dw_listing.fact_price_changes`, `dw_listing.dim_pricing`                                                                                                                  |
| p70/p90 reference bounds (L2WP)                                         | `dw_listing.fact_price_suggested`, `dw_listing.dim_price_suggested` — `suggested_upper_bound_price` (p70), `upper_bound_limit` (p90)                                       |
| Sale unpublish                                                          | `dw_sale.fact_listing_status` — `sk_sale_listing / 1000 = id_house`                                                                                                        |
| Rent unpublish                                                          | `dw_rent.fact_house_listing_status` — `sk_house_listing / 1000 = id_house`                                                                                                 |
| Ongoing published stock (share denominators)                            | RENT: validated SQL in `ongoing_listings.md`; SALE: `dw_sale.fact_daily_ongoing_listing`                                                                                   |
| Eligibility cohorts (published, visits, offers)                         | `datalake_ebdb_clean.listing_business_context`, `house`, `visit`; sale offers via `datalake_sales_flow_clean`                                                              |
| Tool outcomes (price edition, unpublish, suspension via bot)            | `datalake_langfuse_clean.traces` + `observations` — `name = tool_name ('unpublish_listing_v1', 'suspend_listing_v1', 'price_edit_v1', etc.`                                |




### Critical rules (Maria)

- **HSM metadata grain:** `id_house`, `ruleId`, `businessContext`, and related fields come from the **HSM configuration** and are recorded only on the **opening message** of each session (`message_index = 0`, `role = 'HARDCODED'`). Later messages in the same session do not carry this metadata in `state`.
- **Query pattern:** for full-conversation analysis, build a `**session_metadata` CTE** from opening HSM rows (filter `message_index = 0` or `role = 'HARDCODED'`, join `state` on `id_message`), then join all other messages or session-level facts to that CTE on `**id_session`** — do not join `state` on every message expecting house/template context.
- **Channel:** `WHATSAPP_PRICING_AI_CHAT` on copilot `message` / `session` — not chatbot `sessions.bot`.
- **Interaction state:** CDP `pricing_conversation_state_classified` only; join on `CAST(json_extract_scalar(event_properties, '$.id_session') AS BIGINT) = message.id_session`.
- **Grain:** default metrics on `**COUNT(DISTINCT id_house)`** after first-dispatch dedup; align price/status joins on `id_house` + `business_context`.
- **1º contato cohort:** first HSM per `id_house` among first-contact `ruleId` values; exclude FUP-only opens unless the question is about FUP.
- **Response:** `BOOL_OR(m.role = 'HUMAN')` (or equivalent `EXISTS`) — never `message_index > 0`.
- **Conversion:** `interaction_state = 'ACCEPTED_SUGGESTION'` only.
- **L2WP reference** from `fact_price_suggested` (bound column by segment):
  - FS 1P / FS 3P → compare to `**suggested_upper_bound_price**` (p70)
  - FR 3P / FR 1P / FR Relisting → `**upper_bound_limit**` (p90)
  - **Bound timing (default):** last suggestion with `ts_suggestion_started` **before** the cohort reference date (pre-contact). **Adaptable:** (a) bound as-of the same checkpoint as the price (d+2, d+30, …); (b) current bound (`CURRENT_DATE - INTERVAL '1' DAY`). Swap only the `FILTER` / as-of predicate on `fact_price_suggested` — keep the rate formula (WP / L).
- **Cohort reference date (L2Red / L2WP / L2Unp):** default anchor is the **event** timestamp (first Maria session `ts_created` / dispatch). The same N-day windows (2d, 30d, …) can instead be anchored on **publication** (`ts_first_publication` / `ts_last_publication`) or another event the user names — adapt **only** the reference-date parameter (`ts_created` → publication/other); keep price/bound join logic.
- **L2WP is a rate:** numerator = distinct houses well-priced at checkpoint; denominator = `COUNT(DISTINCT id_house)` in the cohort (L). Never report only the WP count as “L2WP”.
- **Time filter:** `DATE(ts_created) >= CURRENT_DATE - INTERVAL '30' DAY AND DATE(ts_created) < CURRENT_DATE` for “last month” rolling windows; for calendar months, use `[month_start, month_end]` inclusive and align OL/published denominators to the same bounds.
- **Share vs OL:** numerator = distinct `id_house` contacted (dispatches) **inside the same period** as the OL snapshot; denominator = Ongoing Listings on the **last day of that period** (see `ongoing_listings.md`). Do not mix a rolling 30d dispatch window with a D-1 OL stock unless the question asks for that.
- **Share vs published:** denominator = ongoing listings on period-end **whose** `ts_first_publication` **or** `ts_last_publication` falls in the analysis month (`dw_sale.dim_listing` join — those timestamps are **not** on `fact_daily_ongoing_listing`).
- **Overpriced share denominator:** ongoing published listings that are overpriced (binary rule from **Q: overpriced** above, using `fact_price_suggested` bounds or `dim_pricing` vs bounds).



### Eligibility — proactive 1º contato (Hightouch)

Operational eligibility for **who receives** the first Maria HSM is defined in Hightouch models (not identical to analytics cohorts). Common patterns:

**SALE 1P (standard):** single listing, ≤ 5 houses per owner, `PUBLISHED`, first publication between 15–180 days ago, low visits (≤ 1 in 30d), no active sale offers, listed price > `suggested_upper_bound_price` × 1.01 (overpriced vs CPS p70 bound), CDP cooldowns on prior FUP states and `hsm_detailed_count` caps, no HSM in last 48h.

**RENT 1P (standard):** `PUBLISHED`, `ownership = STANDARD`, first publication **3–21 days** ago, not PP Multi (no `user_pro_owner` before publication, `< 5` houses owned at publication date via `daily_owner_houses_quantity_history`, `is_pp_multi_active = FALSE` on D-1), exclude owner `id_user = 1228147`, no active rent offers (`datalake_rental_transact_clean.offer`, `status = 'PROPOSED'`), listed rent **>** `upper_bound_limit` (p90 bound on `house_price_suggestion` / `fact_price_suggested`), no prior RENT Maria 1º contato HSM for the house, not allocated in ASP opportunities (`asp_opportunities_distribution`), not in experiment holdout (`maria_for_rent_experiment_group_defined` where `group <> 'maria'`), CDP cooldowns on prior abandonment (15d: `ABANDONED_AFTER_FIRST_SUGGESTION`, `ABANDONED_AFTER_DEAL_OBJECTIVE`, `REFUSED_TO_TALK`, `DID_NOT_TALK_ABOUT_PRICE`), no-response (9d: `NO_ANSWER`, `CANT_TALK_NOW_FIRST_CONTACT`, `CANT_TALK_NOW_DEAL_OBJECTIVE`), and rejection (33d: `ABANDONED_AFTER_REJECT_SUGGESTION`, `REJECT_SUGGESTION_AFTER_NEGOTIATION`, `ASKED_TO_CONFIRM_LATER_AFTER_SUGGESTION`) with `hsm_detailed_count` caps, no HSM in last 48h, access authorization in (`KEYSWITHAGENT`, `FRONTDOOR`, `LOCKBOX`, `PASSWORD`, `KEYSLOCKER`), **one house per owner** (earliest `ts_first_publication`).

For exact filters, mirror the Hightouch SQL (`maria_1p_sale_first_message_elegibility`, `maria_1p_rent_first_message_elegilibity`) — eligibility changes with product rules.

### Key metrics (Maria)

- Houses contacted (1º contato), by `ruleId` / segment / `business_context`
- Share contacted vs OL (same period window) and vs published-in-month
- Response rate, abandonment rate, conversion rate (1º contato, house grain)
- L2Red and Avg Red at 2d / 30d after cohort reference date (default: dispatch)
- L2WP **rate** at 2d / 30d after cohort reference date
- L2Unp at 2d after cohort reference date
- FUP volume by template (`hsm_detailed_count` or copilot opens with FUP `ruleId`)
- Daily volume (“conversas ontem” = `DATE(ts_created) = CURRENT_DATE - INTERVAL '1' DAY`) with full conversation text
- User-initiated conversations (`message_index = 0`, `role = 'USER'`)



### Dos and Don'ts (Maria)

**Do:**

- Build a `**session_metadata` CTE** from opening HSM rows (`message_index = 0` / `role = 'HARDCODED'` + `state`) before joining the rest of the conversation on `id_session`.
- Filter `channel = 'WHATSAPP_PRICING_AI_CHAT'` and read `ruleId` / house fields from that opening row only.
- Use CDP for `interaction_state`, `state tracker`, abandonment and conversation success (price edition , price reduction).
- Use ruleId for FUP identification.
- Dedupe to **first dispatch per** `id_house` for 1º contato performance metrics.
- Use `**fact_price_suggested**` for L2WP reference bounds (`suggested_upper_bound_price` / `upper_bound_limit`).
- Report **L2WP as a rate** (`WP / COUNT(DISTINCT id_house)`), not only the WP count.
- Align Maria dispatch window with the OL / published denominator window when computing shares (same `period_start` / `period_end`).
- End date filters at **D-1** (`< CURRENT_DATE`) for rolling windows.
- State segment (`FS 1P`, `FR 3P`, …) explicitly when reporting template mix.

**Don't:**

- Don't join `state` on every message in a session — metadata is on the opening HSM only.
- Don't use `datalake_chatbot.sessions` or `bot = 'maria'` for Maria WhatsApp pricing analytics.
- Don't use `datalake_pricing_agent.interaction_state_tracker` or Langfuse `PricingStateClassification` for interaction state.
- Don't identify FUP via CDP state / message order
- Don't use `message_index > 0` as the response definition.
- Don't count `ACCEPTED_BUT_NOT_CONFIRMED_REDUCTION` as conversion by default, just if requested.
- Don't use `price_prediction.p70`/`p90` when `fact_price_suggested` bounds are available for L2WP.
- Don't mix a dispatch period with an OL snapshot from a different day when answering share vs OL.
- Don't treat `fact_daily_ongoing_listing` as having `ts_first_publication` / `ts_last_publication` — join `dw_sale.dim_listing`.
- Don't aggregate KPIs by `id_user` when the squad metric is per property or per session.



### Golden Queries (Maria)



#### Maria Query 0 — Session metadata CTE (base pattern for full-conversation analysis)

```sql
WITH session_metadata AS (
    SELECT
        m.id_session,
        m.ts_created AS ts_open,
        CAST(json_extract_scalar(st.state, '$.payload.metadata.houseId') AS BIGINT) AS id_house,
        json_extract_scalar(st.state, '$.payload.metadata.businessContext') AS business_context,
        json_extract_scalar(st.state, '$.ruleId') AS rule_id
    FROM datalake_copilot_service_clean.message AS m
    INNER JOIN datalake_copilot_service_clean.state AS st
        ON st.id_message = m.id
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'HARDCODED'
)
-- Join conversation messages or CDP/Langfuse facts to session_metadata ON id_session
SELECT *
FROM session_metadata
```



#### Maria Query 1 — First dispatch per house (1º contato cohort)

```sql
WITH first_contact_rules AS (
    SELECT rule_id
    FROM (
        VALUES -- Confirm if it's necessary to add new templates
            ('OwnerPriceReductionProposalForSale'),
            ('OwnerPriceReductionProposalForSaleV2'),
            ('OwnerPriceReductionProposalForSale3p'),
            ('OwnerPriceReductionProposalUp15dForRent'),
            ('OwnerPriceReductionProposalMore15dForRent'),
            ('OwnerPriceReductionProposalUp15dForRent3p'),
            ('OwnerPriceReductionProposalMore15dForRent3p'),
            ('OwnerPriceReductionProposalRelistingForRent')
    ) AS t(rule_id)
),
opens AS (
    SELECT
        m.id_session,
        m.ts_created,
        CAST(json_extract_scalar(st.state, '$.payload.metadata.houseId') AS BIGINT) AS id_house,
        json_extract_scalar(st.state, '$.payload.metadata.businessContext') AS business_context,
        json_extract_scalar(st.state, '$.ruleId') AS rule_id
    FROM datalake_copilot_service_clean.message AS m
    INNER JOIN datalake_copilot_service_clean.state AS st
        ON st.id_message = m.id
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'HARDCODED'
      AND DATE(m.ts_created) >= CURRENT_DATE - INTERVAL '30' DAY
      AND DATE(m.ts_created) < CURRENT_DATE
      AND json_extract_scalar(st.state, '$.ruleId') IN (SELECT rule_id FROM first_contact_rules)
),
first_dispatch AS (
    SELECT *
    FROM opens
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_created ASC) = 1
)
SELECT *
FROM first_dispatch
```



#### Maria Query 2 — Volumetria no período + share vs OL (house grain)

```sql
-- Dispatch window MUST match the Ongoing Listings (OL) snapshot window.
-- Example: analysing June OL → count Maria first dispatches in June,
-- denominator = OL stock on the last day of June.
WITH params AS (
    SELECT
        DATE '2025-06-01' AS period_start,
        DATE '2025-06-30' AS period_end  -- last calendar day of the analysis month
),
first_contact_rules AS (
    SELECT rule_id
    FROM (
        VALUES
            ('OwnerPriceReductionProposalForSale'),
            ('OwnerPriceReductionProposalForSaleV2'),
            ('OwnerPriceReductionProposalForSale3p'),
            ('OwnerPriceReductionProposalUp15dForRent'),
            ('OwnerPriceReductionProposalMore15dForRent'),
            ('OwnerPriceReductionProposalUp15dForRent3p'),
            ('OwnerPriceReductionProposalMore15dForRent3p'),
            ('OwnerPriceReductionProposalRelistingForRent')
    ) AS t(rule_id)
),
opens AS (
    SELECT
        m.id_session,
        m.ts_created,
        CAST(json_extract_scalar(st.state, '$.payload.metadata.houseId') AS BIGINT) AS id_house,
        json_extract_scalar(st.state, '$.payload.metadata.businessContext') AS business_context,
        json_extract_scalar(st.state, '$.ruleId') AS rule_id
    FROM datalake_copilot_service_clean.message AS m
    INNER JOIN datalake_copilot_service_clean.state AS st
        ON st.id_message = m.id
    CROSS JOIN params AS p
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'HARDCODED'
      AND DATE(m.ts_created) BETWEEN p.period_start AND p.period_end
      AND json_extract_scalar(st.state, '$.ruleId') IN (SELECT rule_id FROM first_contact_rules)
),
first_dispatch AS (
    SELECT *
    FROM opens
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_created ASC) = 1
),
sale_ol AS (
    SELECT COUNT(DISTINCT sk_sale_listing) AS ongoing_listings
    FROM dw_sale.fact_daily_ongoing_listing
    CROSS JOIN params AS p
    WHERE MAKE_DATE(year, month, day) = p.period_end
)
SELECT
    fd.business_context,
    COUNT(DISTINCT fd.id_house) AS houses_contacted,
    so.ongoing_listings,
    CAST(COUNT(DISTINCT fd.id_house) AS DOUBLE)
        / NULLIF(so.ongoing_listings, 0) AS share_vs_ol
FROM first_dispatch AS fd
CROSS JOIN sale_ol AS so
WHERE fd.business_context = 'SALE'
GROUP BY fd.business_context, so.ongoing_listings
-- RENT denominator: validated ongoing SQL in metric_entities/ongoing_listings.md
-- (same period_end snapshot day as SALE)
```



#### Maria Query 3 — Volumetria no período + share vs published (house grain)

```sql
-- Same dispatch window as Query 2. Denominator = ongoing listings on period_end
-- that had first OR last publication inside the analysis month.
-- ts_first_publication / ts_last_publication live on dw_sale.dim_listing (not on fact_daily_ongoing_listing).
WITH params AS (
    SELECT
        DATE '2025-06-01' AS period_start,
        DATE '2025-06-30' AS period_end
),
-- Reuse first_contact_rules + opens + first_dispatch from Maria Query 2 (same period bounds), then:
sale_published AS (
    SELECT COUNT(DISTINCT fdol.sk_sale_listing) AS published_in_period
    FROM dw_sale.fact_daily_ongoing_listing AS fdol
    INNER JOIN dw_sale.dim_listing AS dl
        ON dl.sk_sale_listing = fdol.sk_sale_listing
    CROSS JOIN params AS p
    WHERE MAKE_DATE(fdol.year, fdol.month, fdol.day) = p.period_end
      AND (
            DATE(dl.ts_first_publication) BETWEEN p.period_start AND p.period_end
         OR DATE(dl.ts_last_publication) BETWEEN p.period_start AND p.period_end
      )
)
SELECT
    fd.business_context,
    COUNT(DISTINCT fd.id_house) AS houses_contacted,
    sp.published_in_period,
    CAST(COUNT(DISTINCT fd.id_house) AS DOUBLE)
        / NULLIF(sp.published_in_period, 0) AS share_vs_published
FROM first_dispatch AS fd
CROSS JOIN sale_published AS sp
WHERE fd.business_context = 'SALE'
GROUP BY fd.business_context, sp.published_in_period
```



#### Maria Query 4 — Response, abandonment, conversion (1º contato, CDP)

```sql
WITH first_contact_rules AS (
    SELECT rule_id
    FROM (
        VALUES
            ('OwnerPriceReductionProposalForSale'),
            ('OwnerPriceReductionProposalForSaleV2'),
            ('OwnerPriceReductionProposalForSale3p'),
            ('OwnerPriceReductionProposalUp15dForRent'),
            ('OwnerPriceReductionProposalMore15dForRent'),
            ('OwnerPriceReductionProposalUp15dForRent3p'),
            ('OwnerPriceReductionProposalMore15dForRent3p'),
            ('OwnerPriceReductionProposalRelistingForRent')
    ) AS t(rule_id)
),
opens AS (
    SELECT
        m.id_session,
        m.ts_created,
        CAST(json_extract_scalar(st.state, '$.payload.metadata.houseId') AS BIGINT) AS id_house
    FROM datalake_copilot_service_clean.message AS m
    INNER JOIN datalake_copilot_service_clean.state AS st
        ON st.id_message = m.id
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'HARDCODED'
      AND DATE(m.ts_created) >= CURRENT_DATE - INTERVAL '30' DAY
      AND DATE(m.ts_created) < CURRENT_DATE
      AND json_extract_scalar(st.state, '$.ruleId') IN (SELECT rule_id FROM first_contact_rules)
),
first_dispatch AS (
    SELECT *
    FROM opens
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_created ASC) = 1
),
human_response AS (
    SELECT
        fd.id_session,
        BOOL_OR(m.role = 'HUMAN') AS has_human_response
    FROM first_dispatch AS fd
    INNER JOIN datalake_copilot_service_clean.message AS m
        ON m.id_session = fd.id_session
    GROUP BY fd.id_session
),
cdp_state AS (
    SELECT
        CAST(json_extract_scalar(cdp.event_properties, '$.id_session') AS BIGINT) AS id_session,
        MAX_BY(
            json_extract_scalar(cdp.event_properties, '$.interaction_state'),
            CAST(json_extract_scalar(cdp.event_properties, '$.state_date') AS DATE)
        ) AS interaction_state
    FROM datalake_cdp_clean.comms AS cdp
    WHERE cdp.event_name = 'pricing_conversation_state_classified'
    GROUP BY 1
),
enriched AS (
    SELECT
        fd.id_house,
        fd.id_session,
        hr.has_human_response,
        cs.interaction_state
    FROM first_dispatch AS fd
    LEFT JOIN human_response AS hr ON fd.id_session = hr.id_session
    LEFT JOIN cdp_state AS cs ON fd.id_session = cs.id_session
)
SELECT
    COUNT(DISTINCT id_house) AS houses_contacted,
    COUNT(DISTINCT id_house) FILTER (WHERE has_human_response) AS houses_with_response,
    COUNT(DISTINCT id_house) FILTER (
        WHERE interaction_state IN (
            'ABANDONED_AFTER_FIRST_SUGGESTION',
            'ABANDONED_AFTER_DEAL_OBJECTIVE',
            'ABANDONED_AFTER_REJECT_SUGGESTION'
        )
    ) AS houses_abandoned,
    COUNT(DISTINCT id_house) FILTER (
        WHERE interaction_state = 'ACCEPTED_SUGGESTION'
    ) AS houses_converted
FROM enriched
```



#### Maria Query 5 — L2Red / Avg Red (2d and 30d, house grain)

**Cohort reference date (adapt when asked):** the 2d / 30d windows are offsets from a single anchor timestamp. **Default** = first Maria session / dispatch (`fd.ts_created`). The same pattern works with **publication date** (`ts_first_publication` / `ts_last_publication`) or another named event — replace `fd.ts_created` (and the pre-contact / checkpoint filters that depend on it) with that anchor. Do not invent a different cohort definition; change **only** the reference-date parameter.

```sql
-- Requires first_dispatch CTE (Maria Query 1 or 4) in the same statement.
-- Anchor alias: ts_ref = fd.ts_created  -- swap to publication / other event when requested
WITH price_at_dispatch AS (
    SELECT
        fd.id_house,
        fd.business_context,
        MAX_BY(dp.price, fpc.ts_price_started) FILTER (
            WHERE fpc.ts_price_started < fd.ts_created
        ) AS price_pre_contact,
        MAX_BY(dp.price, fpc.ts_price_started) FILTER (
            WHERE fpc.ts_price_started <= fd.ts_created + INTERVAL '2' DAY
        ) AS price_2d,
        MAX_BY(dp.price, fpc.ts_price_started) FILTER (
            WHERE fpc.ts_price_started <= fd.ts_created + INTERVAL '30' DAY
        ) AS price_30d
    FROM first_dispatch AS fd
    INNER JOIN dw_listing.fact_price_changes AS fpc
        ON fpc.sk_house = fd.id_house
    INNER JOIN dw_listing.dim_pricing AS dp
        ON dp.sk_pricing = fpc.sk_pricing
       AND dp.business_context = fd.business_context
    GROUP BY fd.id_house, fd.business_context
)
SELECT
    COUNT(DISTINCT id_house) FILTER (WHERE price_2d < price_pre_contact) AS l2red_2d_houses,
    AVG(
        (price_pre_contact - price_2d) / NULLIF(price_pre_contact, 0)
    ) FILTER (WHERE price_2d < price_pre_contact) AS avg_red_2d,
    COUNT(DISTINCT id_house) FILTER (WHERE price_30d < price_pre_contact) AS l2red_30d_houses,
    AVG(
        (price_pre_contact - price_30d) / NULLIF(price_pre_contact, 0)
    ) FILTER (WHERE price_30d < price_pre_contact) AS avg_red_30d
FROM price_at_dispatch
```



#### Maria Query 6 — L2WP (CPS bounds: p70 = suggested_upper_bound_price, p90 = upper_bound_limit)

**L2WP is a rate:** `WP / L` where L = `COUNT(DISTINCT id_house)` in the cohort and WP = houses with listed price ≤ reference bound at the checkpoint.

**Bound timing (adapt when asked):**

- **Default:** p70/p90 (CPS bounds) as-of **pre-contact** — last suggestion with `ts_suggestion_started < ts_ref`
- **(a) Checkpoint-aligned:** bound as-of the same moment as the price checkpoint (e.g. `ts_suggestion_started <= ts_ref + INTERVAL '2' DAY` for d+2)
- **(b) Current:** bound as of `CURRENT_DATE - INTERVAL '1' DAY` (`is_last_suggestion = TRUE` or max suggestion started on D-1)

Swap only the `FILTER` / as-of predicate on `fact_price_suggested`; keep segment → column mapping and the rate formula.

```sql
-- Combine first_dispatch + price_at_dispatch (Query 5) with CPS bounds.
-- Reference bound by segment:
--   SALE (1P/3P) → suggested_upper_bound_price (p70)
--   RENT (1P, 3P, Relisting) → upper_bound_limit (p90)
WITH bounds_pre AS (
    SELECT
        fd.id_house,
        fd.business_context,
        fd.rule_id,
        -- Default: pre-contact. Adapt FILTER for (a) checkpoint or (b) current.
        MAX_BY(fps.suggested_upper_bound_price, fps.ts_suggestion_started) FILTER (
            WHERE fps.ts_suggestion_started < fd.ts_created
        ) AS p70_pre,
        MAX_BY(fps.upper_bound_limit, fps.ts_suggestion_started) FILTER (
            WHERE fps.ts_suggestion_started < fd.ts_created
        ) AS p90_pre
    FROM first_dispatch AS fd
    INNER JOIN dw_listing.fact_price_suggested AS fps
        ON fps.sk_house = fd.id_house
    INNER JOIN dw_listing.dim_price_suggested AS dps
        ON dps.sk_price_suggested = fps.sk_price_suggested
       AND dps.business_context = fd.business_context
    GROUP BY fd.id_house, fd.business_context, fd.rule_id
),
with_ref AS (
    SELECT
        bp.id_house,
        pa.price_2d,
        pa.price_30d,
        CASE
            WHEN bp.business_context = 'SALE' THEN bp.p70_pre
            ELSE bp.p90_pre
        END AS ref_bound
    FROM bounds_pre AS bp
    INNER JOIN price_at_dispatch AS pa
        ON pa.id_house = bp.id_house
)
SELECT
    COUNT(DISTINCT id_house) AS cohort_houses,  -- L (denominator)
    COUNT(DISTINCT id_house) FILTER (WHERE price_2d <= ref_bound) AS l2wp_2d_houses,  -- WP
    CAST(COUNT(DISTINCT id_house) FILTER (WHERE price_2d <= ref_bound) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_house), 0) AS l2wp_2d_rate,
    COUNT(DISTINCT id_house) FILTER (WHERE price_30d <= ref_bound) AS l2wp_30d_houses,
    CAST(COUNT(DISTINCT id_house) FILTER (WHERE price_30d <= ref_bound) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT id_house), 0) AS l2wp_30d_rate
FROM with_ref
```



#### Maria Query 7 — Conversas ontem (by segment / ruleId, with conversation text)

```sql
WITH opens AS (
    SELECT
        m.id_session,
        m.ts_created,
        CAST(json_extract_scalar(st.state, '$.payload.metadata.houseId') AS BIGINT) AS id_house,
        json_extract_scalar(st.state, '$.payload.metadata.businessContext') AS business_context,
        json_extract_scalar(st.state, '$.ruleId') AS rule_id
    FROM datalake_copilot_service_clean.message AS m
    INNER JOIN datalake_copilot_service_clean.state AS st
        ON st.id_message = m.id
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'HARDCODED'
      AND DATE(m.ts_created) = CURRENT_DATE - INTERVAL '1' DAY
),
conversation AS (
    SELECT
        o.id_session,
        o.id_house,
        o.business_context,
        o.rule_id,
        o.ts_created,
        listagg(
            CAST(m.message_index AS VARCHAR) || ' - ' || m.role || ' : ' || COALESCE(m.content, ''),
            CHR(10)
        ) WITHIN GROUP (ORDER BY m.message_index) AS conversation
    FROM opens AS o
    INNER JOIN datalake_copilot_service_clean.message AS m
        ON m.id_session = o.id_session
    GROUP BY o.id_session, o.id_house, o.business_context, o.rule_id, o.ts_created
)
SELECT
    rule_id,
    business_context,
    id_house,
    id_session,
    ts_created,
    conversation
FROM conversation
ORDER BY rule_id, id_session
```



#### Maria Query 8 — Conversas iniciadas pelo user (sem HSM metadata)

```sql
-- Opening row is user-authored: no ruleId / houseId / businessContext on state.
WITH user_opens AS (
    SELECT
        m.id_session,
        m.id_user,
        m.ts_created
    FROM datalake_copilot_service_clean.message AS m
    WHERE m.channel = 'WHATSAPP_PRICING_AI_CHAT'
      AND m.message_index = 0
      AND m.role = 'USER'
      AND DATE(m.ts_created) >= CURRENT_DATE - INTERVAL '30' DAY
      AND DATE(m.ts_created) < CURRENT_DATE
),
conversation AS (
    SELECT
        uo.id_user,
        DATE(uo.ts_created) AS dt_conversation,
        uo.id_session,
        listagg(
            CAST(m.message_index AS VARCHAR) || ' - ' || m.role || ' : ' || COALESCE(m.content, ''),
            CHR(10)
        ) WITHIN GROUP (ORDER BY m.message_index) AS conversation
    FROM user_opens AS uo
    INNER JOIN datalake_copilot_service_clean.message AS m
        ON m.id_session = uo.id_session
    GROUP BY uo.id_user, DATE(uo.ts_created), uo.id_session
)
SELECT
    id_user,
    dt_conversation,
    conversation
FROM conversation
ORDER BY dt_conversation DESC, id_user
```



#### Maria Query 9 — CDP latest state join pattern (reusable)

```sql
SELECT
    CAST(json_extract_scalar(cdp.event_properties, '$.id_session') AS BIGINT) AS id_session,
    CAST(json_extract_scalar(cdp.event_properties, '$.id_house') AS BIGINT) AS id_house,
    json_extract_scalar(cdp.event_properties, '$.business_context') AS business_context,
    json_extract_scalar(cdp.event_properties, '$.interaction_state') AS interaction_state,
    CAST(json_extract_scalar(cdp.event_properties, '$.state_date') AS DATE) AS state_date,
    CAST(json_extract_scalar(cdp.event_properties, '$.hsm_count') AS BIGINT) AS hsm_count
FROM datalake_cdp_clean.comms AS cdp
WHERE cdp.event_name = 'pricing_conversation_state_classified'
  AND CAST(json_extract_scalar(cdp.event_properties, '$.state_date') AS DATE) < CURRENT_DATE
```


