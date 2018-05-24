CREATE OR REPLACE VIEW v_Agente_Regiao_Current AS
(
SELECT
	DadosAgente_id as DadosAgente_id,
	regioes_id as regiao_id,
	NULL as dt_start,
	TIMESTAMP('2099-12-31 00:00:00') as dt_end,
	3 as revtype,
	TIMESTAMP('2099-12-31 00:00:00') as dt
FROM DadosAgente_Regiao a
);