WITH business_contexts AS (
    SELECT
        aud.id_agent_data AS id_agent,
        aud.business_context,
        aud.rev_type,
        u.ts_revision AS ts_revision_started,
        LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.business_context ORDER BY u.ts_revision) AS ts_revision_ended,
        COALESCE(
            LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.business_context ORDER BY u.ts_revision),
            '{load_end_date}'
        ) AS ts_updated
    FROM
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = aud.rev
    WHERE
        DATE(u.ts_revision) <= DATE('{load_end_date}')
)
SELECT
    XXHASH64(bc.id_agent, bc.business_context, bc.ts_revision_started) AS id_agent_business_context,
    bc.id_agent,
    bc.business_context,
    bc.ts_revision_started,
    bc.ts_revision_ended
FROM
    business_contexts AS bc
WHERE
    bc.rev_type <> 2
    AND DATE(bc.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    1 = ROW_NUMBER() OVER (
        PARTITION BY id_agent_business_context
        ORDER BY bc.ts_revision_started, COALESCE(bc.ts_revision_ended, bc.ts_updated) DESC
    )