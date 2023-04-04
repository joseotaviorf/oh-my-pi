SELECT
  c.id AS id_company,
  COALESCE(c.comercial_name, c.name) AS company_name,
  ca.street,
  ca.number,
  ca.complement,
  ca.neighborhood,
  UPPER(ca.city) AS city,
  UPPER(ca.state) AS state, -- this comes already as abbreviation
  ct.code AS country_code,
  ca.zipcode,
  ca.geolocation,
  c.document AS cnpj,
  c.ts_inserted AS ts_created,
  c.ts_updated
FROM
  datalake_velo_clean.clientes_company AS c
LEFT JOIN
  datalake_velo_clean.clientes_address AS ca
    ON ca.id = c.address
LEFT JOIN
  datalake_ebdb_clean.country AS ct
    ON IF(REPLACE(ca.country, '\'', '') = '', NULL, UPPER(REPLACE(ca.country, '\'', ''))) = UPPER(ct.name)
