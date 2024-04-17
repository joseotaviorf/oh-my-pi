WITH amplitude_events AS (
    SELECT
        ep_house_id AS id_house,
        id_amplitude,
        LOWER(business_context) AS business_context
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        DATE(year::STRING || month::STRING || day::STRING) >= (CURRENT_DATE - INTERVAL '30' DAY)
        AND ts_event >= (CURRENT_DATE - INTERVAL '7' DAY)
),
houses AS (
    SELECT
        llf.sk_house AS id_house,
        LOWER(llf.origin_table) AS business_context,
        MIN(dd.date) AS dt_first_listing
    FROM
        dw_datamarts.lead_listing_flows AS llf
    INNER JOIN
        dw_public.dim_date AS dd
            ON llf.sk_first_listing_date = dd.sk_date
    WHERE
        llf.sk_first_listing_date > 0
    GROUP BY 1,2
),
aux AS (
    SELECT
        e.id_house,
        e.business_context,
        CASE
            WHEN LOWER(dhl.house_type) IN ('apartamento', 'studiooukitchenette') THEN 'apartamento'
            WHEN LOWER(dhl.house_type) IN ('casa', 'casacondominio') THEN 'casa'
        END AS house_type,
        fhl.sk_region,
        COUNT(DISTINCT e.id_amplitude) AS views_quantity
    FROM
        amplitude_events AS e
    INNER JOIN
        houses AS h
            ON e.id_house::BIGINT = h.id_house
            AND e.business_context = h.business_context
    INNER JOIN
        dw_public.dim_house_listing AS dhl
            ON dhl.id_house = h.id_house
    INNER JOIN
        dw_public.fact_house_listings AS fhl
            ON dhl.sk_house_listing = fhl.sk_house_listing
    GROUP BY 1,2,3,4
),
metrics AS (
    SELECT
        id_house,
        business_context,
        views_quantity,
        PERCENTILE(views_quantity, .25) OVER(PARTITION BY sk_region, business_context) AS lpv_p_25,
        PERCENTILE(views_quantity, .50) OVER(PARTITION BY sk_region, business_context) AS lpv_p_50,
        PERCENTILE(views_quantity, .75) OVER(PARTITION BY sk_region, business_context) AS lpv_p_75
    FROM
        aux
)
SELECT
    id_house,
    business_context,
    views_quantity,
    lpv_p_25,
    lpv_p_50,
    lpv_p_75,
    CASE
        WHEN views_quantity < lpv_p_25 THEN 'LOW'
        WHEN views_quantity > lpv_p_75 THEN 'HIGH'
        WHEN views_quantity >= lpv_p_25 AND views_quantity <= lpv_p_75 THEN 'MEDIUM'
    END AS lpv_temperature_region_context -- Considera os quartiles do business_context e da regiao
FROM
    metrics
