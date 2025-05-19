WITH visits AS (
   SELECT 
      id,
      id_house,
      ts_visit_fup
   FROM
      datalake_booking.booking
   WHERE 
      ts_visit_fup IS NOT NULL
   QUALIFY 
      ROW_NUMBER() OVER (PARTITION BY id_house, ts_visit_fup ORDER BY id DESC) = 1
),
visits_review AS (
   SELECT
      v.id_house,
      BOOL_AND(r.is_listing_accurate) AS is_listing_accurate,
      DATE(DATE_TRUNC('DAY', v.ts_visit_fup)) AS dt_visit
   FROM
      visits AS v
   INNER JOIN 
      datalake_booking.booking_review AS r
         ON v.id = r.id_booking
   WHERE 
      r.is_listing_accurate IS NOT NULL
   GROUP BY
      1, 3
),
visits_review_changes AS (
   SELECT 
      id_house,
      is_listing_accurate,
      dt_visit AS dt_change
   FROM 
      visits_review
   QUALIFY
      is_listing_accurate IS DISTINCT FROM LAG(is_listing_accurate) OVER (PARTITION BY id_house ORDER BY dt_visit) 
)
SELECT 
   id_house,
   is_listing_accurate,
   dt_change,
   LEAD(dt_change) OVER (PARTITION BY id_house ORDER BY dt_change DESC) AS ts_next_change
FROM
   visits_review_changes