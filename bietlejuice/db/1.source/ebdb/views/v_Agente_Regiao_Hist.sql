CREATE OR REPLACE VIEW v_Agente_Regiao_Hist AS
(
	SELECT a.DadosAgente_id as DadosAgente_id,
		a.regioes_id as regiao_id,
		CASE a.REVTYPE
			WHEN 0 THEN FROM_UNIXTIME(floor(b.timestamp/1000))
			ELSE NULL END AS 'dt_start',
		CASE a.REVTYPE
			WHEN 2 THEN FROM_UNIXTIME(floor(b.timestamp/1000))
			ELSE NULL END AS 'dt_end',
	 	a.REVTYPE,
	 	FROM_UNIXTIME(floor(b.timestamp/1000)) AS dt
	FROM DadosAgente_Regiao_AUD a
	 left join UsuarioRevisionEntity b
		 on a.rev = b.id
	-- where dadosagente_id = 386
	where FROM_UNIXTIME(floor(timestamp/1000)) < TIMESTAMP('2018-05-24 00:00:00')
);