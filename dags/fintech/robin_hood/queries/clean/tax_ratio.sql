SELECT 
    id, 
    tax_id AS id_tax, 
    source_id AS id_source,
    locale, 
    cost_center_code, 
    amount, 
    created_at AS ts_created, 
    synced_at AS ts_synced
FROM 
    datalake_robin_hood_raw.tax_ratio