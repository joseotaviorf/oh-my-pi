select
	_id as id,
	_class as class,
	createdat as created_at,
	cast(taskreferenceoutboundevents as varchar) as outbound_events,
	taskid as task_id,
	updatedat as updated_at
from datalake_raw.task_reference_outbound_event_histories