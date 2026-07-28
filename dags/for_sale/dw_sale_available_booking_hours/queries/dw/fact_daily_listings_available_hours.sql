WITH snapshot AS (
  SELECT
    sk_date,
    sk_house,
    sk_region,
    week_available_hours,
    workdays_available_hours,
    monday_available_hours,
    tuesday_available_hours,
    wednesday_available_hours,
    thursday_available_hours,
    friday_available_hours,
    saturday_available_hours,
    sunday_available_hours,
    year,
    month,
    day
  FROM (
    SELECT
      d.sk_date,
      w.id_house AS sk_house,
      w.id_region AS sk_region,
      w.week_available_hours,
      w.workdays_available_hours,
      w.monday_available_hours,
      w.tuesday_available_hours,
      w.wednesday_available_hours,
      w.thursday_available_hours,
      w.friday_available_hours,
      w.saturday_available_hours,
      w.sunday_available_hours,
      d.year,
      d.month,
      d.day,
      ROW_NUMBER() OVER (PARTITION BY w.id_house, year, month, day ORDER BY dt_schedule_started DESC) AS _w,
      dt_schedule_started
    FROM datalake_sale_available_booking_hours.weekly_available_booking_hours AS w
    JOIN dw_public.dim_date AS d
      ON d.date BETWEEN w.dt_schedule_started AND COALESCE(w.dt_schedule_ended, NOW())
    WHERE
      MAKE_DATE(d.year, d.month, d.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    _w = 1
), sale_status AS (
  SELECT
    sk_house,
    sk_region,
    status_history,
    year,
    month,
    day
  FROM (
    SELECT
      CAST(LEFT(f.sk_sale_listing, 9) AS BIGINT) AS sk_house,
      f.sk_region,
      f.status_history,
      d.year,
      d.month,
      d.day,
      ROW_NUMBER() OVER (PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS _w,
      f.sk_sale_listing,
      d.date,
      f.ts_status_started
    FROM dw_sale.fact_listing_status AS f
    JOIN dw_public.dim_date AS d
      ON d.date BETWEEN CAST(f.ts_status_started AS DATE) AND COALESCE(CAST(f.ts_status_ended AS DATE), NOW())
    WHERE
      MAKE_DATE(d.year, d.month, d.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  sk_date,
  sk_house,
  COALESCE(s.sk_region, sst.sk_region) AS sk_region,
  status_history,
  week_available_hours,
  workdays_available_hours,
  monday_available_hours,
  tuesday_available_hours,
  wednesday_available_hours,
  thursday_available_hours,
  friday_available_hours,
  saturday_available_hours,
  sunday_available_hours,
  year,
  month,
  day
FROM snapshot AS s
LEFT JOIN sale_status AS sst
  USING (sk_house, day, month, year)
WHERE
  NOT status_history IS NULL