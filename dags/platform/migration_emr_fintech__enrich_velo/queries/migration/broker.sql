WITH activation AS (
  SELECT
    p.id_real_estate,
    CAST(MIN(ph.ts_inserted) AS DATE) AS dt_first_propose,
    CAST(MIN(CASE WHEN ps.id IN (13, 14) THEN ph.ts_inserted END) AS DATE) AS dt_first_contract
  FROM datalake_rental_guarantee_platform_clean.propose_history AS ph
  LEFT JOIN datalake_rental_guarantee_platform_clean.propose_status AS ps
    ON ph.value = ps.name
  LEFT JOIN datalake_rental_guarantee_platform_clean.propose AS p
    ON p.id = ph.id_propose
  GROUP BY
    p.id_real_estate
), address AS (
  SELECT
    *
  FROM (
    SELECT
      a.*,
      ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY a.ts_updated DESC) AS _w
    FROM datalake_rental_guarantee_platform_clean.company AS c
    LEFT JOIN datalake_company_clean.address AS a
      ON c.uuid_company = a.uuid_company
  ) AS _t
  WHERE
    _w = 1
), company_info AS (
  SELECT
    *
  FROM (
    SELECT
      comp.*,
      ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY comp.ts_updated DESC) AS _w
    FROM datalake_rental_guarantee_platform_clean.company AS c
    LEFT JOIN datalake_company_clean.company AS comp
      ON c.uuid_company = comp.uuid_company
  ) AS _t
  WHERE
    _w = 1
), company_document AS (
  SELECT
    uuid_company,
    document_type,
    status,
    identification_number
  FROM (
    SELECT
      uuid_company,
      document_type,
      status,
      identification_number,
      ROW_NUMBER() OVER (PARTITION BY uuid_company, document_type ORDER BY ts_updated DESC) AS _w,
      ts_updated
    FROM datalake_company_clean.document
    WHERE
      status = 'ACTIVE'
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  c.id AS id_broker,
  comp.trade_name AS broker_comercial_name,
  comp.company_name AS broker_name,
  a.public_area AS street,
  a.`number`,
  a.complement,
  a.neighborhood,
  a.city,
  COALESCE(st.abbreviation, IF(a.state = '', NULL, UPPER(a.state))) AS state,
  ct.code AS country_code,
  a.zip_code AS zipcode,
  d.identification_number AS creci,
  d2.identification_number AS cnpj,
  NOT activation.dt_first_contract IS NULL AS is_broker_active,
  c.id <= 5000000 AS is_legacy,
  c.ts_created
FROM datalake_rental_guarantee_platform_clean.company AS c
LEFT JOIN company_info AS comp
  ON c.uuid_company = comp.uuid_company
LEFT JOIN address AS a
  ON c.uuid_company = a.uuid_company
LEFT JOIN company_document AS d
  ON c.uuid_company = d.uuid_company
  AND d.document_type = 'CRECI'
  AND d.status = 'ACTIVE'
LEFT JOIN company_document AS d2
  ON c.uuid_company = d2.uuid_company
  AND d2.document_type = 'CNPJ'
  AND d2.status = 'ACTIVE'
LEFT JOIN activation
  ON c.id = activation.id_real_estate
LEFT JOIN datalake_ebdb_clean.country AS ct
  ON IF(REPLACE(a.country, '\'', '') = '', NULL, UPPER(REPLACE(a.country, '\'', ''))) = UPPER(ct.name)
LEFT JOIN datalake_ebdb_clean.state AS st
  ON UPPER(a.state) = UPPER(st.name) AND ct.id = st.id_country
