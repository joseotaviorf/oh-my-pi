SELECT
    id,
    pix_key,
    requested_by,
    bank AS bank_name,
    bank_fee,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_pixar_raw.account
