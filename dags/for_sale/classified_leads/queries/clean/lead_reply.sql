SELECT
    id,
    sent_at AS ts_sent_at,
    NOW() AS ts_load
FROM datalake_classified_leads_raw.lead_reply
