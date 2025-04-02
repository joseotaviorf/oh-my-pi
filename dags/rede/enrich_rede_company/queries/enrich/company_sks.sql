WITH company_product AS (
  SELECT
    cp.id_company,
    MAX(GET_JSON_OBJECT(cp.product_settings, '$.bankingInformationUUId')) AS uuid_banking_information,
    MAX(GET_JSON_OBJECT(cp.product_settings, '$.integratorPartnerUUId')) AS uuid_integrator_partner,
    MAX(GET_JSON_OBJECT(cp.product_settings, '$.revenueShareUUId')) AS uuid_revenue_share,
    MAX(cp.id_product) = 33 AS is_company_asp,
    MAX(cp.id_product) = 32 AS is_company_ciq,
    MAX(cp.id_product) = 28 AS is_company_legal_person_rental_guarantee,
    MAX(cp.id_product) = 29 AS is_company_pp_multi,
    MAX(cp.id_product) = 27 AS is_company_rede_broker,
    MAX(cp.id_product) = 1 AS is_company_rental_guarantee
  FROM
    datalake_company_clean.company_product AS cp
  GROUP BY
    ALL
),
company_address AS (
  SELECT
    ca.id_company,
    ca.id_address
  FROM
    datalake_company_clean.company_address AS ca
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ca.id_company ORDER BY ca.ts_updated DESC) = 1
),
company_cnpj_aux AS (
  SELECT
    cd.id_company,
    REGEXP_REPLACE(d.identification_number, '[^0-9]', '') AS identification_number,
    cd.ts_updated
  FROM
    datalake_company_clean.company_document AS cd
  INNER JOIN
    datalake_company_clean.document AS d
      ON cd.id_document = d.id
        AND d.document_type = 'CNPJ'
        AND d.status = 'ACTIVE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cd.id_company ORDER BY cd.ts_updated DESC) = 1
),
company_cnpj AS (
  SELECT
    ca.id_company,
    ca.identification_number,
    ca.ts_updated
  FROM
    company_cnpj_aux AS ca
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY identification_number ORDER BY ts_updated DESC) = 1
),
company_creci AS (
  SELECT
    cd.id_company,
    d.identification_number
  FROM
    datalake_company_clean.company_document AS cd
  INNER JOIN
    datalake_company_clean.document AS d
      ON cd.id_document = d.id
        AND d.document_type = 'CRECI'
        AND d.status = 'ACTIVE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cd.id_company ORDER BY cd.ts_updated DESC) = 1
),
company_members AS (
  SELECT
    cm.id_company,
    hc.uuid_company,
    cm.cnpj,
    cm.company_name,
    cm.extracted_3p_tag
  FROM
    datalake_hubspot.company_members AS cm
  LEFT JOIN
    datalake_hubspot.company AS hc
      ON cm.id_company = hc.id_company
)
SELECT
  XXHASH64(c.id) AS sk_company,
  c.id AS id_company,
  ca.id_address,
  cm.id_company AS id_hubspot,
  cp.uuid_banking_information,
  c.uuid_company,
  cp.uuid_integrator_partner,
  cp.uuid_revenue_share,
  ccn.identification_number AS cnpj,
  ccr.identification_number AS creci,
  c.company_name,
  c.trade_name,
  cm.company_name AS hubspot_company_name,
  cm.extracted_3p_tag,
  cp.is_company_asp,
  cp.is_company_ciq,
  cp.is_company_legal_person_rental_guarantee,
  cp.is_company_pp_multi,
  cp.is_company_rede_broker,
  cp.is_company_rental_guarantee,
  c.ts_created,
  c.ts_updated
FROM
  datalake_company_clean.company AS c
LEFT JOIN
  company_product AS cp
    ON c.id = cp.id_company
LEFT JOIN
  company_address AS ca
    ON c.id = ca.id_company
LEFT JOIN
  company_cnpj AS ccn
    ON c.id = ccn.id_company
LEFT JOIN
  company_creci AS ccr
    ON c.id = ccr.id_company
LEFT JOIN
  company_members AS cm
    ON c.uuid_company = cm.uuid_company
      OR (cm.uuid_company IS NULL AND ccn.identification_number = cm.cnpj)