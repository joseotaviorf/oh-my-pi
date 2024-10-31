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
        AND country_code = 'BR'

    UNION ALL

    SELECT DISTINCT
        CAST(
            SUBSTRING(
                CAST(fact_listing_status.sk_sale_listing AS STRING),
                1, 9
            )
            AS INTEGER
        )
        AS id_house,
        'sale' AS business_context,
        fact_listing_status.ts_status_started AS ts_house_published
    FROM
        dw_sale.fact_listing_status AS fact_listing_status
    LEFT JOIN dw_public.dim_region AS dim_region
        ON fact_listing_status.sk_region = dim_region.sk_region
    WHERE
        fact_listing_status.status_history = 'PUBLISHED'
        AND fact_listing_status.ts_status_started IS NOT NULL
        AND dim_region.country_code = 'BR'
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
        CONCAT('{{', array_join(array_agg(CONCAT('"', experiment_config.experiment_name, '":"all"')), ','), '}}') AS variants
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
),

df_houses_published AS (
    SELECT
        CAST(NULL AS STRING) AS id_search,
        houses_published.id_house,

        --ids

        '{{}}' AS ids,

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
        DAY(houses_published.ts_house_published) AS day,
        WEEKOFYEAR(houses_published.ts_house_published) AS week
    FROM
      houses_published
    LEFT JOIN house_cities
        ON houses_published.id_house = house_cities.id_house
    WHERE houses_published.ts_house_published BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_21}) AND DATE('{end_date}')
),

unique_houses_ids AS (
    SELECT DISTINCT
        id_house, ts_event, date, year, month, day, week
    FROM
        df_houses_published
),

join_dfs AS (
    SELECT
        search_impressions.id_search,
        search_impressions.id_house,
        search_impressions.ids,
        search_impressions.dimensions,
        search_impressions.variants,
        regexp_replace(search_impressions.metrics, '\\}}', ',"house_published":1}}') AS metrics,
        search_impressions.timestamps,
        unique_houses_ids.ts_event,
        unique_houses_ids.date,
        unique_houses_ids.year,
        unique_houses_ids.month,
        unique_houses_ids.day,
        unique_houses_ids.week
    FROM
        datalake_search.search_impressions AS search_impressions
    INNER JOIN
        unique_houses_ids
    ON
        search_impressions.id_house = unique_houses_ids.id_house
        AND get_json_object(search_impressions.timestamps, '$.ts_house_published') = unique_houses_ids.ts_event
    WHERE search_impressions.ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_21}) AND DATE('{end_date}')
)

SELECT * FROM df_houses_published
UNION ALL
SELECT * FROM join_dfs
