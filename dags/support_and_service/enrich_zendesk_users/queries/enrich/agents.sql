WITH zendesk_tickets AS (
    SELECT DISTINCT
        id_ticket,
        id_assignee
    FROM
        datalake_zendesk_tickets_clean.tickets
),
zendesk_analysts AS (
    SELECT
        zt.id_assignee AS id_agent,
        u.id_external AS id_user_external,
        u.id_organization,
        u.name,
        LOWER(u.email) AS email,
        u.phone,
        CASE 
            WHEN o.name IS NULL AND u.email LIKE "%ext%" 
                THEN LOWER(SPLIT(REPLACE(SPLIT(u.email, "@")[0], ".", " "), " ")[2])
            WHEN o.name IS NULL AND u.email NOT LIKE "%ext%" 
                THEN LOWER(SPLIT(REPLACE(SPLIT(u.email, "@")[1], ".", " "), " ")[0])
            ELSE LOWER(o.name)
        END AS organization,
        u.role,
        CAST(u.is_active AS BOOLEAN) AS is_active,
        u.ts_created,
        u.ts_created_local,
        u.ts_updated
    FROM
        zendesk_tickets AS zt
    LEFT JOIN
        datalake_zendesk_tickets_clean.users AS u
            ON zt.id_assignee = u.id_user
    LEFT JOIN
        datalake_zendesk_tickets_clean.organizations AS o
            ON u.id_organization = o.id 
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY zt.id_assignee ORDER BY u.ts_updated DESC) = 1
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
        event_timestamp AS ts_created
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
union_twilio_data AS (
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
consolidade_base_analysts AS (
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
        ts_created_local,
        ts_updated
    FROM
        zendesk_analysts AS za
    FULL OUTER JOIN
        union_twilio_data AS td
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
    ts_created_local,
    ts_updated
FROM
    consolidade_base_analysts AS u
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_created DESC) = 1
