WITH answers AS (
	SELECT
		id,
		CONCAT('quintoandar',id_campaign) AS id_campaign,
		campaign_name,
		name,
		identification,
		email,
		alternative_email,
		phone,
		alternative_phone,
		priority,
		type,
		status,
		nps_answer,
		CASE
		    WHEN nps_answer <= 6 THEN 'detractor'
		    WHEN nps_answer <= 8 THEN 'passive'
		    WHEN nps_answer <= 10 THEN 'promoter'
		    END AS score_category,
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
		ts_answer_sent as ts_answer_sent_utc,
		from_utc_timestamp(ts_answer_sent, 'America/Sao_Paulo') as ts_answer_sent_local,
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
	a.name,
	a.identification,
	a.email,
	a.alternative_email,
	a.phone,
	a.alternative_phone,
	a.priority,
	a.type,
	a.status,
	a.nps_answer,
	a.score_category,
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
	a.ts_answer_sent_utc,
	a.ts_answer_sent_local,
	a.dt_updated
FROM answers a
INNER JOIN last_updated_answers lua
	ON lua.id = a.id
	AND lua.dt_last_updated = a.dt_updated
