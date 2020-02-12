select 
  rev,
  from_unixtime(revtstmp/1000) as ts_rev
from datalake_oscar_raw.revinfo