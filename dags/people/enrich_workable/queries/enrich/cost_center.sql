WITH workable_cost_center AS (
  SELECT DISTINCT
    cost_center,
    TRIM(SPLIT(cost_center, '-')[0]) AS code
  FROM
    datalake_workable.custom_fields
  WHERE
    cost_center IS NOT NULL
  )
SELECT DISTINCT
  o.id_organization AS id_cost_center,
  o.name AS cost_center_name_pin,
  wcc.cost_center AS cost_center_workable,
  wcc.code AS cost_center_code_workable,
  o.codigo_dff AS cost_center_code,
  NOW() AS ts_load
FROM
  workable_cost_center AS wcc
INNER JOIN 
  datalake_hr_system_clean.organizations AS o 
    ON wcc.code = o.codigo_dff
WHERE
  cost_center IS NOT NULL
QUALIFY
  o.ts_last_update = MAX(o.ts_last_update) OVER (PARTITION BY o.codigo_dff, o.status)
  AND o.dt_effective_start = MAX(o.dt_effective_start) OVER (PARTITION BY o.codigo_dff)