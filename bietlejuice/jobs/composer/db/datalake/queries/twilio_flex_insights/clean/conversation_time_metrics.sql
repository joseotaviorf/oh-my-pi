SELECT
    conversation AS id_conversation,
    conversation_attribute_4 AS id_reservation,
    segment AS id_segment,
    CAST(queue_time AS FLOAT) AS queue_time,
    CAST(talk_time AS FLOAT) AS talk_time,
    CAST(wrap_up_time AS FLOAT) AS wrap_up_time,
    CAST(handling_time AS FLOAT) AS handling_time,
    date AS dt_created,
    year,
    month,
    day
FROM
    datalake_twilio_flex_insights_raw.conversation_time_metrics