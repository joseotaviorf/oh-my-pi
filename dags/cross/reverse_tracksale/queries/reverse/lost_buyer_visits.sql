WITH
  last_visit AS (
    SELECT
      id_visitor,
      MAX(dt_scheduling) last_dt_scheduling
    FROM
      dw_public.dim_booking
    WHERE
      dt_scheduling >= CURRENT_DATE - INTERVAL '30' DAY
    GROUP BY
      1
  ),
  first_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.sk_booking,
      last_visit.last_dt_scheduling
    FROM
      dw_public.dim_booking first_visit
    INNER JOIN 
      last_visit 
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.dt_scheduling
    LEFT JOIN 
      dw_public.dim_booking second_visit 
        ON first_visit.id_visitor = second_visit.id_visitor
        AND second_visit.dt_scheduling > first_visit.dt_scheduling
    WHERE
      first_visit.visit_intent = 'SALE'
      AND first_visit.type = 'Visita'
      AND first_visit.country_code = 'BR'
      AND first_visit.status = 'Cancelado'
      AND first_visit.rescheduled_from_id IS NULL
      AND second_visit.dt_scheduling IS NULL
      AND date_diff (CURRENT_DATE, DATE(first_visit.dt_scheduling)) = 7
  ),
  second_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.sk_booking,
      last_visit.last_dt_scheduling
    FROM
      dw_public.dim_booking first_visit
    INNER JOIN 
      last_visit 
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.dt_scheduling
    WHERE
      first_visit.visit_intent = 'SALE'
      AND first_visit.type = 'Visita'
      AND first_visit.country_code = 'BR'
      AND first_visit.status NOT IN ('Cancelado', 'Realizado')
      AND rescheduled_from_id IS NULL
      AND date_diff (CURRENT_DATE, DATE(first_visit.dt_scheduling)) = 2
  ),
  third_ AS (
    SELECT
      first_visit.id_visitor,
      first_visit.sk_booking,
      last_visit.last_dt_scheduling
    FROM
      dw_public.dim_booking first_visit
    INNER JOIN 
      last_visit 
        ON last_visit.id_visitor = first_visit.id_visitor
        AND last_visit.last_dt_scheduling = first_visit.dt_scheduling
    LEFT JOIN 
      dw_sale.fact_offers o 
        ON first_visit.id_visitor = o.sk_buyer
        AND o.ts_offer_submitted > first_visit.dt_scheduling
    WHERE
      first_visit.visit_intent = 'SALE'
      AND first_visit.type = 'Visita'
      AND first_visit.country_code = 'BR'
      AND first_visit.status IN ('Realizado')
      AND rescheduled_from_id IS NULL
      AND o.ts_offer_submitted IS NULL
      AND date_diff (CURRENT_DATE, DATE(first_visit.dt_scheduling)) = 8
  ),
  rent_visits AS (
    SELECT
      id_visitor,
      MAX(dt_scheduling) AS dt_visit_rent
    FROM
      dw_public.dim_booking
    WHERE
      visit_intent = 'RENT'
      AND TYPE = 'Visita'
      AND visit_follow_up = 'VaiNegociar'
      AND country_code = 'BR'
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