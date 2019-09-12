select
	da.id,
	da.indicadoPor_id,
	da.inicioAtuacao,
	da.tipoAfiliado,
	coalesce(da.ativo,0) as ativo,
	da.atualizadoEm,
	da.criadoEm,
	da.origin,
	da.affiliateType
from DadosAfiliado da