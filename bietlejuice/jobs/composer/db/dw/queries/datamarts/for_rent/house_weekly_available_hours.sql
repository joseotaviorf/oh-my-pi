WITH daily_published_listings AS (
    SELECT
        f.sk_house_listing,
        LEFT(f.sk_house_listing,9) AS id_house,
        d.date,
        d.week_day,
        d.week_start,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
    FROM
        fact_house_listing_status f
    JOIN
        dim_date d
            ON d.sk_date between NULLIF(f.sk_status_start_date,-1) AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, TO_CHAR(current_date -1, 'YYYYMMDD')::bigint)
    WHERE f.status_history = 'publicado' -- consider published AND suspended status
      AND substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
      AND d.date > current_date - interval '180 DAYS'
)
, house_available_hours AS (
    SELECT
        dpl.id_house,
        REPLACE(hah.id_house||dpl.week_start, '-', '') AS id_house_week,
        dpl.week_start,
        dpl.date,
        dpl.week_day,
        hah.day_hours_available
    FROM
        daily_published_listings dpl
    LEFT JOIN
        datamarts.house_available_hours hah
            ON hah.id_house = dpl.id_house
            AND dpl.date BETWEEN hah.available_started_date AND COALESCE(hah.available_ended_date, current_date)
            AND dpl.week_day = (hah.day_of_week - 1) -- matching exactly week day schedule change
    WHERE dpl.order_status = 1
)
SELECT
id_house,
id_house_week,
week_start,
sum(day_hours_available) AS available_hours
FROM
    house_available_hours
GROUP BY id_house,id_house_week,week_start
ORDER BY id_house_week