SELECT
    id,
    bill_id AS id_bill,
    blobvault_invoice_id AS uuid_blobvault_invoice,
    status,
    version,
    upload_date AS dt_upload,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.invoices
