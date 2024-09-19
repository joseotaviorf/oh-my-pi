SELECT
  vse.id_visit_status_events AS sk_event,
  vse.id_visit_status_log AS sk_visits_status_log,
  det.sk_event_type AS sk_event_type,
  pe.id_visit_status_events AS sk_previous_event,
  p_det.sk_event_type AS sk_previous_event_type,
  vse.id_visit AS sk_visit,
  vse.id_schedule AS sk_schedule,
  vse.id_author_user AS sk_author,
  at.sk_author_type AS sk_author_type,
  vse.id_company_demand AS sk_company_demand,
  vse.id_company_supply AS sk_company_supply,
  vse.id_agent AS sk_agent,
  lh.id_region AS sk_region,
  vse.id_house AS sk_house,
  vse.id_house_listing AS sk_house_listing,
  vse.id_rent_flow AS sk_rent_flow,
  vse.id_sale_flow AS sk_sale_flow,
  -1 AS sk_entrance_type,
  dct.sk_cancellation_type AS sk_cancellation_type,
  REPLACE(CAST(DATE(vse.ts_event_created) AS STRING), '-', '') AS sk_event_date,
  vse.country_code,
  vse.ranking,
  DATEDIFF(MINUTE,vse.ts_event_created , pe.ts_event_created) AS minutes_between_last_event,
  DATEDIFF(HOUR,vse.ts_event_created , pe.ts_event_created) AS hours_between_last_event,
  NOW() AS ts_load
FROM
  datalake_visit.visit_status_events AS vse
INNER JOIN
  dw_visit.dim_event_type AS det
    ON vse.event_type = det.event_name
LEFT JOIN
  datalake_visit.visit_status_events AS pe
    ON vse.id_visit = pe.id_visit
    AND vse.ranking = (pe.ranking)+1
LEFT JOIN
  dw_visit.dim_event_type AS p_det
    ON pe.event_type = p_det.event_name
INNER JOIN
  dw_visit.dim_author_type AS at
    ON vse.author_user_role = at.author_user_role
    AND vse.author_user_type = at.author_type
    AND vse.channel = at.channel
    AND vse.on_behalf_of = at.on_behalf_of
INNER JOIN
  datalake_ebdb_listing.house AS lh
    ON vse.id_house = lh.id
LEFT JOIN
  datalake_ebdb_clean.visit_cancellation_details AS vcd
  ON vse.id_cancellation_detail = vcd.id
LEFT JOIN
  dw_visit.dim_cancellation_type AS dct
  ON vcd.reason = dct.reason
  AND vcd.on_behalf_of = dct.on_behalf_of
