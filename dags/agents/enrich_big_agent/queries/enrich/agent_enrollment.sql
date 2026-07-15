WITH enrollment AS (
    SELECT
        id AS id_enrollment,
        id_agent,
        id_program,
        ROW_NUMBER() OVER(PARTITION BY e.id_agent ORDER BY e.ts_updated DESC) = 1 AS is_last_enrollment_by_agent,
        ts_created AS ts_enrollment_started,
        COALESCE(
            LEAD(ts_updated) OVER(PARTITION BY e.id_agent ORDER BY e.ts_updated),
            NOW()
        ) AS ts_enrollment_ended
    FROM
        datalake_big_agent_clean.enrollment AS e
),
agent AS (
    SELECT
        a.id,
        COALESCE(
            GET_JSON_OBJECT(a.details, '$.userExternalId'),
            pa.id_user
        ) AS id_user,
        GET_JSON_OBJECT(a.details, '$.partnerExternalId') AS id_partner,
        e.id_enrollment,
        e.id_program,
        p.name AS consultant_type,
        e.is_last_enrollment_by_agent,
        CAST(GET_JSON_OBJECT(a.details, '$.active') AS BOOLEAN) AS is_agent_active,
        e.ts_enrollment_started,
        e.ts_enrollment_ended,
        COALESCE(TIMESTAMP(GET_JSON_OBJECT(a.details, '$.registeredAt')), a.ts_created) AS ts_agent_registered,
        a.ts_updated AS ts_agent_updated,
        a.year,
        a.month,
        a.day
    FROM
        datalake_big_agent_clean.agent AS a
    LEFT JOIN
        datalake_ebdb_clean.partner_agent AS pa
            ON GET_JSON_OBJECT(a.details, '$.partnerExternalId') = pa.id_partner 
    LEFT JOIN
        enrollment AS e
            ON e.id_agent = a.id
    LEFT JOIN 
        datalake_big_agent_clean.program AS p
            ON e.id_program = p.id
    WHERE
        a.ts_updated BETWEEN '{load_start_date}' AND '{load_end_date}'
),
agent_domain AS (
    SELECT
        id_user,
        id_agent,
        id_agent_data,
        uuid_agent,
        uuid_person,
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY IF(status = 'ACTIVE', 1, 0) DESC, ts_updated DESC) = 1 AS is_last_agent_domain_by_user
    FROM
        datalake_agent_accreditation.agent AS agent_domain
)
SELECT
    CONCAT(a.id, '_', a.id_enrollment) AS id_agent_enrollment,
    a.id AS id_internal_agent,
    ag.id_agent,
    a.id_user,
    a.id_partner,
    ag.id_agent_data,
    a.id_enrollment,
    a.id_program,
    ag.uuid_agent,
    ag.uuid_person,
    a.consultant_type,
    a.is_last_enrollment_by_agent,
    a.is_agent_active,
    a.ts_enrollment_started,
    a.ts_enrollment_ended,
    a.ts_agent_registered,
    a.ts_agent_updated,
    a.year,
    a.month,
    a.day
FROM
    agent AS a
LEFT JOIN
    agent_domain AS ag
        ON a.id_user = ag.id_user
        AND ag.is_last_agent_domain_by_user = True
