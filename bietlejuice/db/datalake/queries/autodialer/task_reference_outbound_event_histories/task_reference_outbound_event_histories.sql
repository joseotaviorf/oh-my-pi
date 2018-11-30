select
	_id as id,
	_class as class,
	createdat as created_at,
	outbound_events,
	taskid as task_id,
	updatedat as updated_at
from datalake_raw.task_reference_outbound_event_histories
CROSS JOIN UNNEST(taskreferenceoutboundevents) as t(outbound_events)