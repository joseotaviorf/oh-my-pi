select
  cast(id as integer) as id,
  tech,
  dial,
  devicetype,
  cast(user as integer) as user,
  description,
  cast(nullif(emergency_cid, '') as integer) as emergency_cid
from datalake_raw.asterisk_devices
;