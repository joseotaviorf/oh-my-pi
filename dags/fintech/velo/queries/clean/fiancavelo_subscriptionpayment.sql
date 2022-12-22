SELECT
    id,
    propose AS id_propose,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    status AS id_status,
    billingtype AS id_billing_type,
    unicid,
    customer,
    description,
    cycle,
    value,
    BOOLEAN(deleted) AS is_deleted,
    BOOLEAN(active) AS is_active,
    nextduedate AS dt_next_due,
    datecreated AS dt_created,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_subscriptionpayment
