WITH agent_business_context_aud AS (
    SELECT
        id_agent_data,
        aud.rev_type,
        aud.business_context
        FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000) AS ts_update,
        TRUNC(FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000), 'day') AS dt_updated
    FROM
        datalake_ebdb_clean.agent_data_business_contexts_served_aud AS aud
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = aud.rev
),
agent_business_context_history AS (
    SELECT
        id_agent_data,
        business_context AS agent_business_context,
        ts_update AS ts_agent_business_context_start,
        LEAD(ts_update) OVER (PARTITION BY id_agent_data ORDER BY ts_update) AS ts_agent_business_context_end
    FROM
        agent_business_context_aud
    WHERE
        rev_type <> 2
)
SELECT
    *
FROM
    agent_business_context_history