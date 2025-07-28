SELECT
    pk_id AS id_pk,
    id,
    lead_id AS id_lead,
    user_phone_number,
    NOW() AS ts_load
FROM datalake_classified_leads_raw.lead_reply_whatsapp
