select
  cast(cxpanel_queue_id as integer) as cxpanel_queue_id,
  cast(queue_id as integer) as queue_id,
  display_name,
  cast(add_queue as integer) as add_queue
from datalake_raw.asterisk_cxpanel_queues
;