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
  p.city,
  LAST_VALUE(apt.utm_campaign) OVER w AS utm_campaign,
  LAST_VALUE(apt.utm_medium) OVER w AS utm_medium,
  LAST_VALUE(apt.utm_source) OVER w AS utm_source,
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
WINDOW w AS (PARTITION BY apt.id_device ORDER BY apt.year, apt.month, apt.DAY ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)