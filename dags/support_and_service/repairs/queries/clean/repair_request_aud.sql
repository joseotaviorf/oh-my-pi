SELECT 
    id, 
    contract_id AS id_contract, 
    house_id AS id_house, 
    requester_user_id AS id_requester_user,
    third_party_crm_ticket_external_id AS id_third_party_crm_ticket_external,
    rev, 
    revend AS rev_end, 
    CAST(revtype AS INTEGER) AS rev_type,
    allow_personal_info_sharing,
    status, 
    third_party_crm,
    contract_id_mod AS mod_id_contract, 
    house_id_mod AS mod_id_house, 
    requester_user_id_mod AS mod_id_requester_user,
    third_party_crm_ticket_external_id_mod AS mod_id_third_party_crm_ticket_external,
    status_mod AS mod_status,
    third_party_crm_mod AS mod_third_party_crm 
FROM
    datalake_repairs_raw.repair_request_aud 
