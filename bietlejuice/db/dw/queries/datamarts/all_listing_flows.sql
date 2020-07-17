WITH all_listings AS (
SELECT 
	f.sk_house_listing,
	f.status_history,
	DATE(f.ts_status_start) AS dt_status_start,
	DATE(COALESCE(f.ts_status_end,CURRENT_DATE)) AS dt_status_end, 
    f.ts_status_start,
    CASE WHEN status_history NOT IN ('alugado', 'despublicado', 'suspenso', 'publicado') THEN 'outros'
        ELSE status_history END status_history_v2
FROM fact_house_listing_status f
join dim_house_listing dhl
  ON dhl.sk_house_listing = f.sk_house_listing
WHERE (dhl.is_last_version = true AND dhl.version > 0) AND (f.ts_status_end is null OR f.ts_status_end >= '2020-01-01') AND f.ts_status_start >= '2019-01-01'
), all_listings_date AS (
SELECT DISTINCT
    al.sk_house_listing,
    d.week_start,
    al.status_history_v2,
    al.ts_status_start,
	max(al.ts_status_start) OVER(PARTITION BY al.sk_house_listing, d.week_start) AS last_status_start
FROM dim_date d
join all_listings al
   ON d.date >= al.dt_status_start AND d.date <= al.dt_status_end
WHERE d.week_start < DATE_TRUNC('week', CURRENT_DATE)
), al_week AS (
SELECT
    aldr.week_start,
    DATE(aldr.week_start + INTERVAL '1 week') AS next_week_start,
    aldr.status_history_v2 AS status_history,
    aldr.sk_house_listing
FROM all_listings_date aldr 
WHERE last_status_start = ts_status_start
), al_week_status AS (
SELECT
    DATE(COALESCE(alw_ws.week_start,(COALESCE(alw_ws.next_week_start, alw_nws.week_start) - INTERVAL '1 week'))) AS week_start,
    COALESCE(alw_ws.next_week_start, alw_nws.week_start) AS next_week_start,
    alw_ws.status_history AS status_week_start,
    alw_nws.status_history AS status_next_week,
    COALESCE(alw_ws.sk_house_listing, alw_nws.sk_house_listing) AS sk_house_listing
FROM al_week alw_ws
FULL OUTER JOIN al_week alw_nws
  ON alw_ws.sk_house_listing = alw_nws.sk_house_listing AND alw_ws.next_week_start = alw_nws.week_start
), al_week_status_region AS (
SELECT
    alw.sk_house_listing,
    alw.week_start,
    alw.status_week_start,
    alw.status_next_week,
    alw.next_week_start,
    dr.city_group
FROM al_week_status alw
LEFT JOIN fact_house_listings fhl
  ON alw.sk_house_listing = fhl.sk_house_listing
LEFT JOIN dim_region dr
  ON fhl.sk_region = dr.sk_region
WHERE dr.city_group IS NOT NULL
)
SELECT
    week_start,
    city_group,
    status_week_start,
    COUNT(DISTINCT sk_house_listing) AS total_listings,
    status_next_week,
    next_week_start
FROM al_week_status_region alw
WHERE week_start < DATE_TRUNC('week',CURRENT_DATE) - INTERVAL '1 week' AND week_start >= '2020-01-01'
GROUP BY 1,2,3,5,6;
