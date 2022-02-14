WITH base AS (
    SELECT
        CAST(e.id_user AS BIGINT) AS id_user,
        CAST(e.ts_event AS TIMESTAMP) AS ts_visit_intent,
        dr.sk_region,
        dr.city_name,
        ROW_NUMBER() OVER (PARTITION BY e.id_user ORDER BY e.ts_event) AS rw
    FROM
        datalake_amplitude_clean_prod.events e
    LEFT JOIN
        sale.fact_listings fl
        	ON CAST(fl.sk_house AS VARCHAR) = TRIM(JSON_EXTRACT_PATH_TEXT(e.event_properties, 'house_id'))
    LEFT JOIN
    	dim_region dr
        	ON dr.sk_region = fl.sk_region
    WHERE
        e.event_type IN ('visit_intent_clicked','visit_schedule_clicked', 'schedule_page_viewed', 'visit_schedule_confirmed')
        AND CAST(TRIM(JSON_EXTRACT_PATH_TEXT(event_properties, 'business_context')) AS VARCHAR) IN ('sale','SALE')
        AND e.id_app = 170698
        AND CAST(e.ts_event AS DATE) >= CAST('2020-01-01' AS DATE)
        AND e.id_user IS NOT NULL
)
SELECT
    id_user,
    sk_region,
    city_name,
    ts_visit_intent AS ts_first_visit_intent
FROM
    base
WHERE
    rw = 1