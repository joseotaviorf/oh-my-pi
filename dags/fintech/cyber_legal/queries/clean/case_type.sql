SELECT
    CTTYPE AS id_case_type,
    CTDESC AS case_type_description,
    CTDWFLOW AS default_workflow_code,
    IF(CTVSTG = 'Y', TRUE, FALSE) AS is_sequential_stage_validation,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.casetype
