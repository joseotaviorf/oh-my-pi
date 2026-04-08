SELECT
    id,
    contract_analysis_job_id AS id_contract_analysis_job,
    sales_flow_id AS id_sales_flow,
    status,
    request_payload,
    contract_analysis_result,
    error_message,
    analysis_started_at,
    analysis_ended_at,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.contract_analysis_request