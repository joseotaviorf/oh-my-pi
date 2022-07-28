WITH agent_business_context_aud AS (
    SELECT
        aud.id_agent_data,
        aud.rev_type,
        aud.business_context,
        LEAD(FROM_UNIXTIME(ure.ts_revision/1000)) OVER (PARTITION BY aud.id_agent_data, aud.business_context ORDER BY rev) AS ts_agent_business_context_ended,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_updated
    FROM
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = aud.rev
    WHERE
        aud.rev_type IN (0,2)
)
SELECT
    id_agent_data,
    business_context AS agent_business_context,
    ts_updated AS ts_agent_business_context_started,
    ts_agent_business_context_ended
FROM
    agent_business_context_aud
WHERE
    rev_type <> 2