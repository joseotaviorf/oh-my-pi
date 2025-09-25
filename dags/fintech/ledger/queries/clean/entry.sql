SELECT 
    id AS id_entry, 
    transaction_id AS id_transaction, 
    account_name AS account_name, 
    amount AS amount, 
    "type" AS type, 
    metadata AS metadata
FROM 
    datalake_ledger_raw.entry