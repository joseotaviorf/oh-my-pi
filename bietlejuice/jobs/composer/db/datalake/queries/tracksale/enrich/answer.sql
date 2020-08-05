WITH answers AS (
	SELECT
		id,
		id_campaign,
		campaign_name,
		identification,
		email,
		alternative_email,
		phone,
		alternative_phone,
		priority,
		type,
		status,
		nps_answer,
		last_nps_answer,
		nps_comment,
		justifications,
		lot_code,
		assignee,
		tags,
		categories,
		seconds_spent_answering,
		ts_deadline,
		ts_reminder,
		ts_dispatch,
		ts_answer_sent,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
	FROM datalake_tracksale_clean.answer
),
last_updated_answers AS (
	SELECT
		id,
		MAX(dt_updated) AS dt_last_updated
	FROM answers
	GROUP BY 1
)
SELECT
	a.id,
	a.id_campaign,
	a.campaign_name,
	a.identification,
	a.email,
	a.alternative_email,
	a.phone,
	a.alternative_phone,
	a.priority,
	a.type,
	a.status,
	a.nps_answer,
	a.last_nps_answer,
	a.nps_comment,
	a.justifications,
	a.lot_code,
	a.assignee,
	a.tags,
	a.categories,
	a.seconds_spent_answering,
	a.ts_deadline,
	a.ts_reminder,
	a.ts_dispatch,
	a.ts_answer_sent,
	a.dt_updated
FROM answers a
INNER JOIN last_updated_answers lua
	ON lua.id = a.id
	AND lua.dt_last_updated = a.dt_updated