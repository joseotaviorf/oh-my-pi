WITH iptu_base AS (
    SELECT
        *
    FROM
        datalake_iptu_bh_raw.iptu_bh
    WHERE
        year BETWEEN YEAR(DATE('{load_start_date}')) AND YEAR(DATE('{load_end_date}'))
),
iptu_normalized AS (
    SELECT
        TRIM(dados_cadastrais_gerais.indice_cadastral) AS id_house,
        TRIM(dados_cadastrais_gerais.exercicio) AS iptu_year,
        TRIM(dados_cadastrais_gerais.situacao_atual) AS iptu_status,
        TRIM(dados_cadastrais_gerais.endereco_do_imovel) AS address,
        TRIM(dados_cadastrais_gerais.endereco_de_correspondencia) AS mailing_address,
        NULLIF(TRIM(dados_cadastrais_gerais.matricula), '--') AS house_registry_number,
        NULLIF(TRIM(dados_cadastrais_gerais.cartorio), '--') AS house_registry_name,
        TRIM(dados_do_imovel.patrimonio) AS property_purpose_description,
        TRIM(dados_do_imovel.tipo_uso) AS property_use_description,
        TRIM(dados_do_imovel.frequencia_coleta) AS waste_collection_frequency,
        TRIM(caracteristicas_do_imovel.area_do_terreno) AS land_area_m2,
        TRIM(caracteristicas_do_imovel.fracao_ideal) AS ideal_land_fraction,
        TRIM(caracteristicas_do_imovel.area_do_terreno_fracionada) AS ideal_land_fraction_m2,
        TRIM(caracteristicas_do_imovel.area_construida) AS built_area_m2,
        TRIM(caracteristicas_do_imovel.ano_de_construcao) AS construction_year,
        TRIM(REPLACE(fatores_ligados_ao_terreno.melhorias, ', ', ',')) AS land_related_improvements,
        TRIM(fatores_de_imunidade_e_isencao.construcao) AS building_exemption,
        TRIM(fatores_de_imunidade_e_isencao.terreno) AS land_exemption,
        TRIM(fatores_de_imunidade_e_isencao.zona_uso) AS zone_exemption,
        TRIM(fatores_de_imunidade_e_isencao.patrimonio) AS property_exemption,
        TRIM(fatores_de_imunidade_e_isencao.imunidade) AS immunity,
        TRIM(fatores_de_imunidade_e_isencao.taxa_de_aparelho) AS transport_fee_exemption,
        TRIM(fatores_de_imunidade_e_isencao.taxa_de_iluminacao) AS street_lighting_fee_exemption,
        TRIM(fatores_de_imunidade_e_isencao.taxa_de_coleta) AS waste_collection_fee_exemption,
        TRIM(fatores_de_imunidade_e_isencao.imposto) AS tax_exemption,
        TRIM(fatores_de_imunidade_e_isencao.isencao_total) AS full_exemption,
        NULLIF(TRIM(elementos_do_lancamento.estado_lancamento),  '') AS iptu_payment_status,
        NULLIF(TRIM(elementos_do_lancamento.valor_m2_terreno), 'R$') AS land_value_m2,
        NULLIF(TRIM(elementos_do_lancamento.valor_venal_terreno), 'R$') AS taxable_land_value,
        NULLIF(TRIM(elementos_do_lancamento.valor_m2_construcao), 'R$') AS built_value_m2,
        NULLIF(TRIM(elementos_do_lancamento.valor_venal_construcao), 'R$') AS taxable_built_value,
        NULLIF(TRIM(elementos_do_lancamento.venal_total), 'R$') AS taxable_property_value,
        NULLIF(TRIM(elementos_do_lancamento.valor_aparelhos_de_transporte), 'R$') AS transport_fee_value,
        NULLIF(TRIM(elementos_do_lancamento.valor_coleta_de_residuos_solidos), 'R$') AS tcrs_value,
        NULLIF(TRIM(elementos_do_lancamento.valor_taxa_de_incendio), 'R$') AS fire_fee_value,
        NULLIF(TRIM(elementos_do_lancamento.valor_da_taxa_de_iluminacao), 'R$') AS street_lighting_fee_value,
        NULLIF(TRIM(elementos_do_lancamento.desconto_especial), 'R$') AS special_discount,
        NULLIF(TRIM(elementos_do_lancamento.valor_imposto), 'R$') AS iptu_value,
        TRANSFORM(
            unidades,
            unit -> STRUCT(
                TRIM(unit.tipo_de_ocupacao) AS occupancy_type,
                TRIM(unit.tipo_construtivo) AS construction_type,
                TRIM(unit.quantidade) AS quantity,
                TRIM(unit.area_construida) AS built_area_m2
            )
        ) AS unities,
        TRANSFORM(
            caracteristicas_construtivas,
            building_features -> STRUCT(
                TRIM(building_features.grupo) AS group_name,
                TRIM(building_features.subgrupo) AS subgroup_name,
                TRIM(building_features.item) AS item_name
            )
        ) AS building_features,
        dt_load,
        year
    FROM
        iptu_base
),
iptu_transformed AS (
    SELECT
        id_house,
        CAST(iptu_year AS BIGINT) AS iptu_year,
        iptu_status,
        address,
        mailing_address,
        CAST(house_registry_number AS BIGINT) AS house_registry_number,
        CAST(house_registry_name AS BIGINT) AS house_registry_name,
        property_purpose_description,
        property_use_description,
        waste_collection_frequency,
        CAST(REPLACE(REGEXP_REPLACE(land_area_m2, '[^0-9,]', ''), ',', '.') AS DOUBLE) AS land_area_m2,
        CAST(REPLACE(ideal_land_fraction, ',', '.') AS DOUBLE) AS ideal_land_fraction,
        CAST(REPLACE(REGEXP_REPLACE(ideal_land_fraction_m2, '[^0-9,]', ''), ',', '.') AS DOUBLE) AS ideal_land_fraction_m2,
        CAST(REPLACE(REGEXP_REPLACE(built_area_m2, '[^0-9,]', ''), ',', '.') AS DOUBLE) AS built_area_m2,
        CAST(construction_year AS BIGINT) AS construction_year,
        SPLIT(land_related_improvements, ',') AS land_related_improvements,
        IF(building_exemption = 'SIM', TRUE, FALSE) AS building_exemption,
        IF(land_exemption = 'SIM', TRUE, FALSE) AS land_exemption,
        IF(zone_exemption = 'SIM', TRUE, FALSE) AS zone_exemption,
        IF(property_exemption = 'SIM', TRUE, FALSE) AS property_exemption,
        IF(immunity = 'SIM', TRUE, FALSE) AS immunity,
        IF(transport_fee_exemption = 'SIM', TRUE, FALSE) AS transport_fee_exemption,
        IF(street_lighting_fee_exemption = 'SIM', TRUE, FALSE) AS street_lighting_fee_exemption,
        IF(waste_collection_fee_exemption = 'SIM', TRUE, FALSE) AS waste_collection_fee_exemption,
        IF(tax_exemption = 'SIM', TRUE, FALSE) AS tax_exemption,
        IF(full_exemption = 'SIM', TRUE, FALSE) AS full_exemption,
        iptu_payment_status,
        CAST(REPLACE(REGEXP_REPLACE(land_value_m2, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS land_value_m2,
        CAST(REPLACE(REGEXP_REPLACE(taxable_land_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS taxable_land_value,
        CAST(REPLACE(REGEXP_REPLACE(built_value_m2, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS built_value_m2,
        CAST(REPLACE(REGEXP_REPLACE(taxable_built_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS taxable_built_value,
        CAST(REPLACE(REGEXP_REPLACE(taxable_property_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS taxable_property_value,
        CAST(REPLACE(REGEXP_REPLACE(transport_fee_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS transport_fee_value,
        CAST(REPLACE(REGEXP_REPLACE(tcrs_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS tcrs_value,
        CAST(REPLACE(REGEXP_REPLACE(fire_fee_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS fire_fee_value,
        CAST(REPLACE(REGEXP_REPLACE(street_lighting_fee_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS street_lighting_fee_value,
        CAST(REPLACE(REGEXP_REPLACE(special_discount, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS special_discount,
        CAST(REPLACE(REGEXP_REPLACE(iptu_value, '[^0-9,]', ''), ',', '.') AS DECIMAL(10, 2)) AS iptu_value,
        TRANSFORM(
            unities,
            unit -> STRUCT(
                unit.occupancy_type,
                unit.construction_type,
                CAST(unit.quantity AS BIGINT) AS quantity,
                CAST(REGEXP_REPLACE(unit.built_area_m2, '[^0-9.]', '') AS DOUBLE) AS built_area_m2
            )
        ) AS unities,
        building_features,
        dt_load,
        year
    FROM
        iptu_normalized
)
SELECT
    *
FROM
    iptu_transformed
QUALIFY
     COUNT(id_house) OVER(PARTITION BY id_house) = 1
