SELECT 
    id AS id_message, 
    incremental_id AS id_incremental, 
    destination, 
    headers, 
    payload, 
    published, 
    message_partition, 
    creation_time, 
    TIMESTAMP(creation_datetime) AS ts_creation_datetime
FROM 
    datalake_ledger_raw.message