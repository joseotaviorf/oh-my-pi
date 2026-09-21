# Recs

## Ownership

**Data Steward:**
- pedro.nogueira@quintoandar.com.br

## Overview

Recs represents recommendation exposures shown to users across product surfaces, especially recommendation carousels tied to listing discovery. Use this entity to measure recommendation volume, click-through behavior, segment performance, AB-test variants, and downstream journey outcomes after an exposure.

The source of truth for every recs metric in this document is `datalake_search.recs_impressions_processed`. It stores recommendation identifiers, dimensions, variants, metrics, and timestamps as JSON payloads plus event date/partition columns.

The lifecycle usually follows these stages:
1. **Impression generated** — recommendation shown (`datalake_search.recs_impressions_processed.ts_event`)
2. **Identifiers and dimensions attached** — recset, user, house, context, platform, showcase, and position are read from `ids` and `dimensions`
3. **Interaction measured** — click and recommendation counts are read from `metrics`
4. **Downstream outcomes attached** — visit, direct-offer, offer, and contract outcomes are read from `metrics` and `timestamps`

Not all impressions lead to user interaction or conversion. Some recommendation sets are only viewed and never clicked, and attribution depends on the metric/timestamp fields available on the processed impression row.

## Glossary and Synonyms

- **recs**, **recommendations**, **recomendacoes**, **carrossel de recomendacao** → recommendation exposures tracked in `datalake_search.recs_impressions_processed`
- **recset**, **carousel** → recommendation set identifier (`ids.id_recset`, `ids.id_recset_fix`)
- **impression** → one listing shown in one recommendation set; count rows in `datalake_search.recs_impressions_processed`
- **click de recs**, **CTR de recs** → click-through behavior from `metrics.click`
- **clicks por usuario em recs**, **recs clicks by user** → first compute user-level click count by summing `metrics.click` by `ids.id_user`; then aggregate those user-level counts by AB-test variant or requested recs dimensions
- **contexto de negocio** → recommendation context from `json_extract_scalar(dimensions, '$.business_context')`, usually `RENT` or `SALE`
- **showcase** → recommendation surface/type from `dimensions.showcase`, for example `LISTING_SIMILAR_USER`
- **usuario outlier** → high-activity users flagged in `dimensions.is_outlier_user`
- **mercado primario**, **primary market** → house SALE listing classified as new-build from `dimensions.is_primary_market` (1 when the listing_sale_type SSOT is PRIMARY, else 0). Do not use the legacy `house.is_sale_primary_market` boolean.
- **conversao de recs** → downstream outcomes after recommendation contact from `metrics.visit_booked`, `metrics.direct_offer`, `metrics.offer`, `metrics.contract_signed`, and matching timestamp fields in `timestamps`
- **variant**, **AB test** → experiment assignment from `variants.<experiment_name>`
- **search**, **busca**, **resultado de busca** → active search-result discovery tracked in [`search.md`](./search.md), not recommendation carousel exposure

## Tables

| You need... | Use this table |
|-------------|----------------|
| Any recs metric, including impressions, recsets, CTR, AB-test allocation, segments, and downstream outcomes | `datalake_search.recs_impressions_processed` (`rip`) — processed recommendation-impression base with JSON payloads (`ids`, `dimensions`, `variants`, `metrics`, `timestamps`) and physical partitions (`year`, `month`, `day`) |

**Critical rules:**
- Compute every recs metric from `datalake_search.recs_impressions_processed`; do not route CTR, user-level click counts, conversion, LPV, or AB-test recs metrics to separate metric tables.
- Extract JSON fields explicitly from `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`.
- Use `ids.id_recset_fix` (not raw `ids.id_recset`) as the unique recset key per user/session when deduplicating recommendation sets.
- Keep `json_extract_scalar(dimensions, '$.business_context')` consistent (`RENT` vs `SALE`) in aggregations; do not pool contexts in one KPI unless the requester explicitly asks for a combined result.
- For CTR requests, ask which `business_context` to use before returning SQL or results. Valid choices are `RENT`, `SALE`, or both as separate rows.
- Treat `dimensions.is_outlier_user` explicitly, either as a filter or segment, in performance analysis to avoid skewed CTR/conversion.
- For AB-test analyses, always define both test start date and test end date in filters before computing allocation or CTR.
- Always filter partitions using `year`, `month`, and `day` in the `WHERE` clause to avoid full partition scans. Keep the `date` or `ts_event` filter too, but never rely on it alone.

## AB Test Request Protocol (Mandatory)

When the user asks for AB-test metrics, for example CTR by variant, follow this interaction rule:

- Ask for `business_context` before returning CTR SQL or results. If the user wants both `RENT` and `SALE`, return them as separate rows.
- Ask for both `dt_start` and `dt_end` before running or returning AB-test metrics.
- For `ab_beakman_search_services_feed_sequence_experiment`, if `dt_start` is missing, use `DATE('2026-05-07')` as the default start date and only ask for `dt_end`.
- For every metric request, including CTR and AB-test metrics, `business_context` is required. If the user does not provide one, ask whether to filter to a specific `business_context` or group the result by `business_context`; never return a metric aggregated across business contexts without making that grouping explicit.
- If either date or `business_context` is missing, do not provide the metric value yet; request the missing input first.
- If `dt_end` is missing, do not return the SQL query template yet; ask for `dt_end` first.
- After receiving both dates, apply both as explicit event-date filters and as physical partition filters (`year`, `month`, `day`) in the AB-test query.
- When adapting AB-test queries for `app`, `platform`, `showcase`, or any other segment, keep the full partition filter block from the base query. Segment filters are additive and must not replace partition predicates.
- Do not use open-ended AB-test windows by default.

Partition filter requirement for `datalake_search.recs_impressions_processed`:

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

For requests like "recs ctr for `<experiment_name>`", always route to recs AB-test patterns from this document.

- Primary and only source for recs CTR by variant and user-level recs clicks by variant: `datalake_search.recs_impressions_processed`.
- Compute variant assignment with `json_extract_scalar(variants, '$.<experiment_name>')`.
- Always state CTR grain in the response (`ctr_recset` vs `ctr_impression`).
- Do not answer "recs ctr" from other experiment or metrics tables.

Prompt-to-query mapping for this specific active test:
- Prompt: "recs ctr for `ab_beakman_search_services_feed_sequence_experiment`"
- Expected path: ask `business_context` and `dt_end` first, then run Query 4 (`ctr_recset` by variant and business context) with `dt_start = DATE('2026-05-07')`.
- If the requester says "for the app", add a `platform = 'app'` filter from `dimensions.platform` while still keeping the `date`, `year`, `month`, and `day` filters from Query 4.
- Only add `showcase` to the output when the requester explicitly asks for a showcase breakdown. Use Query 5 only for explicitly requested segment cuts such as `showcase` or `platform`.

## Key Metrics

- Recommendation impressions (`COUNT(*)` on `datalake_search.recs_impressions_processed`)
- Recommendation sets generated (`COUNT(DISTINCT ids.id_recset_fix)` after extracting from `ids`)
- Users exposed to recommendations (`COUNT(DISTINCT ids.id_user)` after extracting from `ids`)
- Recommendation clicks (`SUM(CAST(metrics.click AS INTEGER))` after extracting from `metrics`)
- Recommendation clicks per user by segment (first `SUM(CAST(metrics.click AS INTEGER)) GROUP BY ids.id_user` and requested segment keys, then aggregate those user-level counts by AB-test variant or segment)
- Impression-level CTR (`AVG(CAST(metrics.click AS DOUBLE))` after extracting from `metrics`)
- Recset-level CTR (`AVG(CAST(click AS DOUBLE))` after collapsing one row per `ids.id_recset_fix`, `ids.id_user`, and `json_extract_scalar(dimensions, '$.business_context')` with `MAX(metrics.click)`)
- Recommendation-attributed visit booked rate (`AVG(CAST(metrics.visit_booked AS DOUBLE))` after extracting from `metrics`)
- Recommendation-attributed direct-offer rate (`AVG(CAST(metrics.direct_offer AS DOUBLE))` after extracting from `metrics`)
- Recommendation-attributed offer rate (`AVG(CAST(metrics.offer AS DOUBLE))` after extracting from `metrics`)
- Recommendation-attributed contract signed rate (`AVG(CAST(metrics.contract_signed AS DOUBLE))` after extracting from `metrics`)
- Impression volume by showcase (`COUNT(*) GROUP BY dimensions.showcase`)
- CTR by position (`AVG(CAST(metrics.click AS DOUBLE)) GROUP BY dimensions.position`)
- CTR by AB-test variant (`AVG(CAST(click AS DOUBLE))` after one row per recset and variant assignment from `variants.<experiment_name>`)

### Metric Grain Conventions

- `ctr_impression`: impression-level CTR using `metrics.click` on each processed impression row.
- `ctr_recset`: recset-level CTR using one row per (`ids.id_recset_fix`, `ids.id_user`, `json_extract_scalar(dimensions, '$.business_context')`) and click collapsed with `MAX(metrics.click)`.
- `recs_clicks_by_user`: two-step metric. First compute `SUM(click)` at `ids.id_user` grain after extracting `metrics.click`; then aggregate the resulting user-level counts by `variants.<experiment_name>` or requested segment columns. Do not compute average clicks per user directly from impression rows.
- `users_in_variant`: user-allocation metric (`COUNT(DISTINCT ids.id_user)`) and should not be interpreted as impression or recset volume.
- Conversion rates from `metrics.visit_booked`, `metrics.direct_offer`, `metrics.offer`, and `metrics.contract_signed` are row-level processed-impression rates unless first collapsed to a recset, user, or user-house grain.
- When reporting AB-test results, explicitly state which CTR grain is being used.

## Relationships with Other Entities

### Broker XP (N:1 via listing and visibility context)

- Recs impressions expose listing/house identifiers in `ids.id_house`; use that key to reason about listing visibility context before joining to house or search visibility entities.
- Keep event grain in mind: recs is impression-per-listing-per-recset, while search events can fan out per search result.

### Search (Parallel discovery surface)

- Use [`search.md`](./search.md) when the request is about search result pages, search ranking, search CTR, or `datalake_search.search_impressions`.
- Use this recs guide when the request is about recommendation carousels, recommendation sets, showcase, or `datalake_search.recs_impressions_processed`.
- Both entities expose JSON payloads named `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`, but the grains are different: recs is listing impression per recommendation set; search is listing impression per search result.

### CDP (N:1 via `id_user` — attribution only)

- **UTM and click IDs** before or after recs exposure → `datalake_cdp_clean.user_tracking` on `ids.id_user` (event grain); see `domain_entities/cdp.md`.
- Recs impression and CTR metrics stay on `datalake_search.recs_impressions_processed` — do not substitute CDP event tables.

### Visits (N:1 via user-house journey keys)

- Use `ids.id_user`, `ids.id_house`, and `json_extract_scalar(dimensions, '$.business_context')` as the journey keys exposed by `datalake_search.recs_impressions_processed`.
- For recommendation-attributed visit logic inside this entity, use `metrics.visit_booked`, `metrics.direct_offer`, `timestamps.ts_visit_booked`, and `timestamps.ts_direct_offer`.
- Split by `json_extract_scalar(dimensions, '$.business_context')` before aggregating Visit KPIs.

### Closing (N:1 via contract outcomes)

- Contract outcomes inside this entity are exposed by `metrics.contract_signed` and `timestamps.ts_contract_signed`.
- Keep attribution semantics explicit: "contract signed after recommendation exposure/click" is different from generic signed-contract volume.

## Dos and Don'ts

**Do:**
- Use `datalake_search.recs_impressions_processed` for all recs metrics and examples.
- Extract JSON keys explicitly from `ids`, `dimensions`, `variants`, `metrics`, and `timestamps`.
- Always Ask for and apply `business_context` before computing CTR; if the answer is both contexts, segment by `business_context` instead of pooling.
- Add `showcase` to CTR outputs only when the requester explicitly asks for showcase-level results.
- Filter or segment by `platform` before comparing performance across cohorts when platform is part of the request.
- Check `dimensions.is_outlier_user` when computing benchmark metrics to avoid outlier-driven distortions.
- For recs clicks per user, first group by `ids.id_user` and sum `metrics.click`; then aggregate those user-level click counts by AB-test variant or the requested segment. Always filter or group by `business_context`, and add `variants.<experiment_name>`, `platform`, `showcase`, or other dimensions when they are part of the requested segment.
- For AB-test reads, extract variants with `json_extract_scalar(variants, '$.<experiment_name>')` and keep one user-variant assignment per analysis window before aggregating.
- For every read from `datalake_search.recs_impressions_processed`, include `year`, `month`, and `day` partition predicates in addition to the `date` filter.
- For AB-test CTR by recs segment, always include `business_context`; include `showcase` only when explicitly requested; include `platform` when explicitly requested.
- Require explicit AB-test date bounds (`dt_start` and `dt_end`) in every AB-test query; avoid open-ended ranges.
- When filtering an experiment by its active window, get the start and end dates from `dags/conversational_xp/enrich_base_metrics_service/queries/enrich/experiment_config.sql`. If the experiment has no end date, use today's date as the end date.


**Don't:**
- Don't use separate metric tables for recs CTR, conversion, LPV, AB-test allocation, or global metrics when answering from this entity.
- Don't use only `ids.id_recset` to deduplicate recommendation sets; use `ids.id_recset_fix`.
- Don't interpret `metrics.contract_signed = 1` as strictly 14-day attributed conversion unless the query also validates the timestamp difference from `timestamps.ts_recommendation`.
- Don't aggregate RENT and SALE together by default; the conversion paths and baselines differ.
- Don't add `showcase` to CTR result sets unless the requester directly asks for a showcase breakdown.
- Don't join recs directly to downstream contract/visit tables without first defining the attribution grain (user-house, recset, or impression).
- Don't join `listing_sale_type` or use `house.is_sale_primary_market` for recs-impression market cuts; use `dimensions.is_primary_market`.
- Do not assume the business context for an experiment. Ask the user explicitly before deciding whether the analysis should focus on conversion, engagement, lead qualification, recommendation quality, operational performance, or another context.

## Golden Queries

### Query 1 — Base recommendation impression pattern

Use this pattern to inspect recommendation impressions with key dimensions and metrics at impression grain.

```sql
SELECT
    date,
    ts_event,
    json_extract_scalar(ids, '$.id_recset_fix') AS id_recset_fix,
    CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
    CAST(json_extract_scalar(ids, '$.id_house') AS BIGINT) AS id_house,
    json_extract_scalar(dimensions, '$.business_context') AS business_context,
    json_extract_scalar(dimensions, '$.platform') AS platform,
    json_extract_scalar(dimensions, '$.showcase') AS showcase,
    CAST(json_extract_scalar(dimensions, '$.position') AS INTEGER) AS listing_position_in_recset,
    COALESCE(CAST(json_extract_scalar(metrics, '$.recommendations') AS INTEGER), 0) AS recommendations,
    COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click,
    COALESCE(CAST(json_extract_scalar(metrics, '$.visit_booked') AS INTEGER), 0) AS visit_booked,
    COALESCE(CAST(json_extract_scalar(metrics, '$.direct_offer') AS INTEGER), 0) AS direct_offer,
    COALESCE(CAST(json_extract_scalar(metrics, '$.offer') AS INTEGER), 0) AS offer,
    COALESCE(CAST(json_extract_scalar(metrics, '$.contract_signed') AS INTEGER), 0) AS contract_signed
FROM datalake_search.recs_impressions_processed
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

### Query 2 — Recommendation volume and CTR trend by day

Tracks recommendation impression volume, recset volume, and CTR over time using only processed impressions.

```sql
WITH recs_impressions AS (
    SELECT
        date AS dt_reference,
        json_extract_scalar(ids, '$.id_recset_fix') AS id_recset_fix,
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click
    FROM datalake_search.recs_impressions_processed
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
)
SELECT
    dt_reference,
    business_context,
    COUNT(*) AS impressions,
    COUNT(DISTINCT id_recset_fix) AS recsets,
    COUNT(DISTINCT id_user) AS users,
    AVG(CAST(click AS DOUBLE)) AS ctr_impression
FROM recs_impressions
GROUP BY
    dt_reference,
    business_context
ORDER BY
    dt_reference DESC,
    business_context
```

### Query 3 — CTR segmentation by showcase, platform, and position

Shows where recommendation performance differs by surface and ranking position.

```sql
WITH recs_impressions AS (
    SELECT
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        json_extract_scalar(dimensions, '$.showcase') AS showcase,
        json_extract_scalar(dimensions, '$.platform') AS platform,
        CAST(json_extract_scalar(dimensions, '$.position') AS INTEGER) AS listing_position_in_recset,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click
    FROM datalake_search.recs_impressions_processed
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
    showcase,
    platform,
    listing_position_in_recset,
    COUNT(*) AS impressions,
    AVG(CAST(click AS DOUBLE)) AS ctr_impression
FROM recs_impressions
GROUP BY
    business_context,
    showcase,
    platform,
    listing_position_in_recset
HAVING COUNT(*) >= 100
ORDER BY
    business_context,
    impressions DESC
```

### Query 4 — CTR per AB test variant

Use this when you need both user allocation and CTR by variant for a specific test key. This is the default AB-test CTR pattern; it does not include `showcase`.

Before sharing or executing this query, confirm `business_context` and `dt_end` with the requester. If `business_context` or `dt_end` is not provided, ask for it first and stop. Set `{business_context_filter}` to `'RENT'`, `'SALE'`, or `'RENT', 'SALE'` when the requester explicitly wants both contexts split.

```sql
WITH recset_variant AS (
    SELECT
        json_extract_scalar(ids, '$.id_recset_fix') AS id_recset_fix,
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ) AS ab_test,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        MAX(COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0)) AS click
    FROM datalake_search.recs_impressions_processed
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
      AND json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ) IS NOT NULL
    GROUP BY
        json_extract_scalar(ids, '$.id_recset_fix'),
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT),
        json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ),
        json_extract_scalar(dimensions, '$.business_context')
)
SELECT
    ab_test,
    business_context,
    COUNT(DISTINCT id_user) AS users_in_variant,
    SUM(click) AS clicked_recsets,
    COUNT(*) AS recsets,
    AVG(CAST(click AS DOUBLE)) AS ctr_recset
FROM recset_variant
GROUP BY
    ab_test,
    business_context
ORDER BY
    ab_test,
    business_context
```

### Query 5 — CTR per AB test variant by showcase, business context, and platform

Use this only when the requester explicitly asks for AB-test CTR sliced by `showcase`, `platform`, or another recs dimension from `datalake_search.recs_impressions_processed`. Do not use it for a plain "recs CTR by variant" request.

Before sharing or executing this query, confirm `business_context` and `dt_end` with the requester. If `business_context` or `dt_end` is not provided, ask for it first and stop. For this specific experiment, default `dt_start = DATE('2026-05-07')`. Set `{business_context_filter}` to `'RENT'`, `'SALE'`, or `'RENT', 'SALE'` when the requester explicitly wants both contexts split.

```sql
WITH recset_variant_segment AS (
    SELECT
        json_extract_scalar(ids, '$.id_recset_fix') AS id_recset_fix,
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ) AS ab_test,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        json_extract_scalar(dimensions, '$.platform') AS platform,
        json_extract_scalar(dimensions, '$.showcase') AS showcase,
        MAX(COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0)) AS click
    FROM datalake_search.recs_impressions_processed
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
      AND json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ) IS NOT NULL
    GROUP BY
        json_extract_scalar(ids, '$.id_recset_fix'),
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT),
        json_extract_scalar(
            variants,
            '$.ab_beakman_search_services_feed_sequence_experiment'
        ),
        json_extract_scalar(dimensions, '$.business_context'),
        json_extract_scalar(dimensions, '$.platform'),
        json_extract_scalar(dimensions, '$.showcase')
)
SELECT
    ab_test,
    platform,
    showcase,
    business_context,
    COUNT(DISTINCT id_user) AS users_in_variant,
    SUM(click) AS clicked_recsets,
    COUNT(*) AS recsets,
    AVG(CAST(click AS DOUBLE)) AS ctr_recset
FROM recset_variant_segment
GROUP BY
    ab_test,
    platform,
    showcase,
    business_context
ORDER BY
    ab_test,
    platform,
    showcase,
    business_context
```

### Query 6 — User-level recs clicks by AB-test variant and segment

Use this when the requester asks for recs clicks per user split by AB-test variant, `platform`, `showcase`, or another segment. The query must first compute clicks per user, then aggregate those user-level counts by the requested segment. If no AB test is requested, remove `ab_test` from the `SELECT`, `WHERE`, and `GROUP BY`.

Before sharing or executing this query for an AB test, confirm `business_context`, `dt_start`, and `dt_end` with the requester. Set `{experiment_name}` to the variant key in `variants` and `{business_context_filter}` to `'RENT'`, `'SALE'`, or `'RENT', 'SALE'` when the requester explicitly wants both contexts split.

```sql
WITH recs_impressions AS (
    SELECT
        CAST(json_extract_scalar(ids, '$.id_user') AS BIGINT) AS id_user,
        json_extract_scalar(ids, '$.id_recset_fix') AS id_recset_fix,
        json_extract_scalar(variants, '$.{experiment_name}') AS ab_test,
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        json_extract_scalar(dimensions, '$.platform') AS platform,
        json_extract_scalar(dimensions, '$.showcase') AS showcase,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click
    FROM datalake_search.recs_impressions_processed
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
),
user_clicks AS (
    SELECT
        id_user,
        ab_test,
        business_context,
        platform,
        showcase,
        SUM(click) AS recs_clicks,
        COUNT(*) AS impressions,
        COUNT(DISTINCT id_recset_fix) AS recsets_exposed,
        SUM(CASE WHEN click > 0 THEN 1 ELSE 0 END) AS clicked_impressions
    FROM recs_impressions
    GROUP BY
        id_user,
        ab_test,
        business_context,
        platform,
        showcase
)
SELECT
    ab_test,
    business_context,
    platform,
    showcase,
    COUNT(*) AS users,
    SUM(recs_clicks) AS recs_clicks,
    AVG(CAST(recs_clicks AS DOUBLE)) AS avg_recs_clicks_per_user,
    approx_percentile(recs_clicks, 0.5) AS median_recs_clicks_per_user,
    SUM(impressions) AS impressions,
    SUM(recsets_exposed) AS recsets_exposed,
    SUM(clicked_impressions) AS clicked_impressions
FROM user_clicks
GROUP BY
    ab_test,
    business_context,
    platform,
    showcase
ORDER BY
    ab_test,
    business_context,
    recs_clicks DESC,
    users DESC
```

### Query 7 — Recommendation-attributed downstream journey from processed impressions

Use this to compute downstream outcome rates directly from the processed impression metrics. Add timestamp-difference filters when the question requires a fixed attribution window.

```sql
WITH recs_impressions AS (
    SELECT
        json_extract_scalar(dimensions, '$.business_context') AS business_context,
        COALESCE(CAST(json_extract_scalar(metrics, '$.click') AS INTEGER), 0) AS click,
        COALESCE(CAST(json_extract_scalar(metrics, '$.visit_booked') AS INTEGER), 0) AS visit_booked,
        COALESCE(CAST(json_extract_scalar(metrics, '$.direct_offer') AS INTEGER), 0) AS direct_offer,
        COALESCE(CAST(json_extract_scalar(metrics, '$.offer') AS INTEGER), 0) AS offer,
        COALESCE(CAST(json_extract_scalar(metrics, '$.contract_signed') AS INTEGER), 0) AS contract_signed
    FROM datalake_search.recs_impressions_processed
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
    COUNT(*) AS impressions,
    AVG(CAST(click AS DOUBLE)) AS click_rate,
    AVG(CAST(visit_booked AS DOUBLE)) AS visit_booked_rate,
    AVG(CAST(direct_offer AS DOUBLE)) AS direct_offer_rate,
    AVG(CAST(offer AS DOUBLE)) AS offer_rate,
    AVG(CAST(contract_signed AS DOUBLE)) AS contract_signed_rate
FROM recs_impressions
GROUP BY
    business_context
ORDER BY
    business_context
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
