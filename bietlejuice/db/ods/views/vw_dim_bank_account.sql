--drop view if exists vw_dim_bank_account;
--create view vw_dim_bank_account as
select
  u.contacorrente_id as sk_bank_account,
  u.contacorrente_id as id_bank_account,
  u.dadosbancarios_conta_corrente as account_number,
  u.dadosbancarios_tipo_conta as account_type,
  u.dadosbancarios_agencia as agency_number,
  ba."atualizadoEm" as ts_updated,
  ba."criadoEm" as ts_created,
  now() as ts_load
from usuario u
left join bank_account ba on u.contaCorrente_id = ba.id
where u.contaCorrente_id is not null;