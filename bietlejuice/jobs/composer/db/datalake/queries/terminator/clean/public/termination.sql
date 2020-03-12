SELECT
    id,
    contract_id AS id_contract,
    reason,
    date AS dt_termination,
    created_at AS ts_created,
    updated_at AS ts_updated,
    status,
    canceled_at as ts_canceled,
    vacancy_date as dt_vacancy,
    source
FROM
    datalake_terminator_raw.termination