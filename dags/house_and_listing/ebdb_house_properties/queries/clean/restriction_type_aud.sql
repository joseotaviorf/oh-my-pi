SELECT
    id AS id_restriction_type,
    REV AS rev,
    REVTYPE AS rev_type,
    name,
    name_MOD AS mod_name
FROM
    datalake_ebdb_raw.`restrictiontype_aud`