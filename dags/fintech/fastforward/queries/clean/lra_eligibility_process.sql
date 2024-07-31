SELECT
    id,
    contract_external_id AS id_contract_external,
    option_bucket,
    file_name,
    status,
    status_reason,
    is_eligible,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_fastforward_raw.lra_eligibility_process
