select
  id,
  -- Adding milliseconds to ts_revision default timestamp format
  from_unixtime(ts_revision/1000) 
    + (ts_revision % 1000) * interval 1 milliseconds as ts_revision,
  id_user,
reason
from 
  datalake_ebdb_clean.user_revision_entity