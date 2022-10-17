WITH conversations AS (
    SELECT
        EXPLODE(conversations) AS conversations, 
        ts_load,
        year,
        month,
        day 
    FROM 
        datalake_stilingue_clean.calls_report 
)
SELECT
    conversations.conversationId AS id_conversation,
    conversations.channel,
    conversations.page,
    conversations.interactionType AS interaction_type,
    conversations.status,
    CAST(conversations.interactionsSize AS BIGINT) AS number_of_interactions,
    conversations.firstAnswerConfiguredSlaTimeSeconds AS predefined_sla,
    conversations.timeToFirstAnswer AS time_first_answer,
    conversations.firstAnswerIsInsideSlaTime AS is_first_answer_sla,
    TIMESTAMP_MILLIS(CAST(conversations.iniAt AS BIGINT)) AS ts_initial,
    ts_load, 
    year, 
    month, 
    day
FROM
    conversations 