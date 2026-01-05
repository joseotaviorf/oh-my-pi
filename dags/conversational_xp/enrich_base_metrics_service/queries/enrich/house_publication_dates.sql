-----------------
--House publication

WITH houses_catalog AS (
    SELECT DISTINCT
        CAST(
            SUBSTRING(
                CAST(sk_house_listing AS STRING), 1, 9
            )
            AS INTEGER
        ) AS id_house,
        'rent' AS business_context,
        ts_status_start AS ts_house_published

    FROM
        dw_rent.fact_house_listing_status
    WHERE
        status_history IN ('publicado', 'PUBLISHED')
        AND ts_status_start IS NOT NULL

    UNION ALL

    SELECT DISTINCT
        CAST(
            SUBSTRING(
                CAST(sk_sale_listing AS STRING),
                1, 9
            )
            AS INTEGER
        )
        AS id_house,
        'sale' AS business_context,
        ts_status_started AS ts_house_published
    FROM
        dw_sale.fact_listing_status
    WHERE
        status_history = 'PUBLISHED'
        AND ts_status_started IS NOT NULL
),

house_published_repeated AS (
  SELECT
    id_house,
    ts_house_published,
    business_context,
    LAG(ts_house_published) OVER (PARTITION BY id_house, business_context ORDER BY ts_house_published) AS ts_house_published_shift
  FROM
    houses_catalog
)

SELECT
  id_house,
  business_context,
  ts_house_published
FROM
  house_published_repeated
WHERE
  COALESCE(DATEDIFF(ts_house_published, ts_house_published_shift), 1000) > 84
