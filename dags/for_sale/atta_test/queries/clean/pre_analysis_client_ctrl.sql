SELECT
    id_controle     AS id_control,
    id_cliente      AS id_client,
    id_solicitacao  AS id_request,
    compoeRenda     AS has_income,
    dt_cadastro     AS ts_register,
    dt_inativo      AS ts_inactive
FROM
    datalake_atta_test_raw.consulta_score_cliente_ctrl
