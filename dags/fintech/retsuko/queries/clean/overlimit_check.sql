SELECT
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    reference_id AS id_reference,
    reference_type,
    status,
    verified_by AS id_verified_by,
    timestamp(verified_at) AS ts_verified,
    fixed_by AS id_fixed_by,
    timestamp(fixed_at) AS ts_fixed,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated
FROM
    datalake_retsuko_raw.overlimit_check
