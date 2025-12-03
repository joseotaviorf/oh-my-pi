SELECT DISTINCT
  sk_disability,
  documented_name_active AS documented_name,
  self_declared_name,
  has_documented_active_disability AS has_documented_disability,
  has_self_declared_disability,
  has_documented_pending_disability AS has_pending_documented_disability,
  NOW() AS ts_load
FROM
  datalake_hr_system.disability