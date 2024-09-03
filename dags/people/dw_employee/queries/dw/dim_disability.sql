SELECT DISTINCT
  sk_disability,
  disability_category_code_wdoc,
  disability_category_wdoc,
  disability_status_wdoc,
  disability_self_declaration_code,
  disability_self_declaration_description,
  NOW() AS ts_load
FROM datalake_hr_system.disability