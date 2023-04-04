SELECT
  r.id AS id_broker,
  c.comercial_name AS broker_comercial_name,
  c.name AS broker_name,
  ca.street,
  ca.number,
  ca.complement,
  ca.neighborhood,
  UPPER(ca.city) AS city,
  UPPER(ca.state) AS state, -- this comes already as abbreviation
  ct.code AS country_code,
  ca.zipcode,
  ca.geolocation,
  r.creci,
  c.document AS cnpj,
  r.is_active AS is_broker_active,
  r.ts_inserted AS ts_created
FROM
  datalake_velo_clean.fiancavelo_realestate AS r
LEFT JOIN
  datalake_velo_clean.clientes_company AS c
    ON c.id = r.id_company
LEFT JOIN
  datalake_velo_clean.clientes_address AS ca
    ON ca.id = c.address
LEFT JOIN
  datalake_ebdb_clean.country AS ct
    ON IF(REPLACE(ca.country, '\'', '') = '', NULL, UPPER(REPLACE(ca.country, '\'', ''))) = UPPER(ct.name)
