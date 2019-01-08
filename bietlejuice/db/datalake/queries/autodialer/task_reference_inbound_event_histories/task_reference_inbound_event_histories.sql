select
	_id as id,
	_class as class,
	createdat as created_at,
	inbound_events,
	taskid as task_id,
	updatedat as updated_at
from datalake_raw.autodialer_task_reference_inbound_event_histories
CROSS JOIN UNNEST(inboundevents) as t(inbound_events)