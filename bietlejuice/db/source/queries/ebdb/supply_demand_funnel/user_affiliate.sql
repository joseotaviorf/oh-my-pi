SELECT
	da.id,
	da.inicioAtuacao,
	da.tipoAfiliado,
	da.cidadeAtuacao,
	coalesce(da.ativo,0) as ativo,
	da.atualizadoEm,
	da.criadoEm,
	da.numeroCreci,
	da.origin,
	da.affiliateType,
    da.usuario_id
FROM
	DadosAfiliado da