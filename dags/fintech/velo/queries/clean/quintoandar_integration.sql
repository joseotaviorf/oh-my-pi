SELECT
    id,
    url,
    method,
    request,
    response,
    response_status,
    dateinsert AS ts_inserted
FROM
    datalake_velo_raw.quintoandar_integration
