SELECT
    id,
    contract_id AS id_contract,
    reason,
    date AS dt_termination,
    created_at AS ts_created,
    updated_at AS ts_updated,
    status,
    canceled_at AS ts_canceled,
    vacancy_date AS dt_vacancy,
    source,
    requested_by,
    exit_inspection_id AS id_exit_inspection,
    feedback
FROM
    datalake_terminator_raw.termination
