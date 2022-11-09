SELECT
    id AS id_sales_rep,
    usuario_id AS id_user,
    rev, 
    revtype AS rev_type,
    ativo AS is_active,
    inicioContrato AS ts_contract_started
FROM
    datalake_ebdb_raw.dadosVendedor_aud