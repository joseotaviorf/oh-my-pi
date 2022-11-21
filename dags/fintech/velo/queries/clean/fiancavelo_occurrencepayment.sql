SELECT
    id,
    propose As id_propose,
    customer As id_customer,
    billingtype AS id_billing_type,
    status AS id_status,
    gateway AS id_gateway,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    unicid,
    value,
    netvalue As net_value,
    invoiceurl AS invoice_url,
    description,
    BOOLEAN(active) AS is_active,
    duedate AS dt_due,
    datecreated AS dt_created,
    confirmeddate As dt_confirmed,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_occurrencepayment
