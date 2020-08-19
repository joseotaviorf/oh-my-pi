--drop view if exists vw_dim_partner;
--create or replace view vw_dim_partner as
SELECT
  id as sk_partner,
  id as id_partner,
  name,
  trade_name,
  phone,
  email,
  cnpj,
  creci,
  ts_joined_partnership,
  ts_updated,
  ts_created,
  now()::timestamp as ts_load
FROM
  partner;