SELECT
    id,
    property_id AS id_property,
    lead_reply_email_id AS id_lead_reply_email,
    lead_reply_whatsapp_id AS id_lead_reply_whatsapp,
    external_lead_id AS id_external_lead,
    origin_partner,
    userddd AS user_ddd,
    user_email,
    user_message,
    user_name,
    user_phone_number,
    business_context,
    publication_type,
    received_at AS ts_received,
    NOW() AS ts_load
FROM datalake_classified_leads_raw.lead_contact
