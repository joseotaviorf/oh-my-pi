SELECT
    id,
    propose AS id_propose,
    tenant AS id_tenant,
    type AS id_type,
    status AS id_status,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    value,
    originalvalue AS original_value,
    paid As paid_value,
    unicid,
    invoiceurl As invoice_url,
    description,
    BOOLEAN(valid) AS is_valid,
    BOOLEAN(active) AS is_active,
    duedate AS dt_due,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_occurrence
