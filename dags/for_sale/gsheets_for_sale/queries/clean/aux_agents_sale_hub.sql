SELECT
    CAST(id AS BIGINT) AS id_user_agent,
    status,
    tipo_agent AS agent_type,
    CAST(dias_desde_ativacao AS BIGINT) AS days_since_activation,
    descred_permanente AS permanently_deactivated,
    motivo_suspensao AS suspension_reason,
    motivo_descredenciamento AS deactivation_reason,
    CAST(semana_credenciamento AS DATE) AS dt_registration,
    CAST(data_ativacao AS DATE) AS dt_activation,
    CAST(data_last_suspensao AS DATE) AS dt_last_suspension,
    CAST(data_last_retorno_suspensao AS DATE) AS dt_last_suspension_return,
    CAST(data_last_descredenciamento AS DATE) AS dt_last_deactivation,
    CAST(data_last_retorno_descredenciamento AS DATE) AS dt_last_deactivation_return
FROM
    datalake_gsheets_raw.aux_agents_sale_hub
