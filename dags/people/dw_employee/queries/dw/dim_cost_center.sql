SELECT
  o.id_organization AS sk_cost_center,
  e.id_period_of_service AS sk_business_partner_assignment,
  e.id_person AS sk_business_partner,
  o.name AS cost_center_name,
  o.codigo_dff AS cost_center_code,
  COALESCE(o.business, '-1') AS business,
  COALESCE(o.product, '-1') AS product,
  COALESCE(o.brand, '-1') AS brand,
  COALESCE(o.vertical, '-1') AS vertical,
  COALESCE(o.structure, '-1') AS structure,
  COALESCE(o.team, '-1') AS team,
  COALESCE(o.chapter, '-1') AS chapter,
  COALESCE(o.line, '-1') AS line,
  COALESCE(o.owner_leadership_layer_1_name, '-1') AS owner_leadership_layer_1_name,
  COALESCE(o.owner_leadership_layer_2_name, '-1') AS owner_leadership_layer_2_name,
  COALESCE(o.owner_leadership_layer_3_name, '-1') AS owner_leadership_layer_3_name,
  COALESCE(o.headcount_type, '-1') AS headcount_type,
  o.status,
  o.dt_effective_start,
  o.dt_effective_end,
  NOW () AS ts_load
FROM
  datalake_hr_system_clean.organizations AS o
LEFT JOIN 
  datalake_hr_system_clean.areas_of_responsibility AS r 
    ON o.codigo_dff = r.template_code
    AND r.active_status = 'A'
LEFT JOIN 
  datalake_hr_system.employee_ids AS e 
    ON e.id_assignment = r.id_assignment
WHERE
  o.classification_code = 'DEPARTMENT'
