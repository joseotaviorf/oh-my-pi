-- Grain: one row per buyer prospect who has ever (within the window below)
-- touched a Primary Market pilot house, per enrich_buyer_prospect_type.sale_type.
-- Scoped to Primary Market: buyers who never touched Primary are not included.
WITH params AS (
    -- bp_window_days: NULL = infinite lookback (all-time). Set an integer
    -- (e.g. 90) to only count touches within that many days of today.
    SELECT CAST(NULL AS INT) AS bp_window_days
),
touches AS (
    SELECT
        bpt.id_prospect,
        bpt.sale_type
    FROM datalake_buyer_prospect.buyer_prospect_type AS bpt
    CROSS JOIN params AS p
    WHERE
        bpt.id_house IS NOT NULL
        AND (p.bp_window_days IS NULL OR bpt.ts_activation >= DATE_SUB(CURRENT_DATE(), p.bp_window_days))
),
agg AS (
    SELECT
        id_prospect,
        MAX(CASE WHEN sale_type = 'PRIMARY' THEN 1 ELSE 0 END) = 1 AS touched_primary,
        MAX(CASE WHEN sale_type = 'SECONDARY' THEN 1 ELSE 0 END) = 1 AS touched_secondary,
        COUNT(*) AS n_events
    FROM touches
    GROUP BY id_prospect
)
SELECT
    id_prospect,
    CASE
        WHEN touched_primary AND touched_secondary THEN 'NON_EXCLUSIVE'
        ELSE 'PRIMARY_EXCLUSIVE'
    END AS bp_market_type,
    n_events,
    CURRENT_DATE() AS dt_computed
FROM agg
WHERE touched_primary
