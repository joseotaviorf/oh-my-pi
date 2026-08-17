WITH lookup AS (
    SELECT
        state,
        locality,
        start_range,
        MAX(end_range) AS end_range
    FROM datalake_gsheets_clean.criteo_region_lookup
    GROUP BY
        state,
        locality,
        start_range
),
-- EMR-safe replacement for the zip-code range join. The previous
-- `ON cc.zip_code BETWEEN lk.start_range AND lk.end_range` is a non-equi
-- predicate that Databricks optimized as a RANGE_JOIN but EMR Spark 3.5 can
-- only plan as BroadcastNestedLoopJoin (O(N x M), 1-2 tasks). Since start_range
-- and end_range are 5-digit CEP prefixes, every range spans at most a handful of
-- 2-digit prefixes; we explode each range into its 2-digit prefix bins so the
-- join gains an equi key (SUBSTR(zip_code, 1, 2) = zip_bin) and the BETWEEN
-- stays only as a residual filter. Verified row-for-row identical to the range
-- join on the full plaintext source (datalake_gsheets_clean.criteo_costs).
lookup_exploded AS (
    SELECT
        state,
        locality,
        start_range,
        end_range,
        EXPLODE(
            SEQUENCE(
                CAST(SUBSTR(start_range, 1, 2) AS INT),
                CAST(SUBSTR(end_range, 1, 2) AS INT)
            )
        ) AS zip_bin_int
    FROM lookup
),
lookup_binned AS (
    SELECT
        state,
        locality,
        start_range,
        end_range,
        LPAD(CAST(zip_bin_int AS STRING), 2, '0') AS zip_bin
    FROM lookup_exploded
)

SELECT
    -- Dimensions
    id_advertiser AS id_account,
    id_campaign,
    id_ad_set AS id_adset,
    CAST(NULL AS STRING) AS id_ad,
    CASE
        WHEN advertiser_name = 'Quinto Andar Demand RetenÃ§Ã£o - ForSale BR' THEN 'Quinto Andar Demand Retenção - ForSale BR'
        ELSE advertiser_name
    END AS account_name,
    'criteo' AS origin,
    'campaigns' AS report_type,
    campaign_name AS utm_campaign,
    ad_set AS utm_term,
    CAST(NULL AS STRING) AS utm_content,
    -- Regions
    'BR' AS country_code,
    cc.region AS state,
    lk.locality AS city,
    -- Metrics
    cc.clicks,
    CAST(NULL AS BIGINT) AS conversions,
    cc.displays AS impressions,
    cc.cost AS total_cost,
    -- Date Reference
    cc.dt_report AS dt_cost,
    YEAR(cc.dt_report) AS year,
    MONTH(cc.dt_report) AS month,
    DAY(cc.dt_report) AS day
FROM
    datalake_criteo.criteo_campaigns AS cc
LEFT JOIN lookup_binned AS lk
    ON SUBSTR(cc.zip_code, 1, 2) = lk.zip_bin
    AND cc.zip_code BETWEEN lk.start_range AND lk.end_range
WHERE
    CAST(dt_report AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
