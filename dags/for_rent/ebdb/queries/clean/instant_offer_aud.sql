SELECT
    id,
    house_id AS id_house,
    rev,
    revtype AS rev_type,
    enabled AS is_enabled,
    enabled_mod AS mod_is_enabled
FROM
    datalake_ebdb_raw.instantoffer_aud
