SELECT
    campaign_id AS id_campaign,
    messages,
    conversions_by_send_time,
    conversions1_by_send_time,
    conversions2_by_send_time,
    conversions3_by_send_time,
    conversions,
    conversions1,
    conversions2,
    conversions3,
    unique_recipients,
    revenue,
    TO_TIMESTAMP(`time`) AS ts_campaign_analytics_time
FROM
    datalake_braze_raw.campaigns_analytics_owners