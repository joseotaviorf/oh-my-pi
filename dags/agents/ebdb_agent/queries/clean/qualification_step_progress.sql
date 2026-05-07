SELECT
    id,
    qualification_id AS id_qualification,
    qualification_step_id AS id_qualification_step,
    author_identifier AS id_author_identifier,
    author_type,
    status,
    reason,
    changed_at AS ts_changed,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.QualificationStepProgress