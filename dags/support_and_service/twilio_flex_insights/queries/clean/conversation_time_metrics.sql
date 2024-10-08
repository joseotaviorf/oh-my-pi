SELECT
    conversation AS id_conversation,
    segment AS id_segment,
    conversation_attribute_4 AS id_reservation,
    CAST(total_queue_time AS FLOAT) AS total_queue_time,
    CAST(total_talk_time AS FLOAT) AS total_talk_time,
    CAST(total_wrap_up_time AS FLOAT) AS total_wrap_up_time,
    CAST(total_handling_time AS FLOAT) AS total_handling_time,
    CAST(`total_waiting_time_[deprecated]` AS FLOAT) AS total_waiting_time,
    CAST(first_reply_time AS FLOAT) AS first_reply_time,
    year,
    month,
    day
FROM
    datalake_twilio_flex_insights_raw.conversation_time_metrics
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
