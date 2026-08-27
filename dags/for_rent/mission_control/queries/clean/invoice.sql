SELECT
    id,
    contract_id AS id_contract,
    invoice_file_storage_id AS id_invoice_file_storage,
    received_file_storage_id AS id_received_file_storage,
    type,
    value AS invoice_amount,
    due_date AS ts_due,
    CAST(deleted AS BOOLEAN) AS is_deleted,
    created_on AS ts_created,
    updated_on AS ts_updated,
    year,
    month,
    day
FROM
    datalake_mission_control_raw.invoice
