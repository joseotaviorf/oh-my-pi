SELECT
    id,
    usuario_id AS id_user,
    REV AS rev,
    REVTYPE AS rev_type,
    confirmation_code,
    usuario_id_MOD AS mod_id_user,
    confirmation_code_MOD AS mod_confirmation_code,
    signed_term_MOD AS mod_is_term_signed,
    signed_time_mod AS mod_ts_term_signed,
    signed_term AS is_term_signed,
    signed_time AS ts_term_signed,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.bypassterm_AUD
