SELECT
    id,
    contract_id AS id_contract,
    exit_inspection_id AS id_exit_inspection,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    feedback,
    tenant_keys_location,
    owner_keys_location,
    status,
    internal_status,
    source,
    requested_by,
    date AS dt_termination,
    vacancy_date AS dt_vacancy,
    canceled_at AS ts_canceled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_raw.termination_aud
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
