SELECT 
    id AS id_account, 
    name, 
    name_tree, 
    "type", 
    currency, 
    track_balance, 
    balance, 
    allows_overdraft, 
    metadata, 
    TIMESTAMP(created_at) AS ts_created, 
    TIMESTAMP(updated_at) AS ts_updated
FROM 
    datalake_ledger_raw.account