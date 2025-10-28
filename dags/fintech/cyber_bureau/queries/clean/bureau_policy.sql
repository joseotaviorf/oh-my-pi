SELECT
    CD_POLITICA AS id_policy,
    DT_INI_VIG AS ts_validity_start,
    DT_FIM_VIG AS ts_validity_end,
    DS_ACAO_BUREAU AS bureau_action_description,
    TP_CLI_DEVEDOR AS debtor_client_type,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_politica_mnr
