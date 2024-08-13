SELECT    
    id_airtable_record,
    historico_v2 AS ids_history,
    CAST(id_user AS BIGINT) AS id_user,
    CAST(credenciamentos AS INT) AS accreditations,
    agent_actual_type,
    CAST(agent_creci AS BIGINT) AS agent_creci,
    email AS agent_email,
    name AS agent_name,
    phone_number AS agent_phone_number,
    cpf,
    disqualification,
    status_dinamico AS dynamic_status,
    last_area,
    last_disqualification,
    last_disqualification_reason,
    last_suspension,
    last_suspension_reason,
    descred_permanente AS permanent_deaccreditation,
    suspensoes AS suspensions,
    registro_supensoes AS suspensions_register,
    tickets_jira,
    CAST(days_since_activation_week AS DOUBLE) AS days_since_activation_week,
    TO_DATE(activation_date, 'yyyy-MM-dd') AS dt_activated,
    TO_DATE(last_disqualification_date, 'yyyy-MM-dd') AS dt_last_disqualificated,
    TO_DATE(last_disqualification_return_date, 'yyyy-MM-dd') AS dt_last_disqualification_returned,
    TO_DATE(last_suspension_date, 'yyyy-MM-dd') AS dt_last_suspended,
    TO_DATE(last_supension_return_date, 'yyyy-MM-dd') AS dt_last_suspension_returned,
    TO_DATE(accreditation_week, 'yyyy-MM-dd') AS dt_week_accreditated,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.activated
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}