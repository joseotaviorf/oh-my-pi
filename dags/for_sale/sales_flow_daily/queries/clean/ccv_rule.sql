SELECT 
    id AS id_ccv_rule,
    ccv_version,
    type,
    name AS ccv_rule_name,
    storage_hash_token,
    checksum,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_rule
