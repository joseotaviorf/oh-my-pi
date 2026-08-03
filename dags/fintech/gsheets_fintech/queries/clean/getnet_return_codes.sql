SELECT
    codigo_novo AS new_code,
    codigo_antigo AS old_code,
    bandeira AS card_brand,
    tipo_codigo AS code_type,
    descricao AS description
FROM
    datalake_gsheets_raw.getnet_return_codes
