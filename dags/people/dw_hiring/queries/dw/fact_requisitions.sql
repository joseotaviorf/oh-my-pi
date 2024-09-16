SELECT
  erd.sk_requisition,
  COALESCE(MD5(CAST(erd.id_candidate AS BINARY)), '-1') AS sk_candidate,
  COALESCE(DATE_FORMAT(erd.dt_created, 'yyyyMMdd'), '-1') AS sk_created_date,
  COALESCE(DATE_FORMAT(erd.dt_opened, 'yyyyMMdd'), '-1') AS sk_opened_date,
  COALESCE(DATE_FORMAT(erd.dt_filled, 'yyyyMMdd'), '-1') AS sk_filled_date,
  COALESCE(erd.sk_owner, '-1') AS sk_owner,
  COALESCE(erd.sk_hiring_manager, '-1') AS sk_hiring_manager,
  COALESCE(erd.sk_business_partner, '-1') AS sk_business_partner,
  COALESCE(cc.id_cost_center, '-1') AS sk_cost_center,
  erd.is_confidential,
  erd.days_on_hold,
  erd.days_open,
  erd.days_queue,
  erd.days_sla,
  erd.days_delay,
  NOW() AS ts_load
FROM
  datalake_workable.requisition_details AS erd
LEFT JOIN
  datalake_workable.cost_center AS cc
    ON erd.cost_center = cc.cost_center_workable