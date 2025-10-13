SELECT 
    external_id as id_inspection,
    contract_id as id_contract,
    id as id_analysis,
    analysis_status,
    identified_repairs,
    error_details,
    model_version,
    policy_version,
    created_at as ts_created,
    updated_at as ts_updated
FROM datalake_kirk_raw.ai_inspection_analysis