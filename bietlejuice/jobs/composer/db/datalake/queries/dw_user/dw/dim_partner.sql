SELECT DISTINCT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  p.id as sk_partner,
  p.id as id_partner,
  p.id_amplitude_device,
  u.country_code,
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
  p.ts_partnership_started AS ts_joined_partnership,
  p.ts_created,
  p.ts_updated,
  now() as ts_load
FROM
  datalake_ebdb_clean.partner AS p
LEFT JOIN
  datalake_amplitude_partner_taxonomy.amplitude_partner_taxonomy AS apt
    ON p.id_amplitude_device = apt.id_device
LEFT JOIN
  datalake_ebdb_user.user AS u
    ON u.id = p.id
WINDOW w AS (PARTITION BY apt.id_device ORDER BY apt.year, apt.month, apt.DAY ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)