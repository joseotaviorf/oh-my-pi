select
  cast(id as integer) as id,
  keyword,
  data,
  cast(flags as integer) as flags
from datalake_raw.asterisk_queues_details
;