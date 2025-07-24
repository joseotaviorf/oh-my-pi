SELECT
    pk_id AS id_pk,
    id,
    lead_id as id_lead,
    user_email,
    NOW() AS ts_load
FROM datalake_classified_leads_raw.lead_reply_email
