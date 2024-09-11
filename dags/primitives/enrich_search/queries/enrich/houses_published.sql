/*
Table with all published houses.
*/

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
),

houses_published AS (
    SELECT
        id_house,
        business_context,
        ts_house_published,
        CONCAT('{', array_join(array_agg(CONCAT('"', experiment_config.experiment_name, '":"all"')), ','), '}') AS variants
    FROM
        house_published_repeated
    LEFT JOIN
        datalake_search.experiment_config AS experiment_config
        ON experiment_config.config.begin_date <= ts_house_published
        AND (experiment_config.config.end_date >= ts_house_published OR experiment_config.config.end_date IS NULL)
    WHERE
        COALESCE(DATEDIFF(ts_house_published, ts_house_published_shift), 1000) > 84
    GROUP BY
        id_house,
        business_context,
        ts_house_published
),

-----------------
--Houses Cities

house_cities AS (
    SELECT
        id AS id_house,
        Last(city) AS city
    FROM
        wonka.house_main
    GROUP BY
        id
)

SELECT
    CAST(NULL AS STRING) AS id_search,
    houses_published.id_house,

    --ids

    '{}' AS ids,

    -- dimensions

    to_json(
        named_struct(
            'business_context', houses_published.business_context,
            'city', house_cities.city
        )
    ) AS dimensions,

    --experimentation

    variants,

    --metrics

    to_json(
        named_struct(
            'house_published', 1
        )
    ) AS metrics,

    -- timestamps

    to_json(
        named_struct(
            'ts_house_published', houses_published.ts_house_published
        )
    ) AS timestamps,

    houses_published.ts_house_published AS ts_event,
    DATE(houses_published.ts_house_published) AS date,
    YEAR(houses_published.ts_house_published) AS year,
    MONTH(houses_published.ts_house_published) AS month,
    DAY(houses_published.ts_house_published) AS day
FROM
  houses_published
LEFT JOIN house_cities
    ON houses_published.id_house = house_cities.id_house
WHERE houses_published.ts_house_published BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_21}) AND DATE('{end_date}')
