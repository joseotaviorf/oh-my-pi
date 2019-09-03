select
	da.id,
	da.indicadoPor_id,
	da.inicioAtuacao,
	da.tipoAfiliado,
	da.cidadeAtuacao,
	coalesce(da.ativo,0) as ativo,
	da.atualizadoEm,
	da.criadoEm,
	left(da.numeroCreci, 50) as numeroCreci,
	da.origin,
	da.affiliateType
from DadosAfiliado da