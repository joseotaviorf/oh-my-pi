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
  LAST_VALUE(apt.utm_campaign) OVER w AS utm_campaign,
  LAST_VALUE(apt.utm_medium) OVER w AS utm_medium,
  LAST_VALUE(apt.utm_source) OVER w AS utm_source,
  p.ts_partnership_started,
  p.ts_created,
  p.ts_updated,
  now() as ts_load
FROM
  datalake_ebdb_clean.partner p
LEFT JOIN
  datalake_amplitude_partner_taxonomy.amplitude_partner_taxonomy apt
ON
  p.id_amplitude_device = apt.id_device
WINDOW w AS (PARTITION BY apt.id_device ORDER BY apt.year, apt.month, apt.DAY ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)