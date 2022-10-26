SELECT
    id,
    property_id as id_property,
    lead_reply_email_id as id_lead_reply_email,
    lead_reply_whatsapp_id as id_lead_reply_whatsapp,
    external_lead_id as id_external_lead,
    origin_partner,
    userddd as user_ddd,
    user_email,
    user_message,
    user_name,
    user_phone_number,
    business_context,
    publication_type,
    received_at as ts_received
FROM datalake_classified_leads_raw.lead_contact