SELECT
    id,
    usuario_id AS id_user,
    confirmation_code,
    signed_term AS is_term_signed,
    signed_time AS ts_term_signed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.bypassterm
