WITH cases AS (
    SELECT
        EXPLODE(cases) AS cases, 
        ts_load,
        year,
        month,
        day 
    FROM 
        datalake_stilingue_clean.calls_report 
)
SELECT
    cases.caseId AS id_case,
    cases.conversationId AS id_conversation,
    cases.channel,
    cases.page,
    cases.status,
    cases.interactionType AS interaction_type,
    TIMESTAMP_MILLIS(CAST(cases.initAt AS BIGINT)) AS ts_initial,
    ts_load, 
    year, 
    month, 
    day
FROM
    cases