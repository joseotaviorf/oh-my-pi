WITH availability_cancelation_new_flow AS (
  SELECT
    fv.sk_visit,
    dd.date AS ts_cancelled_date,
    ct.reason AS cancelation_reason
  FROM
    dw_visit.fact_visits AS fv
  LEFT JOIN
    dw_visit.fact_visit_events AS ve
      ON fv.sk_visit = ve.sk_visit
  LEFT JOIN
    dw_visit.dim_cancellation_type AS ct
      ON ct.sk_cancellation_type = ve.sk_cancellation_type
  LEFT JOIN
    dw_public.dim_date AS dd
      ON dd.sk_date = ve.sk_event_date
  WHERE
    ct.on_behalf_of = 'SUPPLY'
    AND ct.reason IN ('PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE','PROPERTY_TEMPORARILY_UNAVAILABLE')
  GROUP BY
    ALL
),
availability_cancelation_old_flow AS (
  SELECT
    db.id_visit AS sk_visit,
    db.dt_cancel AS ts_cancelled_date,
    db.reason AS cancelation_reason
  FROM 
    dw_public.dim_booking AS db
  WHERE
    db.reason IN ('CANCELED_PROPERTY_SUSPENDED_UNAVAILABLE','CANCELED_PROPERTY_UNAVAILABLE')
),
availability_houses_unpublished_during_vb AS (
  SELECT
    db.id_visit AS sk_visit,
    fl.status_history,
    fl.ts_status_started,
    fl.ts_status_ended,
    CAST(db.dt_created AS DATE) AS dt_booking_created,
    CAST(fv.ts_visit_canceled AS DATE) AS dt_booking_booking_canceled,
    'UNPUBLISHED_DURING_BOOKING_CREATED_AND_VISIT_DATE' AS cancelation_reason
  FROM 
    dw_sale.fact_listing_status AS fl
  LEFT JOIN 
    dw_public.dim_booking AS db
      ON db.id_property = substr(fl.sk_sale_listing,0,9)
      AND CAST(fl.ts_status_started AS DATE) BETWEEN CAST(db.dt_created AS DATE) AND CAST(db.dt_scheduling AS DATE)
  LEFT JOIN 
    dw_Sale.fact_visits AS fv 
      ON fv.sk_booking = db.sk_booking
  WHERE
    db.visit_intent = 'SALE'
      AND type = 'Visita'
      AND fl.status_history != 'PUBLISHED'
),
base_visits AS (
  SELECT 
    fv.sk_visit,
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort,
    COALESCE(new_flow.cancelation_reason, old_flow.cancelation_reason, unpublished_flow.cancelation_reason) AS availability_cancelation_reason,
    CAST(fv.ts_visit AS DATE) AS ts_visit,
    CAST(fv.ts_visit_canceled AS DATE) AS ts_visit_canceled
  FROM 
    dw_sale.fact_visits AS fv 
  LEFT JOIN
    dw_sale.dim_listing AS dl 
      ON dl.sk_house = fv.sk_house
  INNER JOIN 
    dw_public.dim_date AS dd 
      ON dd.sk_date = fv.sk_visit_canceled_date
  LEFT JOIN 
    availability_cancelation_new_flow AS new_flow 
      ON new_flow.sk_visit = fv.sk_visit
  LEFT JOIN 
    availability_cancelation_old_flow AS old_flow 
      ON old_flow.sk_visit = fv.sk_visit
  LEFT JOIN 
    availability_houses_unpublished_during_vb AS unpublished_flow
      ON unpublished_flow.sk_visit = fv.sk_visit
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON dl.sk_company_hubspot = cc.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
  GROUP BY
    ALL
),
count_visits AS (
  SELECT 
    CAST(DATE_TRUNC('week', bv.ts_visit) AS DATE) AS week,
    bv.partner_name,
    bv.company_cluster,
    bv.is_decola_community,
    bv.is_decola_current_cohort,
    COUNT(DISTINCT bv.sk_visit) AS total_visits_sheduled,
    COUNT(DISTINCT
          CASE
            WHEN bv.availability_cancelation_reason IS NOT NULL THEN bv.sk_visit
          END) AS total_visits_unavailable
  FROM
    base_visits AS bv
  GROUP BY
    ALL
)
SELECT 
  cv.week AS dt_week,
  cv.partner_name,
  cv.company_cluster,
  cv.is_decola_community,
  cv.is_decola_current_cohort,
  SUM(cv2.total_visits_sheduled) AS total_visits_sheduled,
  SUM(cv2.total_visits_unavailable) AS total_visits_unavailable,
  SUM(cv2.total_visits_unavailable) / SUM(cv2.total_visits_sheduled) AS share_visits_unavailable
FROM
  count_visits AS cv
LEFT JOIN
  count_visits AS cv2
    ON cv2.partner_name = cv.partner_name
    AND cv.company_cluster = cv2.company_cluster
    AND cv2.week BETWEEN DATE_ADD(cv.week, -14) AND cv.week 
GROUP BY
  ALL