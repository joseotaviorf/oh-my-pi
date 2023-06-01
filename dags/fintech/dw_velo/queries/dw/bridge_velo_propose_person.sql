SELECT
    id_person AS sk_person,
    id_propose AS sk_propose,
    is_primary_person,
    TRUE AS is_legacy,
    NOW() AS ts_load
FROM
    datalake_velo.propose_person
UNION ALL
SELECT
    id AS sk_person,
    id_propose AS sk_propose,
    id_propose_person_type = 3 AS is_primary_person,-- "Responsável Principal"
    FALSE AS is_legacy,
    NOW() AS ts_load
FROM
    datalake_rental_guarantee_platform_clean.propose_person
