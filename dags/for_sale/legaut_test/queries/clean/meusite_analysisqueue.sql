SELECT
    id,
    unit_id AS id_unit,
    user_id AS id_user,
    active,
    status,
    tries,
    started AS has_started,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_legaut_test_raw.meuSite_analysisqueue
