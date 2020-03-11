select
	at.id,
	at.type as tipo,
	at.value as valor,
	at.id_house as imovel_id,
	a.id as conta_corrente_id,
	at.ts_created as creation_date,
	at.ts_payment as payment_date
from
	datalake_ebdb_clean_prod.account_transaction at
left join
	datalake_ebdb_clean_prod.account a
	on at.id_account = a.id
where
	trim(at.type) in (
		'valorFixoPorIndicacaoDeImovel',
		'porcentagemPorIndicacaoDeImovel'
	)
