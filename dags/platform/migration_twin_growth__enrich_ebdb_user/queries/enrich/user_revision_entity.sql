SELECT
  ure.id,
  ure.id_user,
  COALESCE(u.country_code, 'Undefined') AS country_code,
  ure.reason,
  -- Adding milliseconds to ts_revision default timestamp format
  DATEADD(MILLISECOND, ure.ts_revision % 1000, TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000))) AS ts_revision
FROM 
  datalake_ebdb_clean.user_revision_entity AS ure
LEFT JOIN
  datalake_ebdb_country.user AS u
    ON u.id_user = ure.id_user