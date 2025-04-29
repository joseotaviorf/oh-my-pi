WITH agent_current_program AS (
    SELECT 
        a.id AS id_agent,
        pa.id_user AS id_user,
        pa.id_partner AS id_partner,
        p.name AS consultant_type,
        ROW_NUMBER() OVER(PARTITION BY COALESCE(pa.id_user, a.id) ORDER BY e.ts_updated DESC) = 1 AS is_last_enrollment,
        a.ts_updated AS ts_agent_updated,
        e.ts_updated AS ts_enrollment_updated
    FROM
        datalake_big_agent_clean.agent AS a
    LEFT JOIN
        datalake_big_agent_clean.enrollment AS e 
            ON e.id_agent = a.id
    LEFT JOIN 
        datalake_big_agent_clean.program AS p
            ON e.id_program = p.id
    LEFT JOIN
        datalake_ebdb_clean.partner_agent AS pa
            ON GET_JSON_OBJECT(a.details, '$.partnerExternalId') = pa.id_partner        
)
SELECT
    id_agent,
    id_user,
    id_partner,
    consultant_type,
    ts_agent_updated,
    ts_enrollment_updated
FROM
    agent_current_program
WHERE
    is_last_enrollment = True