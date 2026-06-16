SELECT
    id,
    lego_contract_execution_id AS id_legocontract_execution,
    type,
    field,
    old_value,
    new_value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ai_legal_analysis_lego_contract_execution_change_log
