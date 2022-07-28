SELECT
    id_user,
    agent_actual_type,
    agent_creci,
    email AS agent_email,
    name AS agent_name,
    phone_number AS agent_phone_number,
    cpf,
    status_dinamico AS dynamic_status,
    last_area,
    last_suspension,
    status,
    suspensoes AS suspensions,
    registro_supensoes AS suspensions_register,
    tickets_jira,
    days_since_activation_week,
    TO_DATE(activation_date, 'yyyy-MM-dd') AS dt_activated,
    TO_DATE(last_suspension_date, 'yyyy-MM-dd') AS dt_last_suspended,
    TO_DATE(accreditation_week, 'yyyy-MM-dd') AS dt_week_accreditated,
    year,
    month,
    day
FROM
    datalake_airtable_raw.activated
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}