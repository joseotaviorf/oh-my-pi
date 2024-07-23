SELECT
    id as id_user,
    external_id as id_external,
    rev,
    revtype as rev_type,
    revend as rev_end,
    name
FROM
    datalake_fastforward_homolog_raw.users_aud
