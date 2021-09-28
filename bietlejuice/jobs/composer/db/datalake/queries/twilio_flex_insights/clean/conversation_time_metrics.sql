SELECT
    conversation AS id_conversation,
    segment AS id_segment,
    CAST(total_queue_time AS FLOAT) AS total_queue_time,
    CAST(total_talk_time AS FLOAT) AS total_talk_time,
    CAST(total_wrap_up_time AS FLOAT) AS total_wrap_up_time,
    CAST(total_handling_time AS FLOAT) AS total_handling_time,
    date AS dt_created,
    year,
    month,
    day
FROM
    datalake_twilio_flex_insights_raw.conversation_time_metrics