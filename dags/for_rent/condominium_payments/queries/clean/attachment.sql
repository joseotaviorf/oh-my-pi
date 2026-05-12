SELECT
    CAST(id AS BIGINT) AS id,
    CAST(invoice_id AS BIGINT) AS id_invoice,
    blob_vault_id AS id_blob_vault,
    mime_type,
    source_url,
    file_password,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_condominium_payments_raw.attachment
