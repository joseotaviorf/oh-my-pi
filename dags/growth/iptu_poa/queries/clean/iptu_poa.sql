WITH iptu_base AS (
    SELECT
        ano_exercicio AS iptu_year,
        TRIM(nme_endloc_bairro_cdl) AS address_neighborhood,
        TRIM(nme_endloc_logradouro) AS address_street_name,
        nme_endloc_cep AS address_zipcode,
        CAST(num_endloc_endereco AS BIGINT) AS address_number,
        TRIM(des_endloc_tipo_unidade) AS unit_type,
        CAST(num_endloc_unidade AS BIGINT) AS unit,
        pavimento AS floor,
        TRIM(nivel) AS level_type,
        TRIM(complemento) AS address_complement,
        TRIM(des_uso) AS property_use_description,
        TRIM(des_finalidade) AS property_purpose_description,
        TRIM(des_identificacao) AS house_registry_number,
        TRIM(des_zona) AS house_registry_zone,
        CAST(REPLACE(mtr_testada_principal, ',', '.') AS DOUBLE) AS main_frontage_area_m2,
        CAST(REPLACE(mtr_area_real, ',', '.') AS DOUBLE) AS land_area_m2,
        CAST(REPLACE(mtr_area_construida_total, ',', '.') AS DOUBLE) AS built_area_m2,
        CAST(REPLACE(mtr_area_corrigida, ',', '.') AS DOUBLE) AS taxable_area_m2,
        CAST(REPLACE(vlr_venal_terreno, ',', '.') AS DECIMAL(10, 2)) AS taxable_land_value,
        CAST(REPLACE(vlr_venal_construcoes, ',', '.') AS DECIMAL(10, 2)) AS taxable_built_value,
        CAST(REPLACE(vlr_venal_imovel, ',', '.') AS DECIMAL(10, 2)) AS taxable_property_value,
        CAST(REPLACE(vlr_aliquota, ',', '.') AS DOUBLE) AS tax_rate,
        CAST(REPLACE(vlr_imposto, ',', '.') AS DECIMAL(10, 2)) AS iptu_value,
        CAST(REPLACE(vlr_tcl, ',', '.') AS DECIMAL(10, 2)) AS tcrs_value,
        dt_load,
        year
    FROM
        datalake_iptu_poa_raw.iptu_poa
    WHERE
        year = YEAR(DATE('{load_start_date}'))
)
SELECT
    MD5(
        CONCAT_WS(
            '-',
            address_zipcode,
            address_number,
            address_complement,
            unit_type,
            unit,
            floor,
            level_type
        )
    ) AS id_house,
    *
FROM
    iptu_base
QUALIFY
     COUNT(id_house) OVER(PARTITION BY id_house) = 1
