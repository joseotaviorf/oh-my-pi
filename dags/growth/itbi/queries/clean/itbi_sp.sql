SELECT
  n_cadastro_sql AS iptu_sql_registration_number,
  TRIM(matricula_imovel) AS house_registry_number,
  nome_logradouro AS address_street_name,
  CAST(numero AS BIGINT) AS address_number,
  complemento AS address_complement,
  bairro AS address_neighborhood,
  referencia AS address_reference,
  CASE LENGTH(cep)
      WHEN 7 THEN CAST((LEFT(LPAD(TRIM(REPLACE(cep, '.', '')), 8, '0'), 5) || '-' || RIGHT(LPAD(TRIM(REPLACE(cep, '.', '')), 8, '0'), 3)) AS STRING)
      WHEN 9 THEN CAST((LEFT(LPAD(TRIM(SPLIT(cep, '\\.')[0]), 8, '0'), 5) || '-' || RIGHT(LPAD(TRIM(SPLIT(cep, '\\.')[0]), 8, '0'), 3)) AS STRING)
      ELSE TRANSLATE(cep, '\\.-', '')
  END AS address_zipcode,
  TRIM(natureza_transacao) AS transaction_nature,
  TRIM(tipo_financiamento) AS financing_type,
  TRIM(cartorio_registro) AS house_registry_office,
  TRIM(situacao_sql) AS iptu_sql_status,
  TRIM(descricao_uso_iptu) AS iptu_use_description,
  TRIM(descricao_padrao_iptu) AS iptu_standard_description,
  CAST(REGEXP_REPLACE(valor_transacao_declarado, ',', '') AS DECIMAL(18, 2)) AS declared_transaction_value,
  CAST(REGEXP_REPLACE(valor_venal_referencia, ',', '') AS DECIMAL(18, 2)) AS reference_appraisal_value,
  CAST(proporcao_transmitida AS DOUBLE) AS transmitted_proportion,
  CAST(REGEXP_REPLACE(valor_venal_referencia_proporcional, ',', '') AS DECIMAL(18, 2)) AS proportional_reference_appraisal_value,
  CAST(REGEXP_REPLACE(base_calculo_adotada, ',', '') AS DECIMAL(18, 2)) AS adopted_calculation_basis,
  CAST(REGEXP_REPLACE(valor_financiado, ',', '') AS DECIMAL(18, 2)) AS financed_value,
  CAST(area_terreno_m2 AS BIGINT) AS land_area_m2,
  CAST(testada_m AS DOUBLE) AS portion_public_road_land_m,
  CAST(fracao_ideal AS DECIMAL(18, 2)) AS ideal_fraction,
  CAST(area_construida_m2 AS BIGINT) AS built_area_m2,
  TRIM(uso_iptu) AS iptu_use_code,
  TRIM(padrao_iptu) AS iptu_standard_code,
  CAST(acc_iptu AS BIGINT) AS iptu_registration_year,
  source_file,
  source_tab,
  COALESCE(TO_DATE(data_transacao), TO_DATE(data_transacao, 'M/d/yy')) AS dt_transaction,
  dt_load,
  year,
  month
FROM
  datalake_itbi_raw.itbi_sp
WHERE
  year >= {year} - 1
