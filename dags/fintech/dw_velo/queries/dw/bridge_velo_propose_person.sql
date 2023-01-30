SELECT
    id_person AS sk_person,
    id_propose AS sk_propose,
    is_primary_person,
    NOW() AS ts_load
FROM
    datalake_velo.propose_person
