SELECT 
    id, 
    repair_request_item_id AS id_repair_request_item,
    rev, 
    revend AS rev_end, 
    CAST(revtype AS INTEGER) AS rev_type, 
    asset_url, 
    asset_url_mod AS mod_asset_url, 
    repair_request_item_id_mod AS mod_id_repair_request_item
FROM 
    datalake_repairs_raw.repair_evidence_aud 
