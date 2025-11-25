SELECT
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    activated_by_audit_id AS id_activated_by_audit,
    deactivated_by_audit_id AS id_deactivated_by_audit,
    reason,
    description,
    status,
    timestamp(activated_at) AS ts_activated,
    timestamp(deactivated_at) AS ts_deactivated,
    timestamp(synced_at) AS ts_synced
FROM
    datalake_retsuko_raw.payment_block
