SELECT
    id,
    person_uuid AS uuid_person,
    status,
    effective_date AS ts_effective,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentContact
