SELECT
    id,
    lead_id AS id_lead,
    bsp_contact_id AS id_bsp_contact,
    bsp_conversation_id AS id_bsp_conversation,
    crm_id AS id_crm,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_consorcio_raw.lead_external_data
