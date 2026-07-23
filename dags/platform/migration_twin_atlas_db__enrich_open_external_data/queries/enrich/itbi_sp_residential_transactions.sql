WITH itbi_sp_enriched AS (
  SELECT
    -- Creating a unique identifier for each transaction combining source_tab, iptu_sql_registration_number, and row number:
    REPLACE(TRIM(source_tab), '-', '') ||
      TRIM(iptu_sql_registration_number) ||
      '-' ||
      ROW_NUMBER() OVER (PARTITION BY iptu_sql_registration_number,  REPLACE(source_tab, '-', '') ORDER BY 1) AS id_itbi_transaction_source,
    TRIM(CAST(iptu_sql_registration_number AS STRING)) AS iptu_sql_registration_number,
    TRIM(CAST(house_registry_number AS STRING)) AS house_registry_number,
    'ITBI_SP' AS itbi_region,
    'BR' AS address_country,
    'SP' AS address_state,
    'São Paulo' AS address_city,
    INITCAP(address_neighborhood) AS address_neighborhood,
    INITCAP(address_street_name) AS address_street_name,
    CASE
      WHEN address_number IS NULL THEN 'N/A'
      WHEN CAST(address_number AS BIGINT) = 99999 THEN 'N/A'
      ELSE CAST(address_number AS STRING)
    END AS address_number,
    INITCAP(address_complement) AS address_complement,
    TRIM(INITCAP(address_reference)) AS address_reference,
    address_zipcode,
    CASE
      WHEN SUBSTRING(financing_type, 3, LENGTH(financing_type)) = '' THEN NULL
      ELSE TRIM(SUBSTRING(financing_type, 3, LENGTH(financing_type)))
    END AS financing_type,
    /* Cleaning up house registry office information: replacing double spaces with single space,
      replacing 'Imovel' with 'Imóvel', 'Cartorio' with 'Cartório', removing 'º' */
    TRIM(
      REPLACE(
        REPLACE(
          REPLACE(
            REPLACE(INITCAP(house_registry_office), '  ', ' '), 'Imovel', 'Imóvel'
          ), 'Cartorio', 'Cartório'
        ), 'º', ''
      )
    ) AS house_registry_office,
    -- Constructing real estate registry office: 'CRI_' followed by digits extracted from house registry office:
    TRIM(
      'CRI_' ||
      ARRAY_JOIN(
        TRANSFORM(
          SPLIT(
            house_registry_office, ''
          ), x -> IF(
            CAST(x AS BIGINT) IS NULL, '', x
            )
        ), ''
      )
    ) AS real_estate_registry_office,
    TRIM(REPLACE(iptu_sql_status, '_', ' ')) AS iptu_sql_status,
    TRIM(
      UPPER(
        SUBSTRING(iptu_use_description, 1, 1)
      ) ||
      LOWER(
        SUBSTRING(iptu_use_description, 2, LENGTH(iptu_use_description))
      )
    ) AS iptu_use_description,
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
    -- Extracting numeric values from address complement and joining them:
    ARRAY_JOIN(
      TRANSFORM(
        SPLIT(
          ARRAY_JOIN(
            TRANSFORM(
              SPLIT(
                REPLACE(address_complement, '.', ' '), ''
              ), x -> IF(CAST(x AS BIGINT) IS NOT NULL OR x = ' ', x, '')
            ), ''
          ), ' '
        ), x -> IF(LENGTH(x) > 1, x, NULL)
      ), ' '
    ) AS numbers_complement,
    address_neighborhood AS raw_source_neighborhood,
    address_street_name AS raw_source_address,
    address_complement AS raw_source_complement,
    address_reference AS raw_source_reference,
    source_file,
    source_tab,
    month,
    year,
    TIMESTAMP(dt_transaction) AS ts_transaction,
    TIMESTAMP(dt_load) AS ts_load
  FROM
    datalake_itbi_clean.itbi_sp AS i
  WHERE
    transaction_nature = '1.Compra e venda'
    AND (
          (
            TRIM(iptu_standard_description) = 'COMERCIAL HORIZONTAL'
              AND TRIM(iptu_use_description) IN (
                'RESIDÊNCIA',
                'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)',
                'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'
              )
          )
          OR
          (
            TRIM(iptu_standard_description) = 'COMERCIAL VERTICAL'
              AND TRIM(iptu_use_description) IN (
                'FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)',
                'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)',
                'RESIDÊNCIA',
                'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'
              )
          )
          OR
          (
            TRIM(iptu_standard_description) = 'RESIDENCIAL HORIZONTAL'
              AND TRIM(iptu_use_description) IN (
                '',
                'APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)',
                'RESIDÊNCIA',
                'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)',
                'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)'
              )
          )
          OR
          (
            TRIM(iptu_standard_description) = 'RESIDENCIAL VERTICAL'
              AND TRIM(iptu_use_description) IN (
                'APARTAMENTO EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)',
                'RESIDÊNCIA',
                'RESIDÊNCIA COLETIVA, EXCLUSIVE CORTIÇO (MAIS DE UMA RESIDÊNCIA NO LOTE)',
                'RESIDÊNCIA E OUTRO USO (PREDOMINÂNCIA RESIDENCIAL)',
                'FLAT DE USO COMERCIAL (SEMELHANTE À HOTEL)',
                'FLAT RESIDENCIAL EM CONDOMÍNIO (EXIGE FRAÇÃO IDEAL)'
              )
          )
    )
)
SELECT
    ispe.id_itbi_transaction_source,
    MD5(
      CONCAT_WS('',
                COALESCE(ispe.ts_transaction, ''),
                COALESCE(ispe.address_country, ''),
                COALESCE(ispe.address_state, ''),
                COALESCE(ispe.address_city, ''),
                COALESCE(ispe.address_neighborhood, ''),
                COALESCE(ispe.address_street_name, ''),
                COALESCE(ispe.address_number, ''),
                COALESCE(ispe.address_complement, ''),
                COALESCE(ispe.address_reference, ''),
                COALESCE(ispe.address_zipcode, '')
            )
    ) AS id_address_transaction,
    ispe.iptu_sql_registration_number,
    ispe.house_registry_number,
    ispe.itbi_region,
    ispe.address_country,
    ispe.address_state,
    ispe.address_city,
    ispe.address_neighborhood,
    ispe.address_street_name,
    ispe.address_number,
    ispe.address_complement,
    ispe.address_reference,
    ispe.address_zipcode,
    ispe.financing_type,
    ispe.house_registry_office,
    ispe.real_estate_registry_office,
    ispe.iptu_sql_status,
    ispe.iptu_use_description,
    ispe.iptu_standard_description,
    ispe.declared_transaction_value,
    ispe.reference_appraisal_value,
    ispe.transmitted_proportion,
    ispe.proportional_reference_appraisal_value,
    COALESCE(ispe.adopted_calculation_basis, ispe.declared_transaction_value) AS adopted_calculation_basis,
    ispe.financed_value,
    ispe.land_area_m2,
    ispe.built_area_m2,
    ispe.portion_public_road_land_m,
    ispe.ideal_fraction,
    ispe.iptu_use_code,
    ispe.iptu_standard_code,
    ispe.iptu_registration_year AS year_built,
    ispe.numbers_complement,
    ispe.raw_source_neighborhood,
    ispe.raw_source_address,
    ispe.raw_source_complement,
    ispe.raw_source_reference,
    ispe.source_file,
    ispe.source_tab,
    ispe.month,
    ispe.year,
    ispe.ts_transaction,
    ispe.ts_load
FROM
    itbi_sp_enriched AS ispe
