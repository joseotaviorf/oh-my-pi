select
	da.id,
	da.inicioAtuacao,
	da.tipoAfiliado,
	da.cidadeAtuacao,
	coalesce(da.ativo,0) as ativo,
	da.atualizadoEm,
	da.criadoEm,
	left(da.numeroCreci, 50) as numeroCreci,
	da.origin,
	da.affiliateType,
	u.id as user_id
from DadosAfiliado da
join Usuario u
	on da.id = u.dadosAfiliado_id