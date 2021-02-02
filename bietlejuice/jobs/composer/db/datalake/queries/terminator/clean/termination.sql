SELECT
    id,
    contract_id AS id_contract,
    exit_inspection_id AS id_exit_inspection,
    feedback,
    tenant_keys_location,
    owner_keys_location,
    requested_by,
    source,
    status,
    internal_status, 
    date AS dt_termination,
    vacancy_date AS dt_vacancy,
    canceled_at AS ts_canceled,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.termination
