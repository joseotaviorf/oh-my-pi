WITH
  visit_rent_flow AS (
    SELECT
      frde.sk_visit,
      LOWER(dret.abbreviation) AS event_code,
      'RENT' AS business_context,
      MIN(frde.ts_event) AS ts_first_event,
      MAX(frde.ts_event) AS ts_last_event
    FROM
      dw_rent.fact_rent_demand_events AS frde
    INNER JOIN
      dw_rent.dim_rent_event_type AS dret
        ON dret.sk_event_type = frde.sk_event_type
    WHERE
      LOWER(dret.abbreviation) IN ('os','oa','cs')
      AND ts_event::date >= '2024-01-01'
    GROUP BY 1, 2, 3
  )
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renaming
  v.id_visit AS sk_visit,
  v.id_visit AS id_visit,
  v.code AS cd_visit,
  v.visit_origin,
  v.visit_origin_description,
  sv.business_unit,
  v.dt_visit AS day_visit,
  v.slot,
  v.slot_count,
  v.type,
  v.status,
  v.computed_status,
  v.behavior,
  v.booking_type,
  v.business_context,
  v.business_model,
  v.cancellation_reason,
  v.cancellation_on_behalf_of,
  v.cancellation_channel,
  v.cancellation_author_role,
  v.method AS entry_method,
  v.entry_model_type AS entry_method_type,
  v.visit_model,
  v.visit_schedule_type,
  v.visit_request_channel,
  v.is_fixed_agent AS is_visit_with_fixed_agent,
  v.is_confirmed AS is_visit_confirmed,
  v.is_completed AS is_visit_completed,
  v.is_canceled AS is_visit_canceled,
  v.is_unsuccessful AS is_visit_unsuccessful,
  v.is_reschedule AS is_visit_reschedule,
  v.is_registered_by_agent AS is_visit_registered_by_agent,
  v.is_cancelled_by_expiration AS is_visit_cancelled_by_expiration,
  v.is_stalled AS is_visit_stalled,
  v.has_fup_collected AS has_visit_fup_collected,
  v.has_finisher_status AS has_visit_finisher_status,
  v.has_more_one_agent AS has_visit_more_one_agent,
  IF(os.ts_first_event IS NOT NULL, TRUE, FALSE) AS has_offer_submitted,
  IF(oa.ts_first_event IS NOT NULL, TRUE, FALSE) AS has_offer_accepted,
  IF(cs.ts_first_event IS NOT NULL, TRUE, FALSE) AS has_contract_signed,
  IF(v.ts_created < os.ts_first_event, TRUE, FALSE) AS has_offer_submitted_after_visit_creation,
  IF(v.ts_created < oa.ts_first_event, TRUE, FALSE) AS has_offer_accepted_after_visit_creation,
  IF(v.ts_created < cs.ts_first_event, TRUE, FALSE) AS has_contract_signed_after_visit_creation,
  v.ts_created AS dt_created,
  v.ts_updated AS dt_updated,
  v.ts_visit,
  v.ts_visit_requested,
  v.ts_visit_first_confirmed,
  v.ts_visit_last_confirmed,
  v.ts_visit_first_rescheduled,
  v.ts_visit_rescheduled AS ts_visit_last_rescheduled,
  v.ts_visit_canceled,
  v.ts_visit_unsuccessful,
  v.ts_visit_done,
  v.ts_visit_fup_collected,
  v.ts_visit_stalled,
  v.ts_first_visit,
  os.ts_first_event AS ts_first_offer_submitted,
  oa.ts_first_event AS ts_first_offer_accepted,
  cs.ts_first_event AS ts_first_contract_signed,
  NOW() AS ts_load
FROM
  datalake_visit.visits AS v
LEFT JOIN
  datalake_sale_visit_hubs.sale_visit_hubs AS sv
    ON sv.id_booking = v.id_visit
LEFT JOIN
  visit_rent_flow AS os
    ON v.id_visit = os.sk_visit
    AND v.business_context = os.business_context
    AND os.event_code = 'os'
LEFT JOIN
  visit_rent_flow AS oa
    ON v.id_visit = oa.sk_visit
    AND v.business_context = oa.business_context
    AND oa.event_code = 'oa'
LEFT JOIN
  visit_rent_flow AS cs
    ON v.id_visit = cs.sk_visit
    AND v.business_context = cs.business_context
    AND cs.event_code = 'cs'
