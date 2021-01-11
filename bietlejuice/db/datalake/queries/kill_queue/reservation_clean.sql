SELECT
  cast(r.id as bigint) as id,
  r.ts_created as created_at,
  r.ts_updated as updated_at,
  cast(r.version as integer) as version,
  cast(r.attempt as integer) as attempt,
  id_rent_flow as rent_flow_id,
  r.status,
  id_tenant as tenant_id,
  r.value,
  id_main as house_id,
  r.mundipagg_token,
  cast(r.is_ongoing as integer) as is_ongoing,
  r.cancellation_reason,
  r.installments
FROM datalake_kill_queue_clean_prod.reservation r
left join datalake_kill_queue_clean_prod.house h on r.id_house = h.id;
