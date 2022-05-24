WITH daily_published_listings AS (
    SELECT /*+ RANGE_JOIN(f, 19000) */
        f.sk_house_listing,
        LEFT(f.sk_house_listing,9) AS id_house,
        d.date,
        d.week_day,
        d.week_start,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
    FROM
        dw_public.fact_house_listing_status AS f
    JOIN
        dw_public.dim_date AS d
            ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
            AND CAST(DATE_FORMAT( COALESCE(to_date(CAST(NULLIF(sk_status_end_date,-1) AS STRING), 'yyyyMMdd'), CURRENT_DATE) -1 ,'yyyyMMdd') AS BIGINT)
    WHERE 
        f.status_history = 'publicado' -- consider published AND suspended status
        AND substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
        AND d.date > DATE_SUB(CURRENT_DATE,180)
),
house_available_hours AS (
    SELECT /** RANGE_JOIN(hah, 1100) */
        dpl.id_house,
        REPLACE(hah.id_house||dpl.week_start, '-', '') AS id_house_week,
        dpl.week_start,
        dpl.date,
        dpl.week_day,
        hah.day_hours_available
    FROM
        daily_published_listings AS dpl
    LEFT JOIN
        dw_datamarts.house_available_hours AS hah
            ON hah.id_house = dpl.id_house
            AND dpl.date BETWEEN hah.available_started_date AND COALESCE(hah.available_ended_date, current_date)
            AND dpl.week_day = (hah.day_of_week - 1) -- matching exactly week day schedule change
    WHERE
        dpl.order_status = 1
)
SELECT
    id_house,
    id_house_week,
    week_start,
    SUM(day_hours_available) AS available_hours
FROM
    house_available_hours
GROUP BY 1, 2, 3