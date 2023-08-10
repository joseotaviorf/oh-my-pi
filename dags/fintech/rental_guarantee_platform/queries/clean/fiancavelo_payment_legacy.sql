SELECT
    CAST(id AS BIGINT) AS id,
    CAST(propose AS BIGINT) AS id_propose,
    subscription AS id_subscription,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    customer,
    paymentlink AS payment_link,
    invoiceurl AS invoice_url,
    unicid,
    description,
    gateway,
    status,
    quintocred_status,
    billingtype AS billing_type,
    quintocred_billing_type,
    value,
    netvalue,
    active AS is_active,
    duedate AS ts_due,
    originalduedate AS ts_due_original,
    clientpaymentdate AS ts_client_payment,
    confirmeddate AS ts_confirmed,
    datecreated AS ts_created,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.fiancavelo_payment_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
