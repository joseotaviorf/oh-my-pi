SELECT
    id,
    sales_flow_id AS id_sales_flow,
    ccv_id AS id_ccv,
    legocontract_execution_id AS id_legocontract_execution,
    person_id AS id_person,
    signed_document_token,
    payload_fields_hash,
    legalops_saved_fields,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ai_legal_analysis_lego_contract_execution
