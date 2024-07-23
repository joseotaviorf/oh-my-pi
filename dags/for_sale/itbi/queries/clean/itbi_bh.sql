SELECT
  TRIM(endereco_completo) AS address,
  TRIM(bairro) AS neighborhood,
  TRIM(padrao_acabamento_unidade) AS standard_finish,
  TRIM(tipo_construtivo_preponderante) AS predominant_construction_type,
  TRIM(descricao_tipo_ocupacao_unidade) AS occupation_description,
  TRIM(zona_uso_itbi) AS urban_zoning_code,
  source_file,
  ano_construcao_unidade::INTEGER AS year_built,
  area_terreno_total::FLOAT AS land_area_m2,
  area_construida_adquirida::FLOAT AS built_area_m2,
  area_adquirida_unidades_somadas::FLOAT AS all_units_area_m2,
  fracao_ideal_adquirida::FLOAT AS ideal_fraction,
  valor_base_calculo::FLOAT AS adopted_calculation_basis,
  valor_declarado::FLOAT AS declared_transaction_value,
  CAST(NULL AS FLOAT) AS amount_tax_paid_summarized,
  data_inclusao_transacao::DATE AS dt_transaction,
  dt_load::DATE,
  month,
  year
FROM
  datalake_itbi_raw.itbi_bh
