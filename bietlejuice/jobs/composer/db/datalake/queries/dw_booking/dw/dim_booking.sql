-- removing duplicates rows due to CASE difference in the taxonomy
WITH taxonomy_demand AS (
  WITH taxonomy_min_ids AS (
      SELECT
          MIN(CAST(id AS BIGINT)) AS id
      FROM
        datalake_gsheets_clean.taxonomy_demand
      GROUP BY
          LOWER(app_type),
          LOWER(utm_source),
          LOWER(utm_medium),
          LOWER(branded),
          LOWER(first_update_source),
          flg_via_reschedule
    )
    SELECT
      CAST(td.id AS BIGINT) AS id,
      td.app_type,
      td.utm_source,
      td.utm_medium,
      td.branded,
      td.first_update_source,
      CAST(td.flg_via_reschedule AS BOOLEAN) AS flg_via_reschedule,
      td.category AS mkt_category,
      td.flow AS mkt_flow,
      td.completion AS mkt_completion,
      td.channel AS mkt_channel,
      td.medium AS mkt_medium,
      td.origin AS mkt_origin,
      td.source AS mkt_source,
      td.platform AS mkt_platform
    FROM
      datalake_gsheets_clean.taxonomy_demand AS td
    JOIN
      taxonomy_min_ids AS td_min
        ON td.id = td_min.id
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  CAST(b.id AS INT) AS sk_booking,
  COALESCE(td.id, -1) AS sk_rent_flow_taxonomy,
  CAST(b.id AS INT) AS id_booking,
  b.id_visitor,
  b.id_visit,
  b.id_house AS id_property,
  b.id_agent,
  b.id_attendant,
  b.id_rent_flow AS id_rental_flow,
  CAST(b.id_rescheduled_booking AS INT) AS rescheduled_from_id,
  b.country_code,
  b.visit_intent,
  b.buyer_intention,
  b.type,
  CAST(b.is_visit_completed AS VARCHAR(100)) AS confirmed,
  CAST(b.is_visit_performed AS VARCHAR(100)) AS performed,
  CAST(b.is_closed AS VARCHAR(100)) AS closed,
  b.has_reschedule AS is_rescheduled,
  b.is_via_reschedule AS flg_via_reschedule,
  b.is_first_booking_auto,
  COALESCE(src.is_branded, false) AS flg_branded,
  CAST(CAST(b.has_tenant_attended AS INT) AS VARCHAR(255)) AS visitor_arrived,
  CAST(CAST(b.has_agent_attended AS INT) AS VARCHAR(255)) AS agent_arrived,
  -- TODO [ODS] review this rule
  CAST(COALESCE(b.has_owner_arrived, true) AS VARCHAR(255)) AS owner_arrived,
  CAST(CAST(b.is_entrance_successful AS INT) AS VARCHAR(255)) AS successful_entrance,
  b.is_visit_created_from_app,
  b.is_visit_last_updated_from_app,
  b.visit_fup AS visit_follow_up,
  b.status,
  b.slot_day AS slot_dia,
  SUBSTRING(b.last_status_change_reason, 1, 200) AS reason,
  b.cancellation_reason,
  b.cancellation_reason_category,
  b.reason_category,
  b.responsible,
  b.last_update_source,
  b.first_update_source,
  b.tenant_absence_reason AS visitor_missing_reason,
  b.agent_absence_reason AS agent_missing_reason,
  b.owner_missing_reason,
  b.troublesome_entrance_problem AS troublesome_entrance,
  b.checkin_status,
  b.user_sale_booking_creator,
  b.partner_3p_supply,
  b.partner_3p_demand,
  src.app_type,
  -- TODO [ODS] review this rule
  COALESCE(src.media_source, "Unknown") AS media_source,
  src.adjust_network,
  src.utm_source,
  src.utm_medium,
  src.utm_campaign,
  src.utm_content,
  src.utm_term,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_category END AS mkt_category,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_flow END AS mkt_flow,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_completion END AS mkt_completion,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_origin END AS mkt_origin,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_channel END AS mkt_channel,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_medium END AS mkt_medium,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_source END AS mkt_source,
  CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_platform END AS mkt_platform,
  b.is_3p_supply,
  b.is_3p_demand,
  b.ts_visit_fup AS dt_visit_follow_up,
  b.ts_visit_follow_up_local_tz AS ts_visit_follow_up_local,
  b.ts_booking_utc AS dt_scheduling,
  b.ts_booking_local_tz AS ts_scheduling_local,
  b.ts_first_canceled AS dt_cancel,
  b.ts_first_canceled_local_tz AS ts_cancel_local,
  b.ts_created AS dt_created,
  b.ts_created_local_tz AS ts_created_local,
  b.ts_updated AS dt_updated,
  NOW() AS ts_load
FROM
  datalake_booking.booking AS b
LEFT JOIN
  datalake_ebdb_clean.visit AS v
    ON b.id_visit = v.id
LEFT JOIN
  datalake_amplitude_visit.amplitude_visit AS src
    ON v.code = src.id_visit
LEFT JOIN
  taxonomy_demand AS td
    ON LOWER(COALESCE(td.app_type, '')) = LOWER(COALESCE(src.app_type, ''))
    AND LOWER(COALESCE(td.utm_source, '')) = LOWER(COALESCE(src.utm_source, ''))
    AND LOWER(COALESCE(td.utm_medium, '')) = LOWER(COALESCE(src.utm_medium, ''))
    -- TODO [ODS] use flag is_branded FROM datalake_amplitude_visit.amplitude_visit
    AND LOWER(COALESCE(td.branded, '')) = LOWER(COALESCE(src.branded, 'Outro'))
    AND LOWER(COALESCE(td.first_update_source, '')) = LOWER(COALESCE(b.first_update_source, ''))
    AND COALESCE(td.flg_via_reschedule, FALSE) = COALESCE(b.is_via_reschedule, FALSE)
    
