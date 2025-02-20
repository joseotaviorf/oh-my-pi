SELECT
  id,
  repair_request_id AS id_repair_request,
  approved_by AS id_approver,
  registered_by AS id_budget_sender,
  status,
  total_price,
  service_provider,
  allowed_service_provider_info_sharing AS is_allowed_service_provider_info_sharing,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_repairs_test_raw.repair_request_budget