select
	id,
	inicioAtuacao,
	tipoAfiliado,
	cidadeAtuacao,
	coalesce(ativo,0) as ativo,
	atualizadoEm,
	criadoEm,
	left(numeroCreci, 50) as numeroCreci,
	origin,
	affiliateType,
    usuario_id
from DadosAfiliado
;
