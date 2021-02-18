SELECT
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