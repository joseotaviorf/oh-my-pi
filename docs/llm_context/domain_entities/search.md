# Search

## Ownership

**Data Steward:**
- pedro.nogueira@quintoandar.com.br

## Overview

Search represents listing discovery sessions where users view search result pages, see ranked listings, click listings, and may later progress to visits, offers, or contracts. Use this entity to answer questions about search volume, result exposure, click-through behavior, ranking position, AB-test variants, and downstream journey attribution after a search impression.

The source of truth for every search metric in this document is `datalake_search.search_impressions`. It stores search identifiers, listing identifiers, dimensions, variants, metrics, and timestamps as JSON payloads plus event date and physical partition columns.

The lifecycle usually follows these stages:
1. **Search rendered** — search page or search results page viewed (`datalake_search.search_impressions.ts_event`)
2. **Listings exposed** — each listing shown in search results is available through `ids.id_house` and ranking dimensions
3. **Interaction measured** — search and click signals are read from `metrics.search` and `metrics.click`
4. **Downstream outcomes attached** — visit, offer, and contract outcomes after the search are read from `metrics` and `timestamps`

Not every search has a click or downstream conversion. Search metrics are at search-result listing impression grain unless a query explicitly collapses to search, user, user-house, or AB-test variant grain.

## Glossary and Synonyms

- **search**, **busca**, **resultado de busca**, **SRP**, **SPV** -> search result experiences tracked in `datalake_search.search_impressions`
- **search impression** -> one listing exposed in one search result; count rows in `datalake_search.search_impressions`
- **search session**, **id_search** -> search identifier from `ids.id_search`; use it to collapse listing impressions into one search
- **listing impression**, **house impression** -> listing/house exposed in search results (`ids.id_house`)
- **click de busca**, **search CTR** -> click-through behavior from `metrics.click`
- **CTR por busca**, **search-level CTR** -> first collapse one row per `ids.id_search` with `MAX(metrics.click)`, then average that click flag
- **CTR por impressao**, **impression-level CTR** -> average `metrics.click` directly at search-result listing impression grain
- **ranking position**, **posicao no resultado** -> result ordering from `dimensions.absolute_position`, `dimensions.page_number`, and `dimensions.page_position`
- **rank model** -> ranking model family from `dimensions.rank_model`, such as `LTR` or `pclick`
- **rendering type**, **SPV/SRPV** -> search page variant from `dimensions.search_rendering_type`
- **contexto de negocio** -> search context from `json_extract_scalar(dimensions, '$.business_context')`, usually `rent` or `sale`
- **usuario outlier** -> high-activity users flagged in `dimensions.is_outlier_user`
- **mercado primario**, **primary market** -> house SALE listing classified as new-build from `dimensions.is_primary_market` (1 when the listing_sale_type SSOT is PRIMARY, else 0). Do not use the legacy `house.is_sale_primary_market` boolean.
- **variant**, **AB test** -> experiment assignment from `variants.<experiment_name>`

## Tables

| You need... | Use this table |
|-------------|----------------|
| Any search metric, including search impressions, CTR, ranking position, AB-test allocation, search-to-click, and downstream outcomes | `datalake_search.search_impressions` (`si`) — processed search-impression base with JSON payloads (`ids`, `dimensions`, `variants`, `metrics`, `timestamps`) and physical partitions (`year`, `month`, `day`) |
| Pre-aggregated search monitoring metrics by dimension and date | `datalake_search.search_metrics` (`sm`) — monitoring table with `metric_name`, numerator, denominator, value, stability flag, and date granularity; use only when the requester explicitly asks for the monitoring metric output |
| User or house global journey metrics derived from search | `datalake_search.global_metrics` (`gm`) — broader global metrics derived from search interactions and house publication events; do not use as the default source for search CTR or ranking analysis |

**Critical rules:**
- Compute search CTR, ranking, listing exposure, AB-test search metrics, and search-attributed conversion from `datalake_search.search_impressions` by default.
- Extract JSON fields explicitly from `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`.
- Use `ids.id_search` to collapse listing impressions into one search. Do not count rows as searches unless the requested grain is listing impression.
- For search CTR requests, state the grain: `ctr_impression`, `ctr_search`, or `ctr_search_house`.
- Keep `json_extract_scalar(dimensions, '$.business_context')` explicit in aggregations. Do not pool rent and sale unless the requester explicitly asks for a combined result.
- Treat `dimensions.is_outlier_user` explicitly, either as a filter or segment, when benchmarking CTR or conversion.
- For AB-test analyses, always define both test start date and test end date in filters before computing allocation or CTR.
- Always filter physical partitions using `year`, `month`, and `day` in the `WHERE` clause. Keep the `date` or `ts_event` filter too, but never rely on it alone.

## AB Test Request Protocol (Mandatory)

When the user asks for AB-test metrics, for example CTR by variant, follow this interaction rule:

- Ask for `business_context` before returning CTR SQL or results. If the user wants both rent and sale, return them as separate rows.
- Ask for both `dt_start` and `dt_end` before running or returning AB-test metrics.
- For every metric request, including CTR and AB-test metrics, `business_context` is required. If the user does not provide one, ask whether to filter to a specific `business_context` or group the result by `business_context`; never return a metric aggregated across business contexts without making that grouping explicit.
- If either date or `business_context` is missing, do not provide the metric value yet; request the missing input first.
- If `dt_end` is missing, do not return the SQL query template yet; ask for `dt_end` first.
- After receiving both dates, apply both explicit event-date filters and physical partition filters (`year`, `month`, `day`) in the AB-test query.
- When adapting AB-test queries for `platform`, `rank_model`, `search_rendering_type`, or another segment, keep the full partition filter block from the base query. Segment filters are additive and must not replace partition predicates.
- Do not use open-ended AB-test windows by default.

Partition filter requirement for `datalake_search.search_impressions`:

```sql
WHERE date >= DATE('{dt_start}')
  AND date <= DATE('{dt_end}')
  AND (year, month, day) >= (
        year(DATE('{dt_start}')),
        month(DATE('{dt_start}')),
        day(DATE('{dt_start}'))
    )
  AND (year, month, day) <= (
        year(DATE('{dt_end}')),
        month(DATE('{dt_end}')),
        day(DATE('{dt_end}'))
    )
```

### AB Test Metric Routing (Source of Truth)

For requests like "search CTR for `<experiment_name>`", always route to search AB-test patterns from this document.

- Primary source for search CTR by variant, user allocation, and ranking-segment search metrics: `datalake_search.search_impressions`.
- Compute variant assignment with `json_extract_scalar(variants, '$.<experiment_name>')`.
- Always state CTR grain in the response (`ctr_search` vs `ctr_impression`).
- Do not answer "search CTR" from `datalake_search.search_metrics` unless the requester explicitly asks for the monitoring table's pre-aggregated metric.

## Key Metrics

- Search listing impressions (`COUNT(*)` on `datalake_search.search_impressions`)
- Searches (`COUNT(DISTINCT ids.id_search)` after extracting from `ids`)
- Users who searched (`COUNT(DISTINCT ids.id_user)` after extracting from `ids`)
- Listings exposed in search (`COUNT(DISTINCT ids.id_house)` after extracting from `ids`)
- Search clicks (`SUM(CAST(metrics.click AS INTEGER))` after extracting from `metrics`)
- Impression-level CTR (`AVG(CAST(metrics.click AS DOUBLE))` at search-result listing impression grain)
- Search-level CTR (`AVG(CAST(search_clicked AS DOUBLE))` after one row per `ids.id_search` with `MAX(metrics.click)`)
- Search-house CTR (`AVG(CAST(search_house_clicked AS DOUBLE))` after one row per `ids.id_search`, `ids.id_house`)
- Average exposed listings per search (`COUNT(*) / COUNT(DISTINCT ids.id_search)`)
- CTR by ranking position (`AVG(CAST(metrics.click AS DOUBLE)) GROUP BY dimensions.absolute_position` or `dimensions.page_position`)
- Search-attributed visit booked rate (`AVG(CAST(metrics.visit_booked AS DOUBLE))` after extracting from `metrics`)
- Search-attributed offer rate (`AVG(CAST(metrics.offer AS DOUBLE))` after extracting from `metrics`)
- Search-attributed contract signed rate (`AVG(CAST(metrics.contract_signed AS DOUBLE))` after extracting from `metrics`)
- CTR by AB-test variant (`AVG(CAST(search_clicked AS DOUBLE))` after one row per search and variant assignment from `variants.<experiment_name>`)

### Metric Grain Conventions

- `ctr_impression`: listing-impression CTR using `metrics.click` on each processed search-result row.
- `ctr_search`: search-level CTR using one row per (`ids.id_search`, `ids.id_user`, `json_extract_scalar(dimensions, '$.business_context')`) and click collapsed with `MAX(metrics.click)`.
- `ctr_search_house`: user-house exposure CTR using one row per (`ids.id_search`, `ids.id_house`) and click collapsed with `MAX(metrics.click)`.
- `users_in_variant`: user-allocation metric (`COUNT(DISTINCT ids.id_user)`) and should not be interpreted as search or impression volume.
- Conversion rates from `metrics.visit_booked`, `metrics.offer`, and `metrics.contract_signed` are row-level processed-impression rates unless first collapsed to search, user, or user-house grain.
- When reporting AB-test results, explicitly state which CTR grain is being used.

## Relationships with Other Entities

### Recs (Parallel discovery surface)

- Search and recs both live in `datalake_search` and expose JSON payloads named `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`.
- Use `search_impressions` for active search-result behavior and ranking questions. Use `recs_impressions_processed` for recommendation carousel exposure questions.
- Common join keys are `ids.id_user`, `ids.id_house`, `dimensions.business_context`, and event timestamps, but avoid joining the two unless the requester defines a user journey window.

### Visits (N:1 via user-house journey keys)

- Use `ids.id_user`, `ids.id_house`, and `json_extract_scalar(dimensions, '$.business_context')` as the journey keys exposed by `datalake_search.search_impressions`.
- For search-attributed visit logic inside this entity, use `metrics.visit_booked`, `timestamps.ts_visit_booked`, and `timestamps.ts_visit_completed`.
- Split by `json_extract_scalar(dimensions, '$.business_context')` before aggregating Visit KPIs.

### Closing (N:1 via contract outcomes)

- Contract outcomes inside this entity are exposed by `metrics.contract_signed` and `timestamps.ts_contract_signed`.
- Keep attribution semantics explicit: "contract signed after search exposure/click" is different from generic signed-contract volume.

### Listings and Houses (N:1 via exposed listing)

- Use `ids.id_house` to connect search-result exposure to house/listing context.
- Search rank and listing age are already available in `dimensions.absolute_position`, `dimensions.page_number`, `dimensions.page_position`, `dimensions.rank_model`, and `dimensions.listing_age`; avoid joining to listing tables just to recompute these fields.
- Primary vs secondary sale market is already on `dimensions.is_primary_market` from `datalake_sale_primary_market.listing_sale_type`; do not join listing_sale_type or use `house.is_sale_primary_market` for search-impression cuts.

## Dos and Don'ts

**Do:**
- Use `datalake_search.search_impressions` for all search CTR, ranking, AB-test, and search-attributed conversion examples.
- Extract JSON keys explicitly from `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`.
- Always ask for and apply `business_context` before computing CTR; if the answer is both contexts, segment by `business_context` instead of pooling.
- For search-level CTR, first collapse to one row per `ids.id_search` and compute `MAX(metrics.click)`; then aggregate.
- For ranking analysis, keep `dimensions.absolute_position`, `dimensions.page_number`, and `dimensions.page_position` distinct.
- Check `dimensions.is_outlier_user` when computing benchmark metrics to avoid outlier-driven distortions.
- For AB-test reads, extract variants with `json_extract_scalar(variants, '$.<experiment_name>')` and keep one user-variant or search-variant assignment per analysis window before aggregating.
- For every read from `datalake_search.search_impressions`, include `year`, `month`, and `day` partition predicates in addition to the `date` filter.
- When filtering an experiment by its active window, get the start and end dates from `dags/conversational_xp/enrich_base_metrics_service/queries/enrich/experiment_config.sql`. If the experiment has no end date, use today's date as the end date.

**Don't:**
- Don't use `datalake_search.search_metrics` for search CTR, ranking position, or AB-test search analysis unless the requester explicitly asks for the pre-aggregated monitoring output.
- Don't count rows as searches. Rows are listing impressions; use `COUNT(DISTINCT ids.id_search)` for search count.
- Don't aggregate rent and sale together by default; the search behavior and downstream conversion baselines differ.
- Don't join search directly to downstream contract/visit tables without first defining the attribution grain and time window.
- Don't compare rank models, platforms, or rendering types without preserving the business context and partition filters.
- Don't interpret `metrics.contract_signed = 1` as a generic contract count; it is an outcome attached to a search-impression row.

## Golden Queries

### Query 1 — Base search impression pattern

Use this pattern to inspect search-result listing impressions with key dimensions and metrics at listing impression grain.

```sql
SELECT
    date,
    ts_event,
    json_extract_scalar(ids, '$.id_search') AS id_search,
    CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
    CAST(json_extract_scalar(ids, '$.id_house') AS BIGINT) AS id_house,
    json_extract_scalar(ids, '$.id_session') AS id_session,
    json_extract_scalar(dimensions, '$.business_context') AS business_context,
    json_extract_scalar(dimensions, '$.platform') AS platform,
    json_extract_scalar(dimensions, '$.search_rendering_type') AS search_rendering_type,
    json_extract_scalar(dimensions, '$.rank_model') AS rank_model,
    CAST(json_extract_scalar(dimensions, '$.absolute_position') AS INTEGER) AS absolute_position,
    CAST(json_extract_scalar(dimensions, '$.page_number') AS INTEGER) AS page_number,
    CAST(json_extract_scalar(dimensions, '$.page_position') AS INTEGER) AS page_position,
    COALESCE(CAST(json_extract_scalar(metrics, '$.search') AS INTEGER), 0) AS search,
    COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click,
    COALESCE(CAST(json_extract_scalar(metrics, '$.visit_booked') AS INTEGER), 0) AS visit_booked,
    COALESCE(CAST(json_extract_scalar(metrics, '$.offer') AS INTEGER), 0) AS offer,
    COALESCE(CAST(json_extract_scalar(metrics, '$.contract_signed') AS INTEGER), 0) AS contract_signed
FROM datalake_search.search_impressions
WHERE date >= current_date - INTERVAL '30' DAY
  AND (
        year > year(current_date - INTERVAL '30' DAY)
        OR (
            year = year(current_date - INTERVAL '30' DAY)
            AND month > month(current_date - INTERVAL '30' DAY)
        )
        OR (
            year = year(current_date - INTERVAL '30' DAY)
            AND month = month(current_date - INTERVAL '30' DAY)
            AND day >= day(current_date - INTERVAL '30' DAY)
        )
    )
  AND (
        year < year(current_date)
        OR (year = year(current_date) AND month < month(current_date))
        OR (
            year = year(current_date)
            AND month = month(current_date)
            AND day <= day(current_date)
        )
    )
LIMIT 200
```

### Query 2 — Search volume and CTR trend by day

Tracks search listing-impression volume, distinct searches, users, and both impression-level and search-level CTR over time.

```sql
WITH search_impressions AS (
    SELECT
        date AS dt_reference,
        json_extract_scalar(ids, '$.id_search') AS id_search,
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click
    FROM datalake_search.search_impressions
    WHERE date >= current_date - INTERVAL '60' DAY
      AND (
            year > year(current_date - INTERVAL '60' DAY)
            OR (
                year = year(current_date - INTERVAL '60' DAY)
                AND month > month(current_date - INTERVAL '60' DAY)
            )
            OR (
                year = year(current_date - INTERVAL '60' DAY)
                AND month = month(current_date - INTERVAL '60' DAY)
                AND day >= day(current_date - INTERVAL '60' DAY)
            )
        )
      AND (
            year < year(current_date)
            OR (year = year(current_date) AND month < month(current_date))
            OR (
                year = year(current_date)
                AND month = month(current_date)
                AND day <= day(current_date)
            )
        )
),
searches AS (
    SELECT
        dt_reference,
        business_context,
        id_search,
        MAX(click) AS search_clicked
    FROM search_impressions
    GROUP BY
        dt_reference,
        business_context,
        id_search
)
SELECT
    search_impressions.dt_reference,
    search_impressions.business_context,
    COUNT(*) AS listing_impressions,
    COUNT(DISTINCT search_impressions.id_search) AS searches,
    COUNT(DISTINCT search_impressions.id_user) AS users,
    AVG(CAST(search_impressions.click AS DOUBLE)) AS ctr_impression,
    AVG(CAST(searches.search_clicked AS DOUBLE)) AS ctr_search
FROM search_impressions
LEFT JOIN searches
    ON search_impressions.dt_reference = searches.dt_reference
    AND search_impressions.business_context = searches.business_context
    AND search_impressions.id_search = searches.id_search
GROUP BY
    search_impressions.dt_reference,
    search_impressions.business_context
ORDER BY
    search_impressions.dt_reference DESC,
    search_impressions.business_context
```

### Query 3 — CTR by ranking position and platform

Shows where search performance differs by ranking position, page, platform, rendering type, and rank model.

```sql
WITH search_impressions AS (
    SELECT
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        json_extract_scalar(dimensions, '$.platform') AS platform,
        json_extract_scalar(dimensions, '$.search_rendering_type') AS search_rendering_type,
        json_extract_scalar(dimensions, '$.rank_model') AS rank_model,
        CAST(json_extract_scalar(dimensions, '$.absolute_position') AS INTEGER) AS absolute_position,
        CAST(json_extract_scalar(dimensions, '$.page_number') AS INTEGER) AS page_number,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click
    FROM datalake_search.search_impressions
    WHERE date >= current_date - INTERVAL '45' DAY
      AND (
            year > year(current_date - INTERVAL '45' DAY)
            OR (
                year = year(current_date - INTERVAL '45' DAY)
                AND month > month(current_date - INTERVAL '45' DAY)
            )
            OR (
                year = year(current_date - INTERVAL '45' DAY)
                AND month = month(current_date - INTERVAL '45' DAY)
                AND day >= day(current_date - INTERVAL '45' DAY)
            )
        )
      AND (
            year < year(current_date)
            OR (year = year(current_date) AND month < month(current_date))
            OR (
                year = year(current_date)
                AND month = month(current_date)
                AND day <= day(current_date)
            )
        )
)
SELECT
    business_context,
    platform,
    search_rendering_type,
    rank_model,
    absolute_position,
    page_number,
    COUNT(*) AS listing_impressions,
    AVG(CAST(click AS DOUBLE)) AS ctr_impression
FROM search_impressions
GROUP BY
    business_context,
    platform,
    search_rendering_type,
    rank_model,
    absolute_position,
    page_number
HAVING COUNT(*) >= 100
ORDER BY
    business_context,
    absolute_position,
    listing_impressions DESC
```

### Query 4 — Search CTR per AB test variant

Use this when you need both user allocation and search-level CTR by variant for a specific test key.

Before sharing or executing this query, confirm `business_context`, `dt_start`, and `dt_end` with the requester. Set `{business_context_filter}` to `'rent'`, `'sale'`, or `'rent', 'sale'` when the requester explicitly wants both contexts split.

```sql
WITH search_variant AS (
    SELECT
        json_extract_scalar(ids, '$.id_search') AS id_search,
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(variants, '$.{experiment_name}') AS ab_test,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        MAX(COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0)) AS click
    FROM datalake_search.search_impressions
    WHERE date >= DATE('{dt_start}')
      AND date <= DATE('{dt_end}')
      AND json_extract_scalar(dimensions, '$.business_context') IN ({business_context_filter})
      AND (year, month, day) >= (
            year(DATE('{dt_start}')),
            month(DATE('{dt_start}')),
            day(DATE('{dt_start}'))
        )
      AND (year, month, day) <= (
            year(DATE('{dt_end}')),
            month(DATE('{dt_end}')),
            day(DATE('{dt_end}'))
        )
      AND json_extract_scalar(variants, '$.{experiment_name}') IS NOT NULL
    GROUP BY
        json_extract_scalar(ids, '$.id_search'),
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT),
        json_extract_scalar(variants, '$.{experiment_name}'),
        json_extract_scalar(dimensions, '$.business_context')
)
SELECT
    ab_test,
    business_context,
    COUNT(DISTINCT id_user) AS users_in_variant,
    SUM(click) AS clicked_searches,
    COUNT(*) AS searches,
    AVG(CAST(click AS DOUBLE)) AS ctr_search
FROM search_variant
GROUP BY
    ab_test,
    business_context
ORDER BY
    ab_test,
    business_context
```

### Query 5 — Search-attributed downstream journey

Use this to compute downstream outcome rates directly from the processed search metrics. Add timestamp-difference filters when the question requires a fixed attribution window.

```sql
WITH search_impressions AS (
    SELECT
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click,
        COALESCE(CAST(json_extract_scalar(metrics, '$.visit_booked') AS INTEGER), 0) AS visit_booked,
        COALESCE(CAST(json_extract_scalar(metrics, '$.visit_completed') AS INTEGER), 0) AS visit_completed,
        COALESCE(CAST(json_extract_scalar(metrics, '$.offer') AS INTEGER), 0) AS offer,
        COALESCE(CAST(json_extract_scalar(metrics, '$.contract_signed') AS INTEGER), 0) AS contract_signed
    FROM datalake_search.search_impressions
    WHERE date >= current_date - INTERVAL '90' DAY
      AND (
            year > year(current_date - INTERVAL '90' DAY)
            OR (
                year = year(current_date - INTERVAL '90' DAY)
                AND month > month(current_date - INTERVAL '90' DAY)
            )
            OR (
                year = year(current_date - INTERVAL '90' DAY)
                AND month = month(current_date - INTERVAL '90' DAY)
                AND day >= day(current_date - INTERVAL '90' DAY)
            )
        )
      AND (
            year < year(current_date)
            OR (year = year(current_date) AND month < month(current_date))
            OR (
                year = year(current_date)
                AND month = month(current_date)
                AND day <= day(current_date)
            )
        )
)
SELECT
    business_context,
    COUNT(*) AS listing_impressions,
    AVG(CAST(click AS DOUBLE)) AS click_rate,
    AVG(CAST(visit_booked AS DOUBLE)) AS visit_booked_rate,
    AVG(CAST(visit_completed AS DOUBLE)) AS visit_completed_rate,
    AVG(CAST(offer AS DOUBLE)) AS offer_rate,
    AVG(CAST(contract_signed AS DOUBLE)) AS contract_signed_rate
FROM search_impressions
GROUP BY
    business_context
ORDER BY
    business_context
```