WITH first_last_events AS (
	SELECT
		id_agent,
		MIN(ts_first_event) AS ts_first_event,
		MAX(ts_last_event) AS ts_last_event
	FROM
		datalake_bigfone_twilio.call_agents
	GROUP BY 1
)
SELECT
	ca.id_agent AS sk_call_agent,
	ca.full_name,
	ca.email,
	ca.location,
	ca.skills,
	fle.ts_first_event AS ts_created,
	fle.ts_last_event AS ts_updated,
	NOW() AS ts_load
FROM
	datalake_bigfone_twilio.call_agents ca
INNER JOIN
	first_last_events fle
		ON fle.id_agent = ca.id_agent
		AND fle.ts_last_event = ca.ts_last_event
