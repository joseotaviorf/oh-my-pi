SELECT
    role_id AS id_role,
    requester_id AS id_requester,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_homolog_raw.requester_role
