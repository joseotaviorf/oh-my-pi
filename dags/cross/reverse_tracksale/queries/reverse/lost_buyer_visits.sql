WITH
  last_visit AS (
    SELECT
      id_visitor,
      MAX(ts_schedule_visit) last_dt_scheduling
    FROM
      datalake_visit.visit_schedules
    WHERE
      ts_schedule_visit >= CURRENT_DATE - INTERVAL '30' DAY
    GROUP BY
      1
  ),
  first_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.id_schedule AS sk_booking,
      last_visit.last_dt_scheduling
    FROM
      datalake_visit.visit_schedules first_visit
    INNER JOIN
      last_visit
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    WHERE
      first_visit.business_context = 'SALE'
      AND (first_visit.is_canceled OR first_visit.id_succeed_schedule IS NOT NULL) -- canceled booking
      AND first_visit.schedule_origin = 'REQUEST'
      AND date_diff (CURRENT_DATE, DATE(first_visit.ts_schedule_visit)) = 7
  ),
  second_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.id_schedule AS sk_booking,
      last_visit.last_dt_scheduling
    FROM
      datalake_visit.visit_schedules first_visit
    INNER JOIN
      last_visit
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    WHERE
      first_visit.business_context = 'SALE'
      AND NOT (first_visit.id_succeed_schedule IS NOT NULL OR first_visit.is_canceled OR first_visit.is_completed OR first_visit.is_unsuccessful) -- not canceled or realized booking
      AND first_visit.schedule_origin = 'REQUEST'
      AND date_diff (CURRENT_DATE, DATE(first_visit.ts_schedule_visit)) = 2
  ),
  third_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.id_schedule AS sk_booking,
      last_visit.last_dt_scheduling
    FROM
      datalake_visit.visit_schedules first_visit
    INNER JOIN
      last_visit
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    LEFT JOIN
      dw_sale.fact_offers o
        ON first_visit.id_visitor = o.sk_buyer
        AND o.ts_offer_submitted > first_visit.ts_schedule_visit
    WHERE
      first_visit.business_context = 'SALE'
      AND (first_visit.is_completed OR first_visit.is_unsuccessful) -- realized booking
      AND first_visit.schedule_origin = 'REQUEST'
      AND o.ts_offer_submitted IS NULL
      AND date_diff (CURRENT_DATE, DATE(first_visit.ts_schedule_visit)) = 8
  ),
  rent_visits AS (
    SELECT
      id_visitor,
      MAX(ts_visit) AS dt_visit_rent
    FROM
      datalake_visit.visits
    WHERE
      business_context = 'RENT'
      AND is_completed
    GROUP BY
      1
  ),
  union_ AS (
    SELECT
      *
    FROM
      first_
    UNION ALL
    SELECT
      *
    FROM
      second_
    UNION ALL
    SELECT
      *
    FROM
      third_
  )
SELECT
  du.nome AS customer_name,
  du.email AS customer_email,
  du.telefone_principal AS customer_phone,
  'Visita' AS campaign_step,
  'Buyer' AS customer_type,
  du.cpf AS customer_cpf,
  v.id_visitor AS id_user,
  'lost' AS campaign_type,
  'booking' AS driver_type,
  v.sk_booking AS id_driver,
  CASE
    WHEN rv.id_visitor IS NULL THEN 'Sale'
    ELSE 'Híbrido'
  END AS business_context
FROM
  union_ v
JOIN
  dw_public.dim_user du
    ON du.sk_user = v.id_visitor
LEFT JOIN
  rent_visits rv
    ON rv.id_visitor = v.id_visitor
    AND rv.dt_visit_rent BETWEEN (v.last_dt_scheduling - INTERVAL '30' DAY) AND (v.last_dt_scheduling + INTERVAL '30' DAY)
