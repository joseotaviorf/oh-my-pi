WITH
dim_house AS (
    SELECT DISTINCT
        h.id AS id_house,
        h.id_region AS sk_region
    FROM
        datalake_ebdb_clean_prod.house AS h
),
base AS (
    SELECT
        dd.sk_date,
        dr.city_group,
        COUNT(DISTINCT evt.uuid) as events
    FROM
        datalake_amplitude_clean_prod.events AS evt
        JOIN dim_date AS dd
            ON DATE(evt.ts_event) = dd.date
        JOIN dim_house AS dh
            ON JSON_EXTRACT_PATH_TEXT(evt.event_properties, 'house_id') = dh.id_house
        JOIN dim_region AS dr
            ON dh.sk_region = dr.sk_region
    WHERE
        dr.city_group IN ('RMSP', 'Rio de Janeiro', 'Campinas', 'Belo Horizonte', 'Brasília', 'Porto Alegre', 'Goiânia', 'Curitiba', 'Florianópolis')
        AND LOWER(JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_source')) = 'criteo'
        AND evt.event_type = 'listing_page_viewed'
        AND COALESCE(LOWER(JSON_EXTRACT_PATH_TEXT(event_properties, 'business_context')), 'rent') = 'rent'
        AND dd.date >= DATE('2018-01-01')
    GROUP BY 1,2
    ORDER BY 1 DESC,2
)
SELECT
    sk_date,
    city_group,
    events / NULLIF(SUM(EVENTS) OVER(PARTITION BY sk_date), 0)::FLOAT AS share
FROM
    base