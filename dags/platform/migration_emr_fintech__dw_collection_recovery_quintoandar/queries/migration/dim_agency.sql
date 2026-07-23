SELECT
  id_agency AS sk_agency,
  id_main_agency AS sk_main_agency,
  id_agencies_group,
  main_agency_name,
  main_agency_type,
  agencies_name_group,
  ts_start,
  NOW() AS ts_load
FROM datalake_cyber.agencies
