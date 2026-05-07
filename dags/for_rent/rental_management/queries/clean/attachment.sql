SELECT
    id,
    blob_vault_id AS uuid_blob_vault,
    password,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.attachment
