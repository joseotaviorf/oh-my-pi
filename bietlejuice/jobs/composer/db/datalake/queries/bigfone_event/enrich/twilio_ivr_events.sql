WITH ivr_events AS (
	SELECT
		id,
		GET_JSON_OBJECT(metadata,'$.event_data.Sid') AS id_event,
		event,
		metadata,
		ts_created_local,
		ts_received_local
	FROM datalake_bigfone_clean.events
	WHERE provider = 'twilio'
		AND GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'IVR Events'
),
max_index AS (
	SELECT
		id_event,
		MAX(id) AS id_max
	FROM ivr_events
	GROUP BY 1
)
SELECT
	ie.id,
	ie.id_event,
	ie.event,
	ie.metadata,
	ie.ts_created_local,
	ie.ts_received_local
FROM ivr_events ie
INNER JOIN max_index mi
	ON mi.id_max = ie.id