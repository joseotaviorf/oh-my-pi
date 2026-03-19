SELECT
    id,
    contract_analysis_job_id AS id_contract_analysis_job,
    sales_flow_id AS id_sales_flow,
    raw_payload,
    person_uuid,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.contract_analysis_feedback_batch
