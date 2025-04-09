SELECT
    id,
    idempotency_id AS id_idempotency,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    source_type_code,
    status,
    version,
    status_mod AS mod_status,
    source_type_code_mod AS mod_source_type_code,
    idempotency_id_mod AS mod_id_idempotency,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.insurance_aud
