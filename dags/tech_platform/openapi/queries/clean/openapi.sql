SELECT 
    REGEXP_EXTRACT(file_path,'.*\/(.*)\/(.*)\/openapi\/latest\/original\/openapi\.yaml$',1) as repo,
    REGEXP_EXTRACT(file_path,'.*\/(.*)\/(.*)\/openapi\/latest\/original\/openapi\.yaml$',2) as app,
    path,
    method,
    operationId as id_operation,
    operation_description,
    element_at(security, 1).oauth2 as oauth2_scopes
FROM datalake_access_logs_raw.openapi