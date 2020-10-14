WITH
daily_published_listings AS (
   SELECT
      f.sk_house_listing,
      f.status_history,
      d.sk_date,
      d.date,
      d.week_start,
      d.week_day,
      d.weekday_name,
      d.month_start,
      d.month_end,
      ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing,
                                     d.date
                        ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
   FROM
      fact_house_listing_status AS f
      INNER JOIN dim_date AS d
         ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1)
                              AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date, -1),'YYYYMMDD') - 1, 'YYYYMMDD')::BIGINT,
                                           TO_CHAR(CURRENT_DATE - 1, 'YYYYMMDD')::BIGINT)
   WHERE 
      f.status_history = 'publicado' -- consider only published status
      AND SUBSTRING(sk_house_listing, 10, 12) <> '000' -- consider only listings that already started publication
),
house_status_and_dimensions AS (
   SELECT
      fhs.sk_date,
      fhs.sk_house_listing,
      fhs.date,
      fhs.week_day,
      fhs.week_start,
      fhs.weekday_name,
      dhl.id_house,
      fhs.month_start,
      fhs.month_end,
      fhs.order_status,
      fhs.status_history,
      fhl.sk_region,
      dr.city_group,
      dr.city_name AS city,
      dr.region_code,
      dr.name AS neighborhood,
      DATE(DATE_TRUNC('WEEK', dhl.ts_publication)) AS week_start_publication,
      CASE
         WHEN dhl.house_bedrooms <= 1 THEN 1
         WHEN dhl.house_bedrooms >= 4 THEN 4
          ELSE dhl.house_bedrooms
      END AS house_bedrooms,
      dhl.is_b2b,
      dp.sk_partner,
      dp.trade_name
   FROM
      daily_published_listings AS fhs
      LEFT OUTER JOIN fact_house_listings AS fhl
         ON fhs.sk_house_listing = fhl.sk_house_listing
      LEFT OUTER JOIN dim_region AS dr
         ON fhl.sk_region = dr.sk_region
      LEFT OUTER JOIN dim_house_listing AS dhl
         ON fhs.sk_house_listing = dhl.sk_house_listing
      LEFT OUTER JOIN dim_partner dp
         ON dp.sk_partner = fhl.sk_partner
   WHERE
      fhs.order_status = 1
      AND dr.city_group IS NOT NULL
      AND fhs.weekday_name = 'Sunday'
),
house_status_and_dimensions_book AS (
   SELECT
      fhs.sk_house_listing,
      fhs.week_start,
      dhl.id_house,
      fhs.status_history,
      fhl.sk_region,
      dr.city_group,
      dr.city_name AS city,
      dr.region_code,
      dr.name AS neighborhood,
      DATE(DATE_TRUNC('WEEK', dhl.ts_publication)) AS week_start_publication,
      CASE
         WHEN dhl.house_bedrooms <= 1 THEN 1
         WHEN dhl.house_bedrooms >= 4 THEN 4
         ELSE dhl.house_bedrooms
      END AS house_bedrooms,
      dhl.is_b2b,
      dp.sk_partner,
      dp.trade_name
   FROM
      daily_published_listings AS fhs
      INNER JOIN fact_house_listings AS fhl
         ON fhs.sk_house_listing = fhl.sk_house_listing
      INNER JOIN dim_region AS dr
         ON fhl.sk_region = dr.sk_region
      LEFT OUTER JOIN dim_house_listing AS dhl
         ON fhs.sk_house_listing = dhl.sk_house_listing
      LEFT OUTER JOIN dim_partner AS dp
         ON dp.sk_partner = fhl.sk_partner
   WHERE fhs.order_status = 1
      AND dr.city_group IS NOT NULL
),
ongoing_listings_wk_snapshot AS (
   -- returns for each week and dimension the sunday count/snapshot of publicated listings
   SELECT
      hsd.city_group,
      hsd.city,
      hsd.region_code,
      hsd.neighborhood,
      hsd.week_start,
      hsd.week_start_publication,
      hsd.house_bedrooms,
      hsd.is_b2b,
      hsd.sk_partner,
      hsd.trade_name,
      COUNT(DISTINCT hsd.sk_house_listing) AS ongoing_listings
   FROM
      house_status_and_dimensions AS hsd
   GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
bookings AS (
   -- returns number of bookings, independently of house status on booking_creation_date
   SELECT
      dr.city_group,
       dr.city_name AS city,
      dr.region_code,
      dr.name AS neighborhood,
      dd.week_start,
      DATE(DATE_TRUNC('WEEK', dhl.ts_publication)) AS week_start_publication,
      CASE
         WHEN dhl.house_bedrooms <= 1 THEN 1
         WHEN dhl.house_bedrooms >= 4 THEN 4
         ELSE dhl.house_bedrooms
      END AS house_bedrooms,
      dhl.is_b2b,
      dp.sk_partner,
      dp.trade_name,
      COUNT(DISTINCT flrf.sk_booking) AS visits_booked
   FROM
      fact_listing_rent_flows AS flrf
      INNER JOIN dim_date AS dd
         ON flrf.sk_booking_created_date = dd.sk_date
      INNER JOIN fact_house_listings AS fhl
         ON flrf.sk_house_listing = fhl.sk_house_listing
      INNER JOIN dim_region AS dr
         ON fhl.sk_region = dr.sk_region
      LEFT OUTER JOIN dim_house_listing AS dhl
         ON flrf.sk_house_listing = dhl.sk_house_listing
      LEFT OUTER JOIN dim_partner AS dp
         ON dp.sk_partner = fhl.sk_partner
   WHERE
      sk_booking > 0
   GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
lpv_events AS (
   -- aggregates listing_page_view event counts per event date and house_id
   WITH 
   amplitude AS (
      SELECT
         CASE
            WHEN NULLIF(REGEXP_SUBSTR(JSON_EXTRACT_PATH_TEXT(event_properties, 'house_id'), '^\\d{9}$'), '') IS NOT NULL
            THEN REGEXP_SUBSTR(JSON_EXTRACT_PATH_TEXT(event_properties, 'house_id'), '^\\d{9}$')::BIGINT
            ELSE NULL 
         END AS id_house,
         TO_CHAR(DATE(ts_event), 'YYYYMMDD')::BIGINT AS sk_event_dt,
         ts_event::DATE AS event_dt,
         uuid
      FROM
         datalake_amplitude_clean_staging_prod."170698_listing_page_viewed_events"
    )
   SELECT
      id_house,
      sk_event_dt,
      event_dt,
      dd.week_start,
      COUNT(DISTINCT uuid) AS cnt_listing_page_view
   FROM
      amplitude AS amp
      INNER JOIN dim_date AS dd
         ON dd.sk_date = amp.sk_event_dt
   GROUP BY 1,2,3,4
),
listing_page_views AS (
   -- returns number of listing_page_view events per house and date, independently of house status on event date
   SELECT
      hsdb.city_group,
      hsdb.city,
      hsdb.region_code,
      hsdb.neighborhood,
      COALESCE(le.week_start, hsdb.week_start) AS week_start,
      hsdb.week_start_publication,
      hsdb.house_bedrooms,
      hsdb.is_b2b,
      hsdb.sk_partner,
      hsdb.trade_name,
      SUM(le.cnt_listing_page_view) AS listing_page_views
   FROM
      lpv_events AS le
      INNER JOIN house_status_and_dimensions_book AS hsdb
         ON hsdb.id_house = le.id_house
         AND hsdb.week_start = le.week_start
   GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
results AS (
   -- merge results from different sub-queries into one result set
   SELECT
      COALESCE(ol.city_group, vb.city_group, lpv.city_group) AS "city_group",
      COALESCE(ol.city, vb.city, lpv.city) AS "city",
      COALESCE(ol.region_code, vb.region_code, lpv.region_code) AS "region_code",
      COALESCE(ol.neighborhood, vb.neighborhood, lpv.neighborhood) AS "neighborhood",
      COALESCE(ol.week_start, vb.week_start, lpv.week_start) AS "week_start",
      COALESCE(ol.week_start_publication, vb.week_start_publication, lpv.week_start_publication) AS "week_start_publication",
      COALESCE(ol.house_bedrooms, vb.house_bedrooms, lpv.house_bedrooms) AS "house_bedrooms",
      COALESCE(ol.is_b2b, vb.is_b2b, lpv.is_b2b) AS "is_b2b",
      COALESCE(ol.sk_partner, vb.sk_partner, lpv.sk_partner) AS "sk_partner",
      COALESCE(ol.trade_name, vb.trade_name, lpv.trade_name) AS "trade_name",
      ongoing_listings,
      visits_booked,
      listing_page_views
   FROM 
      ongoing_listings_wk_snapshot AS ol
      FULL OUTER JOIN bookings AS vb
         ON vb.city_group = ol.city_group
         AND vb.city = ol.city
         AND vb.region_code = ol.region_code
         AND vb.neighborhood = ol.neighborhood
         AND vb.week_start = ol.week_start
         AND vb.week_start_publication = ol.week_start_publication
         AND vb.house_bedrooms = ol.house_bedrooms
         AND vb.is_b2b = ol.is_b2b
         AND vb.sk_partner = ol.sk_partner
         AND vb.trade_name = ol.trade_name
      FULL OUTER JOIN listing_page_views AS lpv
         ON lpv.city_group = ol.city_group
         AND lpv.city = ol.city
         AND lpv.region_code = ol.region_code
         AND lpv.neighborhood = ol.neighborhood
         AND lpv.week_start = ol.week_start
         AND lpv.week_start_publication = ol.week_start_publication
         AND lpv.house_bedrooms = ol.house_bedrooms
         AND lpv.is_b2b = ol.is_b2b
         AND lpv.sk_partner = ol.sk_partner
         AND lpv.trade_name = ol.trade_name
   ORDER BY 5, 6, 1, 2, 3, 4, 7, 8, 9, 10
)
SELECT
   *,
   CURRENT_TIMESTAMP AS ts_load
FROM
   results
LIMIT 10