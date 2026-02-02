SELECT
    CAST(id_proposal AS BIGINT) AS id_proposal,
    CAST(id_contract AS BIGINT) AS id_contract,
    CAST(ts_signature AS TIMESTAMP) AS ts_signature,
    group,
    motivo_identificado as identified_reason,
    motivo_macro as macro_reason,
    observacao_do_auditora as auditor_notes
FROM
    datalake_gsheets_raw.fraud_contracts