SELECT 
    id,
    repair_request_id AS id_repair_request, 
    third_party_crm_ticket_external_id AS id_third_party_crm_ticket_external,
    rev,
    revend AS rev_end,
    CAST(revtype AS INTEGER) AS rev_type,
    status,
    type, 
    third_party_crm,
    status_mod AS mod_status
FROM 
    datalake_repairs_raw.service_request_aud