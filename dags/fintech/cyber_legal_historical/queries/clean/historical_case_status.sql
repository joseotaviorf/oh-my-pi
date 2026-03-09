SELECT
    CECASENO AS id_case,
    CEDOSSIERID AS id_dossier,
    CESSNUM AS id_client,
    CASE
        WHEN CESTATUS = 'N' THEN 'New'
        WHEN CESTATUS = 'A' THEN 'Active'
        WHEN CESTATUS = 'F' THEN 'Finalized'
        WHEN CESTATUS = 'P' THEN 'Pending'
        WHEN CESTATUS = 'C' THEN 'Completed'
        ELSE CESTATUS
    END AS case_status,
    CEREASON AS closure_reason,
    CERESULT AS closure_result,
    CESTATDT AS dt_status_changed,
    CEDTUPD AS ts_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_legal_historical_raw.case
