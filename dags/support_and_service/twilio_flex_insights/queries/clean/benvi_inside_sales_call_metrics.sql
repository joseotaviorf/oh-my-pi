SELECT
    NULLIF(handling_team, '') AS handling_team,
    NULLIF(communication_channel, '') AS communication_channel,
    NULLIF(agent, '') AS agent_name,
    CAST(COALESCE(NULLIF(all_calls, ''), 0) AS INTEGER) AS all_calls,
    CAST(COALESCE(NULLIF(answered_outbound_calls, ''), 0) AS INTEGER) AS answered_outbound_calls,
    CAST(COALESCE(NULLIF(abandoned_conversations, ''), 0) AS INTEGER) AS abandoned_conversations,
    CAST(COALESCE(NULLIF(total_handling_time, ''), 0) AS FLOAT) AS total_handling_time,
    CAST(date AS DATE) AS dt_created,
    year,
    month,
    day
FROM
    datalake_twilio_flex_insights_raw.benvi_inside_sales_call_metrics