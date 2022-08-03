SELECT
  id_suspicion AS sk_suspicion,
  name,
  CURRENT_TIMESTAMP AS ts_load
FROM
  datalake_gsheets_clean.pld_suspicion_list