WITH i_full AS
(
SELECT 
	DATE(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS'))  AS dt,
	t_out.dadosagente_id,
    t_out.regiao_id,
    aux."Nossa nomenclatura"
FROM
	public.agent_region_hist t_out
LEFT join
	files.aux_regiao aux ON aux.id = t_out.regiao_id
WHERE
	TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS') BETWEEN dt_start AND dt_end
	AND TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS') > TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS')  -- limit date, where aud started to be implemented
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
	aux."Nossa nomenclatura"
FROM
	public.agents_schedule ag
LEFT JOIN public.usuario us
	ON us.id = ag.agent_user_id
LEFT JOIN files.aux_regiao aux
	ON aux.id = ag.region_id
WHERE
	ag.region_id IS NOT NULL
	AND us.dados_agente_id IS NOT NULL
	AND	ag.available_date = DATE(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS'))
	AND DATE(TO_TIMESTAMP('{}', 'YYYY-MM-DD HH24:MI:SS')) <= DATE(TO_TIMESTAMP('2018-01-31 00:00:00', 'YYYY-MM-DD HH24:MI:SS'))  -- limit date, where aud started to be implemented
)
, i_group AS
(SELECT
	i_union.dt,
	i_union.dadosagente_id,
	i_union."Nossa nomenclatura",
	count(i_union."Nossa nomenclatura") AS times,
	RANK() OVER (PARTITION BY i_union.dadosagente_id ORDER BY count(i_union."Nossa nomenclatura") DESC, i_union."Nossa nomenclatura" ASC) ranking
FROM i_union
	GROUP BY
	i_union.dt,
	i_union.dadosagente_id,
	i_union."Nossa nomenclatura")
SELECT
	g.dt,
	g.dadosagente_id,
	list.regions,
	g."Nossa nomenclatura" AS area,
	(
	SELECT r2."Nossa nomenclatura"
		FROM i_group r2
	WHERE r2.dadosagente_id = g.dadosagente_id
			AND r2.dt = g.dt
			AND r2.ranking = 2
			AND r2.times = g.times
	 ) AS secondary_area
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
WHERE ranking = 1;