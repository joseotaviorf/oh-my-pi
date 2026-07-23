WITH visits AS (
  SELECT
    id,
    id_house,
    ts_visit_fup
  FROM (
    SELECT
      id,
      id_house,
      ts_visit_fup,
      ROW_NUMBER() OVER (PARTITION BY id_house, ts_visit_fup ORDER BY id DESC) AS _w
    FROM datalake_booking.booking
    WHERE
      NOT ts_visit_fup IS NULL
  ) AS _t
  WHERE
    _w = 1
), visits_review AS (
  SELECT
    v.id_house,
    BOOL_AND(r.is_listing_accurate) AS is_listing_accurate,
    CAST(DATE_TRUNC('DAY', v.ts_visit_fup) AS DATE) AS dt_visit
  FROM visits AS v
  INNER JOIN datalake_booking.booking_review AS r
    ON v.id = r.id_booking
  WHERE
    NOT r.is_listing_accurate IS NULL
  GROUP BY
    1,
    3
), visits_review_changes AS (
  SELECT
    id_house,
    is_listing_accurate,
    dt_change
  FROM (
    SELECT
      id_house,
      is_listing_accurate,
      dt_visit AS dt_change,
      LAG(is_listing_accurate) OVER (PARTITION BY id_house ORDER BY dt_visit) AS _w,
      dt_visit
    FROM visits_review
  ) AS _t
  WHERE
    is_listing_accurate IS DISTINCT FROM _w
)
SELECT
  id_house,
  is_listing_accurate,
  TRUE AS has_3p_access_control,
  dt_change,
  LEAD(dt_change) OVER (PARTITION BY id_house ORDER BY dt_change DESC) AS ts_next_change
FROM visits_review_changes