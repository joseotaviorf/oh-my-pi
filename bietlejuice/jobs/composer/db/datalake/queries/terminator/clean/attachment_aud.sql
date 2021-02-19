SELECT
    id,
    termination_id AS id_termination,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    filename,
    path,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.attachment_aud
