SELECT
  id,
  id_user,
  reason,
  -- Adding milliseconds to ts_revision default timestamp format
  DATEADD(MILLISECOND, ts_revision % 1000, TIMESTAMP(FROM_UNIXTIME(ts_revision/1000))) AS ts_revision
FROM 
  datalake_ebdb_clean.user_revision_entity