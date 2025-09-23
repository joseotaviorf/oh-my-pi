WITH rent_daily_info AS (
    SELECT
        id_house,
        year,
        month,
        day,
        dt_day,
        uuid_company
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
WITH sale_daily_info AS (
    SELECT
        id_house,
        year,
        month,
        day,
        sk_company
    FROM
        datalake_sale_ongoing_listings.ongoing_listings_daily_info
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    UUID() AS id,
    CAST(CONCAT(hms.id_house, DATE_FORMAT(MAKE_DATE(hms.year, hms.month, hms.day), 'yyyyMMdd')) AS STRING) AS business_id,
    hms.id_house,
    '44bab39d-39e5-44b9-88fe-0a1a800c0bb3' AS company_uuid,
    hms.base_lpv AS traffic_count,
    hms.base_vb AS visits_scheduled_count,
    hms.base_favorites AS favorites_count,
    hms.base_os AS offers_count,
    hms.similar_lpv AS traffic_median,
    hms.similar_vb AS visits_scheduled_median,
    hms.similar_favorites AS favorites_median,
    hms.similar_os AS offers_median,
    hms.final_score AS demand_score,
    IF(
        hms.similar_lpv IS NOT NULL,
        CASE
            WHEN hms.base_lpv = hms.similar_lpv THEN 'ON_MEDIAN'
            WHEN hms.base_lpv > hms.similar_lpv THEN 'ABOVE_MEDIAN'
            ELSE 'BELOW_MEDIAN'
        END,
        NULL
    ) AS traffic_flag,
    IF(
        hms.similar_vb IS NOT NULL,
        CASE
            WHEN hms.base_vb = hms.similar_vb THEN 'ON_MEDIAN'
            WHEN hms.base_vb > hms.similar_vb THEN 'ABOVE_MEDIAN'
            ELSE 'BELOW_MEDIAN'
        END,
        NULL
    ) AS visits_scheduled_flag,
    IF(
        hms.similar_favorites IS NOT NULL,
        CASE
            WHEN hms.base_favorites = hms.similar_favorites THEN 'ON_MEDIAN'
            WHEN hms.base_favorites > hms.similar_favorites THEN 'ABOVE_MEDIAN'
            ELSE 'BELOW_MEDIAN'
        END,
        NULL
    ) AS favorites_flag,
    IF(
        hms.similar_os IS NOT NULL,
        CASE
            WHEN hms.base_os = hms.similar_os THEN 'ON_MEDIAN'
            WHEN hms.base_os > hms.similar_os THEN 'ABOVE_MEDIAN'
            ELSE 'BELOW_MEDIAN'
        END,
        NULL
    ) AS offers_flag,
    hms.business_context,
    DATE_DIFF(hms.dt_agg_ended, hms.dt_agg_started) + 1 AS period_in_days,
    hms.year,
    hms.month,
    hms.day
FROM
    datalake_similarity_score.house_metrics_score AS hms
LEFT JOIN
    rent_daily_info AS rdi
        ON rdi.year = hms.year
        AND rdi.month = hms.month
        AND rdi.day = hms.day
        AND rdi.id_house = hms.id_house
        AND hms.business_context = 'RENT'
LEFT JOIN
    sale_daily_info AS sdi
        ON sdi.year = hms.year
        AND sdi.month = hms.month
        AND sdi.day = hms.day
        AND sdi.id_house = hms.id_house
        AND hms.business_context = 'SALE'
WHERE
    MAKE_DATE(hms.year, hms.month, hms.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND rdi.uuid_company IS NULL
    AND sdi.sk_company IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY hms.id_house, hms.business_context, hms.year, hms.month, hms.day ORDER BY rdi.dt_day DESC) = 1

