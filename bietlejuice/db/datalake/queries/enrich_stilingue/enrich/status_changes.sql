WITH status_changes AS (
    SELECT
        EXPLODE(status_changes) AS status_changes, 
        ts_load,
        year,
        month,
        day 
    FROM 
        datalake_stilingue_clean.calls_report 
)
SELECT
    status_changes.id,
    status_changes.conversationId AS id_conversation,
    status_changes.commentId AS id_comment,
    status_changes.calendarId AS id_calendar,
    status_changes.operator AS agent,
    status_changes.channel,
    status_changes.page,
    status_changes.oldValue AS old_status,
    status_changes.newValue AS new_status,
    status_changes.interactionType AS interaction_type,
    status_changes.timeToStatusChange AS time_status_change,
    status_changes.configuredSlaTimeSeconds AS predefined_sla,
    status_changes.insideSlaTime AS is_inside_sla,
    status_changes.endingStatus AS is_ending_status,
    status_changes.firstAnswer AS is_first_answer,
    TIMESTAMP_MILLIS(CAST(status_changes.relativeProcessedAt AS BIGINT)) AS ts_relative_processed,
    TIMESTAMP_MILLIS(CAST(status_changes.relativePostedAt AS BIGINT)) AS ts_relative_posted,
    TIMESTAMP_MILLIS(CAST(status_changes.createdAt AS BIGINT)) AS ts_created,
    ts_load, 
    year, 
    month, 
    day
FROM
    status_changes 