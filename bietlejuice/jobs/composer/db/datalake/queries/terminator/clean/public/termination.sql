SELECT
    id,
    contract_id AS id_contract,
    reason,
    date AS dt_termination,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.termination