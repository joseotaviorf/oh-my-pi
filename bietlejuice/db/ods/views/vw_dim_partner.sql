--drop view if exists vw_dim_partner;
--create or replace view vw_dim_partner as
SELECT DISTINCT
  p.id as sk_partner,
  p.id as id_partner,
  p.id_amplitude_device,
  p.name,
  p.trade_name,
  p.phone,
  p.email,
  p.cnpj,
  p.creci,
  p.type,
  apt.utm_campaign,
  apt.utm_medium,
  apt.utm_source,
  p.ts_joined_partnership,
  p.ts_updated,
  p.ts_created,
  now()::timestamp as ts_load
FROM
  partner p
LEFT JOIN
  public.amplitude_partner_taxonomy apt
ON
  p.id_amplitude_device = apt.id_device