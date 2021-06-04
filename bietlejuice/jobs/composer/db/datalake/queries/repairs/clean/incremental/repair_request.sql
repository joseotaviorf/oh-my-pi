SELECT 
    id,
    contract_id AS id_contract, 
    house_id AS id_house, 
    requester_user_id AS id_requester_user, 
    third_party_crm_ticket_external_id AS id_third_party_crm_ticket_external,
    allow_personal_info_sharing, 
    third_party_crm,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year, 
    month, 
    day
FROM 
    datalake_repairs_raw.repair_request 
WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}


