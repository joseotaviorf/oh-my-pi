SELECT
	f.DadosAgente_id,
	f.regiao_id,
	COALESCE((SELECT h.dt
	FROM v_Agente_Regiao_Hist h
	WHERE h.DadosAgente_id = f.DadosAgente_id
		AND h.regiao_id = f.regiao_id
		AND h.dt_start < f.dt_end
		AND h.dt_start IS NOT NULL
	ORDER BY h.dt_start DESC
	LIMIT 1
	), TIMESTAMP('2009-12-31 00:00:00')) as dt_start,
	TIMESTAMP(f.dt_end) as dt_end,
	f.revtype,
	TIMESTAMP('2009-12-31 00:00:00') as dt
FROM
(SELECT * FROM v_Agente_Regiao_Current
UNION ALL
 SELECT * FROM v_Agente_Regiao_Hist)
	AS f
WHERE
	f.dt_end IS NOT NULL
ORDER BY dt_end DESC