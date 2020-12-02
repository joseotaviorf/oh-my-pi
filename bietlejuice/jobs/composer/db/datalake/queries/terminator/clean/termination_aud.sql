SELECT
    id,
    contract_id AS id_contract,
    exit_inspection_id AS id_exit_inspection,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    feedback,
    status,
    source,
    requested_by,
    date AS dt_termination,
    vacancy_date AS dt_vacancy,
    canceled_at AS ts_canceled,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.termination_aud
