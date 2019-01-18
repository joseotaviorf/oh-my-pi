drop view if exists vw_fact_bank_transaction;

create view vw_fact_bank_transaction
as
select
	bt.id as sk_bank_transaction,
	bt.id as id_bank_transaction,
	bt."dataOperacao" as ts_trasaction,
	bt.valor as "value",
	bt."contaCorrente_id" as sk_bank_account,
	bt.imovel_id as house_id,
	COALESCE(u.id, -1) as sk_user,
	COALESCE(b.id, -1) as sk_bank,
	now() as ts_load
from
	bank_transaction bt
left join
	usuario u on bt."contaCorrente_id" = u.contaCorrente_id
left join
	bank b on b.codigo = u.dadosbancarios_banco_codigo
;
