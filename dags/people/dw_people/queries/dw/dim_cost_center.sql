SELECT
  id_organization AS sk_cost_center,
  name AS cost_center_name,
  codigo_dff AS cost_center_code,
  COALESCE(business, '-1') AS business,
  COALESCE(product, '-1') AS product,
  COALESCE(vertical, '-1') AS vertical,
  COALESCE(vice_presidency, '-1') AS vice_presidency,
  COALESCE(DIRECTORY, '-1') AS DIRECTORY,
  COALESCE(sub_directory, '-1') AS sub_directory,
  status,
  dt_effective_start,
  dt_effective_end,
  NOW() AS ts_load
FROM
  datalake_hr_system_clean.organizations
WHERE
  classification_code = 'DEPARTMENT'