WITH i_full AS
(
SELECT 
	DATE(TO_TIMESTAMP('{0}', 'YYYY-MM-DD HH24:MI:SS'))  AS dt,
	t_out.dadosagente_id,
    t_out.regiao_id,
    aux.region_code,
    aux.region_code_deprecated
FROM
	public.agent_region_hist t_out
LEFT join
	files.aux_regiao aux ON aux.id = t_out.regiao_id
WHERE
	TO_TIMESTAMP('{0}', 'YYYY-MM-DD HH24:MI:SS') BETWEEN dt_start AND dt_end
	AND TO_TIMESTAMP('{0}', 'YYYY-MM-DD HH24:MI:SS') > TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS')  -- limit date, where aud started to be implemented
ORDER BY 2, 4
)
, i_union AS
(
SELECT
	*
 FROM i_full
UNION ALL
SELECT DISTINCT
	ag.available_date AS dt,
	us.dados_agente_id AS dadosagente_id,
	region_id AS regiao_id,
	aux.region_code,
	aux.region_code_deprecated
FROM
	public.agents_schedule ag
LEFT JOIN public.usuario us
	ON us.id = ag.agent_user_id
LEFT JOIN files.aux_regiao aux
	ON aux.id = ag.region_id
WHERE
	ag.region_id IS NOT NULL
	AND us.dados_agente_id IS NOT NULL
	AND	ag.available_date = DATE(TO_TIMESTAMP('{0}', 'YYYY-MM-DD HH24:MI:SS'))
	AND DATE(TO_TIMESTAMP('{0}', 'YYYY-MM-DD HH24:MI:SS')) <= DATE(TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS'))  -- limit date, where aud started to be implemented
)
, i_group AS
(SELECT
	i_union.dt,
	i_union.dadosagente_id,
	i_union.region_code,
	count(i_union.region_code) AS times,
	RANK() OVER (PARTITION BY i_union.dadosagente_id ORDER BY count(i_union.region_code) DESC, i_union.region_code ASC) ranking
FROM i_union
	GROUP BY
	i_union.dt,
	i_union.dadosagente_id,
	i_union.region_code)
, i_group_new AS
(SELECT
	i_union.dt,
	i_union.dadosagente_id,
	i_union.region_code_deprecated,
	count(i_union.region_code_deprecated) AS times,
	RANK() OVER (PARTITION BY i_union.dadosagente_id ORDER BY count(i_union.region_code_deprecated) DESC, i_union.region_code_deprecated ASC) ranking
FROM i_union
	GROUP BY
	i_union.dt,
	i_union.dadosagente_id,
	i_union.region_code_deprecated)
SELECT
	g.dt,
	g.dadosagente_id,
	list.regions,
	g.region_code AS area,
	(
	SELECT r2.region_code
		FROM i_group r2
	WHERE r2.dadosagente_id = g.dadosagente_id
			AND r2.dt = g.dt
			AND r2.ranking = 2
			AND r2.times = g.times
	 ) AS secondary_area,
	 gn.region_code_deprecated as area_deprecated,
	 (
        SELECT ng2.region_code_deprecated
            FROM i_group_new ng2
        WHERE ng2.dadosagente_id = g.dadosagente_id
                AND ng2.dt = g.dt
                AND ng2.ranking = 2
                AND ng2.times = g.times
	 ) AS secondary_area_deprecated
FROM i_group g
LEFT JOIN
	(SELECT
		arh.dt,
		arh.dadosagente_id,
	    array_agg(arh.regiao_id ORDER BY arh.regiao_id) AS regions
	 FROM
	 	i_union arh
	 GROUP BY
	 	arh.dt,
		arh.dadosagente_id
	) list
    ON list.dt = g.dt AND list.dadosagente_id = g.dadosagente_id
LEFT JOIN
    i_group_new gn
    ON gn.dt = g.dt AND gn.dadosagente_id = g.dadosagente_id AND gn.ranking = 1
WHERE g.ranking = 1;