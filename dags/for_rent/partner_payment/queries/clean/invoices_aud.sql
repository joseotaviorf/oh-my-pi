SELECT
    id,
    blobvault_invoice_id AS uuid_blobvault_invoice,
    blobvault_invoice_id_mod AS uuid_blobvault_invoice_mod,
    rev,
    revend,
    revtype,
    status,
    version,
    status_mod,
    version_mod,
    upload_date AS dt_upload,
    upload_date_mod AS dt_upload_mod,
    created_at AS ts_created,
    created_at_mod AS ts_created_mod,
    updated_at AS ts_updated,
    updated_at_mod AS ts_updated_mod
FROM
    datalake_partner_payment_raw.invoices_aud
