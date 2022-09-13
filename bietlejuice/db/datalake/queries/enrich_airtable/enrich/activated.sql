WITH activated_last_version AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY cpf ORDER BY ts_updated DESC) AS ordered_version,
        id_airtable_record,
        ids_history,
        id_user,
        accreditations,
        agent_actual_type,
        agent_creci,
        agent_email,
        agent_name,
        agent_phone_number,
        cpf,
        disqualification,
        dynamic_status,
        last_area,
        last_disqualification,
        last_disqualification_reason,
        last_suspension,
        last_suspension_reason,
        permanent_deaccreditation,
        suspensions,
        suspensions_register,
        tickets_jira,
        days_since_activation_week,
        dt_activated,
        dt_last_disqualificated,
        dt_last_disqualification_returned,
        dt_last_suspended,
        dt_last_suspension_returned,
        dt_week_accreditated,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_airtable_clean.activated
),
id_user_changes AS (
    SELECT
        cpf,
        COUNT(DISTINCT id_user) - 1 AS number_of_id_user_changes
    FROM
        datalake_airtable_clean.activated
    GROUP BY 1
)
SELECT
    alv.id_airtable_record,
    alv.ids_history,
    alv.id_user,
    alv.accreditations,
    alv.agent_actual_type,
    alv.agent_creci,
    alv.agent_email,
    alv.agent_name,
    alv.agent_phone_number,
    alv.cpf,
    alv.disqualification,
    alv.dynamic_status,
    alv.last_area,
    alv.last_disqualification,
    alv.last_disqualification_reason,
    alv.last_suspension,
    alv.last_suspension_reason,
    iuc.number_of_id_user_changes,
    alv.permanent_deaccreditation,
    alv.suspensions,
    alv.suspensions_register,
    alv.tickets_jira,
    alv.days_since_activation_week,
    alv.dt_activated,
    alv.dt_last_disqualificated,
    alv.dt_last_disqualification_returned,
    alv.dt_last_suspended,
    alv.dt_last_suspension_returned,
    alv.dt_week_accreditated,
    alv.ts_updated,
    alv.year,
    alv.month,
    alv.day
FROM
    activated_last_version AS alv
LEFT JOIN
    id_user_changes AS iuc
        ON alv.cpf = iuc.cpf
WHERE
    ordered_version = 1
    AND id_user IS NOT NULL