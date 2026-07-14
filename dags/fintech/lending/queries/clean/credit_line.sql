SELECT
    id,
    uuid,
    person_uuid AS uuid_person,
    approved_limit,
    max_draws,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.credit_line
