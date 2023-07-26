WITH zendesk_analysts AS (
    SELECT
        u.id_user AS id_agent,
        u.id_external AS id_user_external,
        u.id_organization,
        u.email,
        u.phone,
        u.name,
        split(replace(split(u.email, "@")[1], ".", " "), " ")[0] AS organization,
        u.is_active,
        u.ts_created,
        u.ts_created_local,
        u.ts_updated
    FROM
        datalake_zendesk_tickets_clean.users AS u
    WHERE
        LOWER(split(replace(split(u.email, "@")[1], ".", " "), " ")[0]) IN (SELECT DISTINCT LOWER(name) FROM datalake_zendesk_tickets_clean.organizations) 
),
bigfone_analysts AS (
    SELECT DISTINCT
        GET_JSON_OBJECT(metadata, '$.event_data.WorkerName') AS email,
        GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.full_name') AS name,
        GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location') AS organization
    FROM
        datalake_bigfone_clean.event
),
quinto_messenger_analysts AS (
    SELECT DISTINCT
        GET_JSON_OBJECT(assigned_to,'$.worker_name') AS email,
        split(replace(split(GET_JSON_OBJECT(assigned_to,'$.worker_name'), "@")[1], ".", " "), " ")[0] AS organization
    FROM
        datalake_quinto_messenger_clean.task
)
SELECT
    za.id_agent,
    za.id_user_external,
    za.id_organization,
    COALESCE(za.email, ba.email, qma.email) AS email,
    za.phone,
    COALESCE(za.name, ba.name) AS name,
    COALESCE(za.organization, ba.organization, qma.organization) AS organization,
    za.is_active,
    za.ts_created,
    za.ts_created_local,
    za.ts_updated
FROM 
    zendesk_analysts AS za
FULL OUTER JOIN
    bigfone_analysts AS ba
        ON za.email = ba.email
FULL OUTER JOIN
    quinto_messenger_analysts AS qma
        ON za.email = qma.email
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_updated DESC) = 1
