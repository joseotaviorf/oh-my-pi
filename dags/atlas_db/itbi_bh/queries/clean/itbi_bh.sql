SELECT
    TRIM(endereco_completo) AS address,
    TRIM(bairro) AS neighborhood,
    TRIM(padrao_acabamento_unidade) AS standard_finish,
    TRIM(tipo_construtivo_preponderante) AS predominant_construction_type,
    TRIM(descricao_tipo_ocupacao_unidade) AS occupation_description,
    TRIM(zona_uso_itbi) AS urban_zoning_code,
    source_file,
    CAST(ano_construcao_unidade AS INTEGER) AS year_built,
    CAST(area_terreno_total AS FLOAT) AS land_area_m2,
    CAST(area_construida_adquirida AS FLOAT) AS built_area_m2,
    CAST(area_adquirida_unidades_somadas AS FLOAT) AS all_units_area_m2,
    CAST(fracao_ideal_adquirida AS FLOAT) AS ideal_fraction,
    CAST(valor_base_calculo AS FLOAT) AS adopted_calculation_basis,
    CAST(valor_declarado AS FLOAT) AS declared_transaction_value,
    CAST(NULL AS FLOAT) AS amount_tax_paid_summarized,
    CAST(data_inclusao_transacao AS DATE) AS dt_transaction,
    CAST(dt_load AS DATE),
    month,
    year
FROM
    datalake_itbi_raw.itbi_bh
WHERE
    year BETWEEN YEAR(DATE('{load_start_date}')) - 1 AND YEAR(DATE('{load_end_date}'))
