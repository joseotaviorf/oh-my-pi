WITH addresses AS (
    SELECT 
      address_street_name AS address,
      CASE
        WHEN address_number IS NULL THEN 'N/A'
        WHEN CAST(address_number AS BIGINT) = 99999 THEN 'N/A'
        ELSE CAST(address_number AS STRING)
      END AS number,
      INITCAP(address_neighborhood) AS neighborhood,
      address_zipcode AS zipcode,
      'São Paulo' AS city
    FROM
      datalake_itbi_clean.itbi_sp
    WHERE 
      transaction_nature = '1.Compra e venda'
      AND ((TRIM(iptu_standard_description) = 'COMERCIAL HORIZONTAL' AND TRIM(iptu_use_description) IN ('RESIDÊNCIA','RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)')) 
        OR (TRIM(iptu_standard_description) = 'COMERCIAL VERTICAL' AND TRIM(iptu_use_description) IN ('FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)', 'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'))
        OR (TRIM(iptu_standard_description) = 'RESIDENCIAL HORIZONTAL' AND TRIM(iptu_use_description) IN ('', 'APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'))
        OR (TRIM(iptu_standard_description) = 'RESIDENCIAL VERTICAL' AND TRIM(iptu_use_description) IN ('APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)', 'FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)', 'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)')))
)
SELECT DISTINCT
  MD5(CONCAT(address, number, city)) AS id_address,
  address,
  number,
  neighborhood,
  zipcode,
  city
FROM
  addresses