SELECT
    mapping.requisition_code,
    mapping.job_opening_id,
    mapping.status,
    mapping.ts_load
FROM
    datalake_gsheets_people_raw.mapping_wb_to_gh AS mapping
