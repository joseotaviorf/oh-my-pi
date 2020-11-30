WITH ivr_paths AS (
	SELECT
		id_call AS sk_call,
		step_name AS step,
		event_type,
		digits AS answer,
		ts_created AS ts_answered
	FROM datalake_bigfone.call_ivr_paths
	WHERE event_type IN ('keypress','timeout')
	GROUP BY 1,2,3,4,5
),
path_sequence AS (
	SELECT
		sk_call,
		step,
		event_type,
		answer,
		ts_answered,
		LAG(ts_answered) OVER (PARTITION BY sk_call ORDER BY ts_answered) AS ts_last_answered
	FROM ivr_paths
)
SELECT
	sk_call,
	step,
	answer,
	event_type = 'timeout' AS is_timeout,
	UNIX_TIMESTAMP(ts_answered) - UNIX_TIMESTAMP(ts_last_answered) AS seconds_elapsed,
	ts_answered
FROM path_sequence
