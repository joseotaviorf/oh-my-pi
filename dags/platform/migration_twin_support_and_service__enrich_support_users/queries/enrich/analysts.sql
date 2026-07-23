WITH zendesk_tickets AS (
    SELECT DISTINCT
        id_assignee
    FROM
        datalake_zendesk_clean.tickets
),
zendesk_analysts AS (
    SELECT
        zt.id_assignee AS id_agent,
        zu.id_external AS id_user_external,
        zu.id_organization,
        zu.name,
        LOWER(zu.email) AS email,
        zu.phone,
        CASE
            WHEN zu.organization IS NULL AND zu.email LIKE "%ext%"
                THEN LOWER(SPLIT(REPLACE(SPLIT(zu.email, "@")[0], ".", " "), " ")[2])
            WHEN zu.organization IS NULL AND zu.email NOT LIKE "%ext%"
                THEN LOWER(SPLIT(REPLACE(SPLIT(zu.email, "@")[1], ".", " "), " ")[0])
            ELSE LOWER(zu.organization)
        END AS organization,
        zu.role,
        CAST(zu.is_active AS BOOLEAN) AS is_active,
        zu.ts_created,
        zu.ts_updated
    FROM
        zendesk_tickets AS zt
    LEFT JOIN
        datalake_support_users.zendesk_users AS zu
            ON zt.id_assignee = zu.id_user_zendesk
),
bigfone_analysts AS (
    SELECT DISTINCT
        COALESCE(
          GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid'),
          GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.worker_sid')
        ) AS id_agent,
        LOWER(GET_JSON_OBJECT(metadata, '$.event_data.WorkerName')) AS email,
        GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.full_name') AS name,
        CASE
            WHEN GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location') IS NULL
            AND GET_JSON_OBJECT(metadata, '$.event_data.WorkerName') LIKE "%ext%"
                THEN LOWER(SPLIT(REPLACE(SPLIT(GET_JSON_OBJECT(metadata, '$.event_data.WorkerName'), "@")[0], ".", " "), " ")[2])
            WHEN GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location') IS NULL
            AND GET_JSON_OBJECT(metadata, '$.event_data.WorkerName') NOT LIKE "%ext%"
                THEN LOWER(SPLIT(REPLACE(SPLIT(GET_JSON_OBJECT(metadata, '$.event_data.WorkerName'), "@")[1], ".", " "), " ")[0])
            ELSE LOWER(GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location'))
        END AS organization,
        ts_created
    FROM
        datalake_bigfone_clean.event
),
quinto_messenger_analysts AS (
    SELECT DISTINCT
        GET_JSON_OBJECT(assigned_to,'$.worker_sid') AS id_agent,
        LOWER(GET_JSON_OBJECT(assigned_to,'$.worker_name')) AS email,
        CASE
            WHEN GET_JSON_OBJECT(assigned_to,'$.worker_name') LIKE "%ext%"
                THEN LOWER(SPLIT(REPLACE(SPLIT(GET_JSON_OBJECT(assigned_to,'$.worker_name'), "@")[0], ".", " "), " ")[2])
            ELSE LOWER(SPLIT(REPLACE(SPLIT(GET_JSON_OBJECT(assigned_to,'$.worker_name'), "@")[1], ".", " "), " ")[0])
        END AS organization,
        ts_created
    FROM
        datalake_quinto_messenger_clean.task
),
twilio_analysts AS (
    SELECT
        id_agent,
        email,
        name,
        organization,
        ts_created
    FROM
        bigfone_analysts
    UNION ALL
    SELECT
        id_agent,
        email,
        NULL AS name,
        organization,
        ts_created
    FROM
        quinto_messenger_analysts
),
analysts AS (
    SELECT
        COALESCE(za.id_agent, td.id_agent) AS id_agent,
        td.id_agent AS id_agent_twilio,
        za.id_user_external,
        za.id_organization,
        COALESCE(za.name, td.name) AS name,
        COALESCE(za.email, td.email) AS email,
        za.phone,
        COALESCE(za.organization, td.organization) AS organization,
        role,
        is_active,
        COALESCE(za.ts_created,td.ts_created) AS ts_created,
        ts_updated
    FROM
        zendesk_analysts AS za
    FULL OUTER JOIN
        twilio_analysts AS td
            ON za.email = td.email
)
SELECT
    id_agent,
    id_agent_twilio,
    id_user_external,
    id_organization,
    email,
    name,
    phone,
    organization,
    role,
    is_active,
    ts_created,
    ts_updated
FROM
    analysts
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_created DESC) = 1
