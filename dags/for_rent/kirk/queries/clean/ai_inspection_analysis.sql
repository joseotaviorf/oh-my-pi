SELECT
    external_id AS id_inspection,
    contract_id AS id_contract,
    id AS id_analysis,
    analysis_status,
    analysis_mode,
    identified_repairs,
    error_details,
    model_version,
    policy_version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_kirk_raw.ai_inspection_analysis
