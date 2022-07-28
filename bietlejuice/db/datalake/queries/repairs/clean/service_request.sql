SELECT 
    id,
    repair_request_id AS id_repair_request, 
    third_party_crm_ticket_external_id AS id_third_party_crm_ticket_external,
    status,
    type, 
    third_party_crm,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year, 
    month, 
    day
FROM 
    datalake_repairs_raw.service_request 
WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}