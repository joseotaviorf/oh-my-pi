select 
   id,
   user_id as id_user,
   -- timestamp column is in milliseconds 
   from_unixtime(`timestamp`/1000, 'yyyy-MM-dd HH:mm:ss') as ts_revised
from datalake_insider_raw.user_revision_entity