SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  metadata,
  path,
  year,
  month,
  day
FROM
  datalake_kodak_raw.photo
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
