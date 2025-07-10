WITH rent_houses_catalog AS (
    SELECT DISTINCT
        'house' AS type_item,
        'rent' AS business_context,
        ts_status_start AS ts_status_started,
        CAST(
            SUBSTRING(
                CAST(sk_house_listing AS STRING), 1, 9
            )
            AS INTEGER
        ) AS id_item,
        COALESCE(ts_status_end, CURRENT_TIMESTAMP()) AS ts_status_ended
    FROM
        dw_rent.fact_house_listing_status
    WHERE
        status_history IN ('publicado', 'PUBLISHED')
        AND ts_status_start <= CURRENT_TIMESTAMP()
        AND ts_status_start IS NOT NULL
        AND (
            ts_status_end IS NULL
            OR ts_status_end >= TO_TIMESTAMP('2019-01-01')
        )
),

sale_houses_catalog AS (
    SELECT DISTINCT
        'house' AS type_item,
        'sale' AS business_context,
        ts_status_started,
        CAST(
            SUBSTRING(
                CAST(sk_sale_listing AS STRING),
                1, 9
            )
            AS INTEGER
        )
        AS id_item,
        COALESCE(ts_status_ended, CURRENT_TIMESTAMP()) AS ts_status_ended
    FROM
        dw_sale.fact_listing_status
    WHERE
        status_history = 'PUBLISHED'
        AND ts_status_started <= CURRENT_TIMESTAMP()
        AND ts_status_started IS NOT NULL
        AND (
            ts_status_ended IS NULL
            OR ts_status_ended >= TO_TIMESTAMP('2019-01-01')
        )
)

SELECT * FROM rent_houses_catalog
UNION ALL
SELECT * FROM sale_houses_catalog
