drop view if exists vw_dim_bank_account;

create view vw_dim_bank_account
as
select
  ba.id as sk_bank_account,
  ba.id as id_bank_account,
  u.dadosbancarios_conta_corrente as account_number,
  u.dadosbancarios_tipo_conta as account_type,
  u.dadosbancarios_agencia as agency_number,
  ba."atualizadoEm" as updated_at,
  ba."criadoEm" as created_at,
  now() as ts_load
from bank_account ba
join usuario u on u.id = ba.usuario_id;