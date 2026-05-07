SELECT
    id,
    qualification_step_uuid AS uuid_qualification_step,
    description,
    name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.QualificationStep