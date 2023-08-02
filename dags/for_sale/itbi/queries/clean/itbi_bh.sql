SELECT 
  TRIM(bairro) AS neighborhood,
  endereco_completo AS address,
  TRIM(descricao_tipo_ocupacao_unidade) AS occupation_description,
  TRIM(padrao_acabamento_unidade) AS standard_finish,
  TRIM(zona_uso_itbi) AS urban_zoning_code,
  TRIM(tipo_construtivo_preponderante) AS predominant_construction_type,
  source_file,
  area_terreno_total::FLOAT AS land_area_m2,
  area_construida_adquirida::FLOAT AS built_area_m2,
  area_adquirida_unidades_somadas::FLOAT AS all_units_area_m2,
  fracao_ideal_adquirida::FLOAT AS ideal_fraction,
  valor_base_calculo::FLOAT AS adopted_calculation_basis,
  CAST(NULL AS FLOAT) AS amount_tax_paid_summarized,
  ano_construcao_unidade::INTEGER AS year_built,
  data_inclusao_transacao::DATE AS dt_transaction,
  dt_load,
  month,
  year
FROM 
  datalake_itbi_raw.itbi_bh 