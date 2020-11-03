WITH flex_events AS (
	SELECT
		id,
		GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
		event,
		metadata,
		ts_created_local,
		ts_received_local
	FROM datalake_bigfone_clean.events
	WHERE provider = 'twilio'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
),
max_index AS (
	SELECT
		id_event,
		MAX(id) AS id_max
	FROM flex_events
	GROUP BY 1
)
SELECT
	fe.id,
	fe.id_event,
	fe.event,
	fe.metadata,
	fe.ts_created_local,
	fe.ts_received_local
FROM flex_events fe
INNER JOIN max_index mi
	ON mi.id_max = fe.id