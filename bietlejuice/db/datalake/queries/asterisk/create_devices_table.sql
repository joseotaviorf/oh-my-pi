select
  id,
  tech,
  dial,
  devicetype,
  "user",
  description,
  nullif(emergency_cid, '') as emergency_cid
from datalake_raw.asterisk_devices
;