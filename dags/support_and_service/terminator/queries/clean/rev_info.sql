SELECT
    user_id AS id_user,
    rev,
    revtstmp AS ts_rev
FROM
    datalake_terminator_raw.revinfo
