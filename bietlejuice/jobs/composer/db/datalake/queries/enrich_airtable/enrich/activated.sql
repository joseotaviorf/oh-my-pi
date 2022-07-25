WITH activated_last_version AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY DATE(CONCAT(year, '-', month, '-', day)) DESC) AS ordered_version,
        id_user,
        agent_actual_type,
        agent_creci,
        agent_email,
        agent_phone_number,
        cpf,
        dynamic_status,
        last_area,
        last_suspension,
        status,
        suspensions,
        suspensions_register,
        tickets_jira,
        days_since_activation_week,
        dt_activated,
        dt_last_suspended,
        dt_week_accreditated,
        year,
        month,
        day
    FROM
        datalake_airtable_clean.activated
)
SELECT
    id_user,
    agent_actual_type,
    agent_creci,
    agent_email,
    agent_phone_number,
    cpf,
    dynamic_status,
    last_area,
    last_suspension,
    status,
    suspensions,
    suspensions_register,
    tickets_jira,
    days_since_activation_week,
    dt_activated,
    dt_last_suspended,
    DATE(CONCAT(year, '-', month, '-', day)) AS dt_updated,
    dt_week_accreditated,
    year,
    month,
    day
FROM
    activated_last_version
WHERE
    ordered_version = 1
    AND id_user IS NOT NULL