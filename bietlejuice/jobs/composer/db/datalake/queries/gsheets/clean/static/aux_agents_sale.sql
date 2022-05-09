SELECT
    CAST(id AS BIGINT) AS id_agent,
    status,
    tipo_agent AS agent_type,
    motivo_descredenciamento AS reason_disqualification,
    motivo_suspensao AS suspension_reason,
    descred_permanente AS permanent_disaccreditation,
    CAST(dias_desde_ativacao AS INTEGER) AS days_since_activation,
    TO_DATE(data_ativacao, 'yyyy-MM-dd') AS dt_activation,
    TO_DATE(data_last_descredenciamento, 'yyyy-MM-dd') AS dt_last_deaccreditation,
    TO_DATE(data_last_retorno_descredenciamento, 'yyyy-MM-dd') AS dt_last_return_deaccreditation,
    TO_DATE(data_last_suspensao, 'yyyy-MM-dd') AS dt_last_suspension,
    TO_DATE(data_last_retorno_suspensao, 'yyyy-MM-dd') AS dt_last_return_suspension,
    TO_DATE(semana_credenciamento, 'yyyy-MM-dd') AS dt_week_accreditation
FROM
    datalake_gsheets_raw.aux_agents_sale
