select
  id,
  id_user,
  reason,
  -- Adding milliseconds to ts_revision default timestamp format
  cast(
    from_unixtime(ts_revision/1000) +
    (ts_revision % 1000) * interval 1 milliseconds
  as timestamp) as ts_revision
from 
  datalake_ebdb_clean.user_revision_entity