select
  cast(ivr_id as integer) as ivr_id,
  selection,
  dest,
  cast(ivr_ret as integer) as ivr_ret
from datalake_raw.asterisk_ivr_entries
;