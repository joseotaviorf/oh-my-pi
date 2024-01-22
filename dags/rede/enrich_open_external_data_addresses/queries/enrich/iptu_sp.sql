WITH addresses AS (
  SELECT 
    address,
    CASE
      WHEN number IS NULL THEN 'N/A'
      WHEN CAST(number AS BIGINT) = 99999 THEN 'N/A'
      ELSE CAST(number AS STRING)
    END AS number,
    INITCAP(neighborhood) AS neighborhood,
    zipcode AS zipcode,
    'São Paulo' AS city
  FROM 
    datalake_iptu_clean.iptu_sp
  WHERE
    (TRIM(building_standard_type) LIKE "Comercial horizontal%" AND TRIM(property_use_type) IN ("Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
    OR (TRIM(building_standard_type) LIKE "Comercial vertical%" AND TRIM(property_use_type) IN ("Flat de uso comercial (semelhante a hotel)", "Flat residencial em condomínio",  "Residência", "Residência e outro uso (predominância residencial)"))
    OR (TRIM(building_standard_type) LIKE "Residencial horizontal%" AND TRIM(property_use_type) IN ("Apartamento em condomínio", "Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
    OR (TRIM(building_standard_type) LIKE "Residencial horizontal%" AND TRIM(property_use_type) IN ("Apartamento em condomínio", "Flat de uso comercial (semelhante a hotel)", "Flat residencial em condomínio", "Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
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