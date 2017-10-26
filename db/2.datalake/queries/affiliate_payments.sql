select
	occ.id,
	occ.tipo,
	occ.valor,
	occ.imovel_id,
	cc.id as conta_corrente_id,
	occ.dataCriacao as creation_date,
	occ.paymentDate as payment_date
from
	datalake_clean.ebdb_operacao_conta_corrente occ
left join
	datalake_clean.ebdb_conta_corrente cc
	on trim(occ.contacorrente_id) = trim(cc.id)
where
	trim(occ.tipo) in (
		'valorFixoPorIndicacaoDeImovel',
		'porcentagemPorIndicacaoDeImovel'
	)
