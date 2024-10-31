SELECT
    id,
    inicioContrato AS ts_contract_started,
    usuario_id AS id_user,
    gerente_id AS id_manager,
    ativo AS is_active,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.dadosvendedor
