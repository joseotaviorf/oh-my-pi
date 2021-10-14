SELECT
    codigo_conta AS id_account,
    CAST(ordem AS INT) AS id_order,
    CAST(lineid AS INT) AS id_line,
    agrupador AS group,
    descricao_conta AS account_description
FROM
    datalake_gsheets_raw.agr_account