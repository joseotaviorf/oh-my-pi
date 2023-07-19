SELECT 
    REPLACE(TRIM(source_tab), '-', '') || TRIM(iptu_sql_registration_number) || '-' || ROW_NUMBER() OVER (PARTITION BY iptu_sql_registration_number,  REPLACE(source_tab, '-', '') ORDER BY 1) AS id_itbi_transaction,
    TRIM(CAST(iptu_sql_registration_number AS STRING)) AS iptu_sql_registration_number,
    TRIM(CAST(house_registry_number AS STRING)) AS house_registry_number,
    COALESCE(c.id_region, -1) AS id_region,
    COALESCE(c.neighborhood, INITCAP(i.address_neighborhood)) AS address_neighborhood,
    COALESCE(c.address, INITCAP(ARRAY_JOIN(TRANSFORM(SPLIT(i.address_street_name, ' '), (x, i) -> CASE 
                                                                                                    WHEN i = 0 AND x = 'R' THEN 'Rua'
                                                                                                    WHEN i = 0 AND x = 'AV' THEN 'Avenida'
                                                                                                    WHEN i = 0 AND x = 'AL' THEN 'Alameda'
                                                                                                    WHEN i = 0 AND x = 'PC' THEN 'Praça'
                                                                                                    WHEN i = 0 AND x = 'ES' THEN 'Estrada'
                                                                                                    WHEN i = 0 AND x = 'TV' THEN 'Travessa'
                                                                                                    WHEN i = 0 AND x = 'LG' THEN 'Largo'
                                                                                                    WHEN i = 0 AND x = 'RV' THEN 'Rodovia'
                                                                                                    WHEN i = 0 AND x = 'VD' THEN 'Viaduto'
                                                                                                    WHEN i = 0 AND x = 'PQ' THEN 'Parque'
                                                                                                    WHEN i = 0 AND x = 'VL' THEN 'Vila'
                                                                                                    ELSE x
                                                                                                  END), 
    ' '))) AS address_street_name,
    CASE
        WHEN CAST(address_number AS BIGINT) = 99999 THEN NULL
        ELSE CAST(address_number AS BIGINT)
    END AS address_number,
    address_complement,
    TRIM(INITCAP(address_reference)) AS address_reference,
    address_zipcode,
    CASE 
        WHEN SUBSTRING(financing_type, 3, LENGTH(financing_type)) = '' THEN NULL
        ELSE TRIM(SUBSTRING(financing_type, 3, LENGTH(financing_type)))
    END AS financing_type,
    TRIM(REPLACE(REPLACE(REPLACE(REPLACE(INITCAP(house_registry_office), '  ', ' '), 'Imovel', 'Imóvel'), 'Cartorio', 'Cartório'), 'º', '')) AS house_registry_office,
    TRIM('CRI_' || ARRAY_JOIN(TRANSFORM(SPLIT(house_registry_office, ''), x -> IF(CAST(x AS BIGINT) IS NULL, '', x)), '')) AS real_estate_registry_office,
    TRIM(REPLACE(iptu_sql_status, '_', ' ')) AS iptu_sql_status,
    TRIM(UPPER(SUBSTRING(iptu_use_description, 1, 1)) || LOWER(SUBSTRING(iptu_use_description, 2, LENGTH(iptu_use_description)))) AS iptu_use_description,
    TRIM(INITCAP(iptu_standard_description)) AS iptu_standard_description,
    CASE
      WHEN CAST(declared_transaction_value AS DOUBLE) = 0 THEN NULL
      ELSE CAST(declared_transaction_value AS DOUBLE)
    END AS declared_transaction_value,
    CAST(reference_appraisal_value AS DOUBLE) AS reference_appraisal_value,
    CAST(transmitted_proportion AS FLOAT) AS transmitted_proportion,
    CAST(proportional_reference_appraisal_value AS DOUBLE) AS proportional_reference_appraisal_value,
    CAST(adopted_calculation_basis AS FLOAT) AS adopted_calculation_basis,
    CAST(financed_value AS DOUBLE) AS financed_value,
    CAST(land_area_m2 AS BIGINT) AS land_area_m2,
    CAST(built_area_m2 AS BIGINT) AS built_area_m2, 
    CAST(portion_public_road_land_m AS FLOAT) AS portion_public_road_land_m,
    CAST(ideal_fraction AS FLOAT) AS ideal_fraction,
    CAST(iptu_use_code AS BIGINT) AS iptu_use_code,
    CAST(iptu_standard_code AS BIGINT) AS iptu_standard_code,
    CAST(iptu_registration_year AS BIGINT) AS iptu_registration_year,
    ARRAY_JOIN(TRANSFORM(SPLIT(ARRAY_JOIN(TRANSFORM(SPLIT(REPLACE(address_complement, '.', ' '), ''), x -> IF(CAST(x AS BIGINT) IS NOT NULL OR x = ' ', x, '')), ''), ' '), x -> IF(LENGTH(x) > 1, x, NULL)), ' ') AS numbers_complement,
    address_neighborhood AS raw_source_neighborhood,
    address_street_name AS raw_source_address,
    address_complement AS raw_source_complement,
    address_reference AS raw_source_reference,
    source_file,
    source_tab,
    month,
    year,
    TO_DATE(dt_transaction, 'yyyy-MM-dd') AS dt_transaction,
    dt_load
FROM
    datalake_itbi_clean.itbi_sp AS i
LEFT JOIN 
    datalake_zipcodes.zipcodes AS c 
        ON c.zipcode = CAST((LEFT(i.address_zipcode, 5) || '-' || RIGHT(i.address_zipcode, 3)) AS STRING) 
        AND c.city_name = 'São Paulo'
WHERE 
    transaction_nature = '1.Compra e venda'
    AND ((TRIM(iptu_standard_description) = 'COMERCIAL HORIZONTAL' AND TRIM(iptu_use_description) IN ('RESIDÊNCIA','RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)')) 
    OR (TRIM(iptu_standard_description) = 'COMERCIAL VERTICAL' AND TRIM(iptu_use_description) IN ('FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)', 'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'))
    OR (TRIM(iptu_standard_description) = 'RESIDENCIAL HORIZONTAL' AND TRIM(iptu_use_description) IN ('', 'APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'))
    OR (TRIM(iptu_standard_description) = 'RESIDENCIAL VERTICAL' AND TRIM(iptu_use_description) IN ('APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)', 'RESIDÊNCIA', 'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)', 'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)', 'FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)', 'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)')))