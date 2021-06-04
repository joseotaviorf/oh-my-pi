SELECT 
    id, 
    expense_id AS id_expense,
    repair_request_id AS id_repair_request, 
    rev, 
    revend AS rev_end, 
    revtype AS rev_type, 
    description AS repair_item_description,
    is_urgent, 
    expense_id_mod AS mod_id_expense, 
    repair_request_id_mod AS mod_id_repair_request,
    description_mod AS mod_repair_item_description, 
    is_urgent_mod AS mod_is_urgent 
FROM
    datalake_repairs_raw.repair_request_item_aud