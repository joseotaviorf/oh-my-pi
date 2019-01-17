drop view if exists vw_dim_bank_transaction;

create view vw_dim_bank_transaction
as
select
	id as sk_bank_transaction,
	id as id_bank_transaction,
	descricao as description,
	tipo as "type",
	"atualizadoEm" as updated_at,
	"dataCriacao" as created_at,
	now() as ts_load
from
	public.bank_transaction
;
