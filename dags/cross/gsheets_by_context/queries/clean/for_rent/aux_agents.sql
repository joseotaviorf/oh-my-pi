SELECT
    CAST(id AS BIGINT) AS id,
    status AS agent_status,
    tipo_agent AS agent_type,
    motivo_descredenciamento AS deaccreditation_reason,
    motivo_suspensao AS suspension_reason,
    CAST(dias_desde_ativacao AS INT) AS days_from_activation, 
    IF(LOWER(descred_permanente)='sim', TRUE, FALSE) AS is_permanent_deaccreditation,
    TO_DATE(semana_credenciamento, 'yyyy-MM-dd') AS dt_accreditation_week,
    TO_DATE(data_ativacao, 'yyyy-MM-dd') AS dt_activation,
    TO_DATE(data_last_descredenciamento, 'yyyy-MM-dd') AS dt_last_deaccreditation,
    TO_DATE(data_last_retorno_descredenciamento, 'yyyy-MM-dd') AS dt_last_return_deaccreditation,
    TO_DATE(data_last_suspensao, 'yyyy-MM-dd') AS dt_last_suspension,
    TO_DATE(data_last_retorno_suspensao, 'yyyy-MM-dd') AS dt_last_return_suspension
FROM
    datalake_gsheets_raw.aux_agents