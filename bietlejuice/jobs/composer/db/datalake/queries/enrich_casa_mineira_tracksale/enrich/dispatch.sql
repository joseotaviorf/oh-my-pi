WITH dispatches AS (
	SELECT
		id,
		JSON_TUPLE(campaign,'name','code'),
		customers,
		status,
		ts_created,
		DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
	FROM 
		datalake_casa_mineira_tracksale_clean.dispatch
),
last_updated_dispatches AS (
	SELECT
        id,
        MAX(dt_updated) AS dt_last_updated
	FROM 
		dispatches
	GROUP BY 1
)
SELECT DISTINCT
	d.id,
	CONCAT('casamineira',d.c1) AS id_campaign,
	d.c0 AS campaign_name,
	d.customers,
	d.status,
	d.ts_created,
	d.dt_updated
FROM 
	dispatches d
INNER JOIN last_updated_dispatches lud
	ON lud.id = d.id
	AND lud.dt_last_updated = d.dt_updated