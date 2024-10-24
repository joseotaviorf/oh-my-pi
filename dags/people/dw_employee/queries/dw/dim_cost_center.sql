SELECT
  o.id_organization AS sk_cost_center,
  e.id_period_of_service AS sk_business_partner_assignment,
  e.id_person AS sk_business_partner,
  o.name AS cost_center_name,
  o.codigo_dff AS cost_center_code,
  COALESCE(o.business, '-1') AS business,
  COALESCE(o.product, '-1') AS product,
  COALESCE(o.vertical, '-1') AS vertical,
  COALESCE(o.vice_presidency, '-1') AS vice_presidency,
  COALESCE(o.directorate, '-1') AS directorate,
  COALESCE(o.subdirectorate, '-1') AS subdirectorate,
  o.status,
  o.dt_effective_start AS dt_started,
  o.dt_effective_end AS dt_ended,
  NOW() AS ts_loaded
FROM
  datalake_hr_system_clean.organizations AS o
LEFT JOIN
  datalake_hr_system_clean.areas_of_responsibility AS r
    ON o.codigo_dff = r.template_code
LEFT JOIN
  datalake_hr_system.employee_ids AS e
    ON e.id_assignment = r.id_assignment
WHERE
  o.classification_code = 'DEPARTMENT'
  AND r.active_status = 'A'
