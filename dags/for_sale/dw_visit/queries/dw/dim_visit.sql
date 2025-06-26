SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renaming
  v.id_visit AS sk_visit,
  v.id_visit AS id_visit,
  v.code AS cd_visit,
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
  v.is_fixed_agent AS is_visit_with_fixed_agent,
  v.ts_created AS dt_created,
  v.ts_updated AS dt_updated,
  v.ts_visit_requested,
  v.ts_visit_canceled,
  v.ts_visit_unsuccessful,
  v.ts_visit_done,
  v.ts_visit_fup_collected,
  NOW() AS ts_load
FROM
  datalake_visit.visits AS v
LEFT JOIN
  datalake_sale_visit_hubs.sale_visit_hubs AS sv
    ON sv.id_booking = v.id_visit
