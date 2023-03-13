SELECT
    ctm.conversation AS id_conversation,
    ctm.segment AS id_segment,
    CAST(ctm.total_queue_time AS FLOAT) AS total_queue_time,
    CAST(ctm.total_talk_time AS FLOAT) AS total_talk_time,
    CAST(ctm.total_wrap_up_time AS FLOAT) AS total_wrap_up_time,
    CAST(ctm.total_handling_time AS FLOAT) AS total_handling_time,
    CAST(ctm.date AS DATE) AS dt_created,
    ctm.year,
    ctm.month,
    ctm.day
FROM
    datalake_twilio_flex_insights_raw.conversation_time_metrics AS ctm
